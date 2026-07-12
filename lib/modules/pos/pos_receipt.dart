import 'package:mercantis_core/mercantis_core.dart';

import '../../ledger/ledger_values.dart';

/// Pure 80mm-receipt text builder (Phase 6 POS polish). Renders a posted POS
/// Invoice (hydrated with its `items` / `taxes` / `tenders` children) as
/// fixed-width text — 42 columns, the classic 80mm thermal width — that can
/// be printed raw on a receipt printer or shown/shared as-is. Database-free.
abstract final class PosReceiptBuilder {
  static String build({
    required Document invoice,
    required String businessName,
    String? addressLine,
    String? vatNumber,
    String? exoNumber,
    String? footer,
    int width = 42,
  }) {
    final b = StringBuffer();
    void center(String s) => b.writeln(_center(s, width));
    void rule() => b.writeln(''.padRight(width, '-'));
    void kv(String label, String value) =>
        b.writeln(_spread(label, value, width));

    center(businessName);
    if (addressLine != null && addressLine.trim().isNotEmpty) {
      center(addressLine.trim());
    }
    if (vatNumber != null && vatNumber.trim().isNotEmpty) {
      center('VAT No: ${vatNumber.trim()}');
    }
    // Malta 13th Schedule: the Commissioner's approval number must appear
    // on every fiscal receipt issued by an approved POS.
    if (exoNumber != null && exoNumber.trim().isNotEmpty) {
      center('EXO No: ${exoNumber.trim()}');
    }
    rule();
    kv('Receipt', invoice.id);
    kv('Date', asNonEmpty(invoice.payload['posting_date']) ?? '');
    final customer = asNonEmpty(invoice.payload['customer']);
    if (customer != null) kv('Customer', customer);
    rule();

    for (final line in invoice.children['items'] ?? const <ChildRow>[]) {
      final name = asNonEmpty(line.payload['description']) ??
          '${line.payload['item']}';
      final qty = asNum(line.payload['qty']);
      final rate = asNum(line.payload['rate']);
      final amount = asNum(line.payload['amount']);
      b.writeln(_clip(name, width));
      kv('  ${_qty(qty)} x ${rate.toStringAsFixed(2)}',
          amount.toStringAsFixed(2));
    }
    rule();

    final total = asNum(invoice.payload['total']);
    final taxTotal = asNum(invoice.payload['tax_total']);
    final grand = asNum(invoice.payload['grand_total']);
    kv('Net', total.toStringAsFixed(2));
    for (final tax in invoice.children['taxes'] ?? const <ChildRow>[]) {
      final desc = asNonEmpty(tax.payload['description']) ??
          asNonEmpty(tax.payload['tax_code']) ??
          'Tax';
      kv(desc, asNum(tax.payload['tax_amount']).toStringAsFixed(2));
    }
    if ((invoice.children['taxes'] ?? const []).isEmpty && taxTotal != 0) {
      kv('VAT', taxTotal.toStringAsFixed(2));
    }
    kv('TOTAL', grand.toStringAsFixed(2));
    rule();

    for (final tender in invoice.children['tenders'] ?? const <ChildRow>[]) {
      kv('${tender.payload['tender_type'] ?? 'Paid'}',
          asNum(tender.payload['amount']).toStringAsFixed(2));
    }
    final change = asNum(invoice.payload['change_amount']);
    if (change > 0) kv('Change', change.toStringAsFixed(2));
    rule();
    center(footer ?? 'Thank you!');
    return b.toString();
  }

  /// Quantities print without a trailing `.0` when whole.
  static String _qty(num qty) =>
      qty == qty.roundToDouble() ? '${qty.round()}' : '$qty';

  static String _center(String s, int width) {
    final t = _clip(s, width);
    final pad = (width - t.length) ~/ 2;
    return '${' ' * (pad > 0 ? pad : 0)}$t';
  }

  /// Label left, value right, dot-free spread; the label is clipped before
  /// the value ever is (the number matters more than the words).
  static String _spread(String label, String value, int width) {
    final room = width - value.length - 1;
    final l = _clip(label, room > 0 ? room : 0);
    return '$l${' ' * (width - l.length - value.length)}$value';
  }

  static String _clip(String s, int max) =>
      s.length <= max ? s : s.substring(0, max);
}
