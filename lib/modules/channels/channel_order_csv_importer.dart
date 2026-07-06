/// Pure CSV → channel-order parser (Phase 5). Database-free: it turns the
/// row-per-line order export every storefront can produce (one CSV row per
/// order line, orders grouped by their order reference) into normalised
/// order records the import service saves as `Channel Order` documents.
///
/// Same tolerances as the bank-statement importer: delimiter auto-detected
/// (comma / semicolon / tab), columns mapped from header names so order
/// doesn't matter, US/EU number formats, ISO or day-first dates.
library;

/// One order line as exported by the storefront — still in channel terms
/// (SKU, not Item).
class ParsedChannelOrderLine {
  const ParsedChannelOrderLine({
    required this.sku,
    required this.qty,
    required this.rate,
    this.description,
  });

  final String sku;
  final num qty;
  final num rate;
  final String? description;

  num get amount => qty * rate;
}

/// One storefront order: the rows of the CSV that share an order reference.
class ParsedChannelOrder {
  const ParsedChannelOrder({
    required this.externalId,
    required this.lines,
    this.orderDate,
    this.customerName,
    this.customerEmail,
  });

  final String externalId;
  final String? orderDate; // ISO yyyy-MM-dd
  final String? customerName;
  final String? customerEmail;
  final List<ParsedChannelOrderLine> lines;

  num get grossTotal =>
      lines.fold<num>(0, (sum, line) => sum + line.amount);
}

/// The result of parsing a CSV: orders understood (in file order) and how
/// many data rows were skipped (no order reference, SKU, or readable qty).
class ChannelOrdersImport {
  const ChannelOrdersImport({required this.orders, required this.skipped});
  final List<ParsedChannelOrder> orders;
  final int skipped;
}

/// Which CSV column index holds which field, resolved from the header row.
class _Columns {
  int? order, date, sku, description, qty, rate, customer, email;
  bool get usable => order != null && sku != null;
}

abstract final class ChannelOrderCsvImporter {
  static ChannelOrdersImport parse(String csv) {
    final rows = _rows(csv);
    if (rows.isEmpty) return const ChannelOrdersImport(orders: [], skipped: 0);

    // Find the header and delimiter together (same approach as the bank
    // importer): the first row that maps to usable columns under some
    // candidate delimiter.
    _Columns? cols;
    var delimiter = ',';
    var dataStart = 0;
    for (var i = 0; i < rows.length && i < 20 && cols == null; i++) {
      if (rows[i].trim().isEmpty) continue;
      for (final d in _delimiters) {
        final candidate = _mapColumns(_split(rows[i], d));
        if (candidate.usable) {
          cols = candidate;
          delimiter = d;
          dataStart = i + 1;
          break;
        }
      }
    }
    if (cols == null) return const ChannelOrdersImport(orders: [], skipped: 0);

    // Group rows by order reference, keeping first-seen order of orders.
    final orderIds = <String>[];
    final linesByOrder = <String, List<ParsedChannelOrderLine>>{};
    final dateByOrder = <String, String>{};
    final nameByOrder = <String, String>{};
    final emailByOrder = <String, String>{};
    var skipped = 0;

    for (var i = dataStart; i < rows.length; i++) {
      if (rows[i].trim().isEmpty) continue;
      final cells = _split(rows[i], delimiter);
      String? at(int? c) =>
          (c != null && c >= 0 && c < cells.length) ? cells[c].trim() : null;

      final orderId = at(cols.order) ?? '';
      final sku = at(cols.sku) ?? '';
      final qty = _parseAmount(at(cols.qty) ?? '') ?? 1;
      final rate = _parseAmount(at(cols.rate) ?? '') ?? 0;
      if (orderId.isEmpty || sku.isEmpty || qty <= 0) {
        skipped++;
        continue;
      }

      if (!linesByOrder.containsKey(orderId)) orderIds.add(orderId);
      final description = at(cols.description);
      (linesByOrder[orderId] ??= []).add(ParsedChannelOrderLine(
        sku: sku,
        qty: qty,
        rate: rate,
        description: (description != null && description.isNotEmpty)
            ? description
            : null,
      ));
      // Header-level fields: the first non-empty value per order wins.
      final date = _parseDate(at(cols.date) ?? '');
      if (date != null) dateByOrder.putIfAbsent(orderId, () => date);
      final name = at(cols.customer);
      if (name != null && name.isNotEmpty) {
        nameByOrder.putIfAbsent(orderId, () => name);
      }
      final email = at(cols.email);
      if (email != null && email.isNotEmpty) {
        emailByOrder.putIfAbsent(orderId, () => email);
      }
    }

    return ChannelOrdersImport(
      orders: [
        for (final id in orderIds)
          ParsedChannelOrder(
            externalId: id,
            orderDate: dateByOrder[id],
            customerName: nameByOrder[id],
            customerEmail: emailByOrder[id],
            lines: linesByOrder[id]!,
          ),
      ],
      skipped: skipped,
    );
  }

  // ---- rows / delimiter (same mechanics as BankStatementCsvImporter) ------

  static const _delimiters = [',', ';', '\t'];

  static List<String> _rows(String csv) =>
      csv.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');

  static List<String> _split(String line, String delimiter) {
    final out = <String>[];
    final sb = StringBuffer();
    var inQuotes = false;
    for (var i = 0; i < line.length; i++) {
      final ch = line[i];
      if (ch == '"') {
        if (inQuotes && i + 1 < line.length && line[i + 1] == '"') {
          sb.write('"');
          i++;
        } else {
          inQuotes = !inQuotes;
        }
      } else if (ch == delimiter && !inQuotes) {
        out.add(sb.toString());
        sb.clear();
      } else {
        sb.write(ch);
      }
    }
    out.add(sb.toString());
    return out;
  }

  // ---- header mapping ------------------------------------------------------

  static _Columns _mapColumns(List<String> header) {
    final cols = _Columns();
    for (var i = 0; i < header.length; i++) {
      final h = header[i].trim().toLowerCase();
      if (h.isEmpty) continue;
      if (cols.order == null &&
          (h.contains('order') && !h.contains('date') || h == 'reference')) {
        cols.order = i;
      } else if (cols.date == null && h.contains('date')) {
        cols.date = i;
      } else if (cols.sku == null &&
          (h.contains('sku') || h == 'item' || h.contains('item code') ||
              h.contains('product code') || h.contains('variant'))) {
        cols.sku = i;
      } else if (cols.qty == null &&
          (h.contains('qty') || h.contains('quantity'))) {
        cols.qty = i;
      } else if (cols.rate == null &&
          (h.contains('price') || h.contains('rate') ||
              h.contains('unit cost'))) {
        cols.rate = i;
      } else if (cols.email == null && h.contains('email')) {
        cols.email = i;
      } else if (cols.customer == null &&
          (h.contains('customer') || h.contains('billing name') ||
              h == 'name' || h.contains('buyer'))) {
        cols.customer = i;
      } else if (cols.description == null &&
          (h.contains('description') || h.contains('product') ||
              h.contains('item name') || h.contains('title'))) {
        cols.description = i;
      }
    }
    return cols;
  }

  // ---- value parsing (identical rules to the bank importer) ---------------

  static String _pad(String s) => s.padLeft(2, '0');

  static String? _parseDate(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return null;
    var m = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})').firstMatch(s);
    if (m != null) return '${m[1]}-${_pad(m[2]!)}-${_pad(m[3]!)}';
    m = RegExp(r'^(\d{1,2})[/.\-](\d{1,2})[/.\-](\d{2,4})').firstMatch(s);
    if (m != null) {
      final day = m[1]!, month = m[2]!, yr = m[3]!;
      final year = yr.length == 2 ? '20$yr' : yr;
      return '$year-${_pad(month)}-${_pad(day)}';
    }
    return null;
  }

  static num? _parseAmount(String raw) {
    var s = raw.replaceAll(RegExp(r'[^\d.,\-]'), '');
    if (s.isEmpty || s == '-') return null;
    final lastDot = s.lastIndexOf('.');
    final lastComma = s.lastIndexOf(',');
    if (lastDot >= 0 && lastComma >= 0) {
      if (lastComma > lastDot) {
        s = s.replaceAll('.', '').replaceAll(',', '.'); // EU 1.234,56
      } else {
        s = s.replaceAll(',', ''); // US 1,234.56
      }
    } else if (lastComma >= 0) {
      final after = s.length - lastComma - 1;
      s = after == 2 ? s.replaceAll(',', '.') : s.replaceAll(',', '');
    }
    return num.tryParse(s);
  }
}
