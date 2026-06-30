/// Pure CSV → bank-statement-line parser (H1 — ported from the Swift Hub
/// `BankStatementCSVImporter`). Database-free: it turns the text of a bank's CSV
/// export into normalised line records that the caller saves as `Bank Statement
/// Line` documents (and the matcher later reconciles).
///
/// Copes with the messy reality of bank exports:
///  * delimiter is auto-detected (comma / semicolon / tab);
///  * the header row is found by keyword and columns mapped from its names, so
///    column order doesn't matter;
///  * amounts come as a single signed column *or* separate debit/credit columns,
///    with US (`1,234.56`) or EU (`1.234,56`) number formatting;
///  * dates in ISO, `dd/mm/yyyy`, `dd.mm.yyyy`, or `dd-mm-yyyy` (2- or 4-digit
///    year), defaulting to day-first.
library;

/// One normalised statement line. [amount] is signed: positive money in.
class ParsedStatementLine {
  const ParsedStatementLine({
    required this.postingDate,
    required this.deposit,
    required this.withdrawal,
    this.description,
    this.reference,
  });

  final String postingDate; // ISO yyyy-MM-dd
  final String? description;
  final String? reference;
  final num deposit;
  final num withdrawal;

  num get amount => deposit - withdrawal;

  /// As a `Bank Statement Line` payload (minus `bank_account` / `import_batch`,
  /// which the caller supplies).
  Map<String, dynamic> toPayload() => {
        'posting_date': postingDate,
        if (description != null) 'description': description,
        if (reference != null) 'reference_number': reference,
        'deposit': deposit,
        'withdrawal': withdrawal,
        'amount': amount,
        'status': 'Unreconciled',
      };
}

/// The result of parsing a CSV: the lines understood, and how many data rows
/// were skipped (no parseable date or amount).
class BankStatementImport {
  const BankStatementImport({required this.lines, required this.skipped});
  final List<ParsedStatementLine> lines;
  final int skipped;
}

/// Which CSV column index holds which field, resolved from the header row.
class _Columns {
  int? date, description, reference, amount, debit, credit;
  bool get usable => date != null && (amount != null || debit != null || credit != null);
}

abstract final class BankStatementCsvImporter {
  static BankStatementImport parse(String csv) {
    final rows = _rows(csv);
    if (rows.isEmpty) return const BankStatementImport(lines: [], skipped: 0);

    // Find the header and the delimiter together: the first row (skipping any
    // export preamble) that maps to usable columns under some candidate
    // delimiter — so detection isn't fooled by a separator-less preamble line.
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
    if (cols == null) return const BankStatementImport(lines: [], skipped: 0);

    final lines = <ParsedStatementLine>[];
    var skipped = 0;
    for (var i = dataStart; i < rows.length; i++) {
      if (rows[i].trim().isEmpty) continue;
      final cells = _split(rows[i], delimiter);
      final line = _parseRow(cells, cols);
      if (line == null) {
        skipped++;
      } else {
        lines.add(line);
      }
    }
    return BankStatementImport(lines: lines, skipped: skipped);
  }

  // ---- rows / delimiter --------------------------------------------------

  /// Delimiters tried, in order, when resolving the header. Comma first so a
  /// plain comma file isn't mis-read as something else.
  static const _delimiters = [',', ';', '\t'];

  static List<String> _rows(String csv) =>
      csv.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');

  /// Splits one CSV line on [delimiter], honouring double-quoted fields (with
  /// `""` as an escaped quote).
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

  // ---- header mapping ----------------------------------------------------

  static _Columns _mapColumns(List<String> header) {
    final cols = _Columns();
    for (var i = 0; i < header.length; i++) {
      final h = header[i].trim().toLowerCase();
      if (h.isEmpty) continue;
      if (cols.date == null && h.contains('date')) {
        cols.date = i;
      } else if (cols.debit == null &&
          (h.contains('debit') || h.contains('withdraw') ||
              h.contains('paid out') || h.contains('money out'))) {
        cols.debit = i;
      } else if (cols.credit == null &&
          (h.contains('credit') || h.contains('deposit') ||
              h.contains('paid in') || h.contains('money in'))) {
        cols.credit = i;
      } else if (cols.amount == null && h.contains('amount')) {
        cols.amount = i;
      } else if (cols.reference == null &&
          (h == 'ref' || h.contains('reference'))) {
        cols.reference = i;
      } else if (cols.description == null &&
          (h.contains('description') || h.contains('narrative') ||
              h.contains('details') || h.contains('memo') ||
              h.contains('payee') || h.contains('particulars'))) {
        cols.description = i;
      }
    }
    return cols;
  }

  // ---- row parsing -------------------------------------------------------

  static ParsedStatementLine? _parseRow(List<String> cells, _Columns cols) {
    String? at(int? i) =>
        (i != null && i >= 0 && i < cells.length) ? cells[i].trim() : null;

    final date = _parseDate(at(cols.date) ?? '');
    if (date == null) return null;

    num deposit = 0;
    num withdrawal = 0;
    if (cols.amount != null) {
      final amt = _parseAmount(at(cols.amount) ?? '');
      if (amt == null) return null;
      if (amt >= 0) {
        deposit = amt;
      } else {
        withdrawal = -amt;
      }
    } else {
      // A bank statement credits money in and debits money out of your account.
      deposit = _parseAmount(at(cols.credit) ?? '') ?? 0;
      withdrawal = _parseAmount(at(cols.debit) ?? '') ?? 0;
      if (deposit == 0 && withdrawal == 0) return null;
    }

    final desc = at(cols.description);
    final ref = at(cols.reference);
    return ParsedStatementLine(
      postingDate: date,
      description: (desc != null && desc.isNotEmpty) ? desc : null,
      reference: (ref != null && ref.isNotEmpty) ? ref : null,
      deposit: deposit,
      withdrawal: withdrawal,
    );
  }

  static String _pad(String s) => s.padLeft(2, '0');

  /// Parses ISO or day-first dates to `yyyy-MM-dd`; null when unrecognised.
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

  /// Parses an amount, coping with currency symbols, thousands separators, and
  /// US (`1,234.56`) vs EU (`1.234,56`) decimal commas. Null when not numeric.
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
      // Only a comma: 2 digits after ⇒ decimal; otherwise thousands separator.
      final after = s.length - lastComma - 1;
      s = after == 2 ? s.replaceAll(',', '.') : s.replaceAll(',', '');
    }
    return num.tryParse(s);
  }
}
