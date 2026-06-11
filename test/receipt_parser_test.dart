import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_hub_app/capture/receipt_parser.dart';

/// ADR-049: the heuristic receipt parser. Covers the EU/US number groupings,
/// labelled vs fallback totals, date formats, and the confidence signal.
void main() {
  test('parses a typical EU fuel receipt (comma decimals, € symbol)', () {
    final r = ReceiptParser.parse('''
BP Service Station
Triq il-Kbira, Mosta
VAT No: MT12345678
Date: 14/03/2026
Receipt No: 4471
Unleaded 95      45,30
Subtotal         38,39
VAT 18%           6,91
TOTAL           €45,30
''');
    expect(r.merchantName, 'BP Service Station');
    expect(r.documentDate, '2026-03-14');
    expect(r.invoiceNo, '4471');
    expect(r.netTotal, 38.39);
    expect(r.vatTotal, 6.91);
    expect(r.grandTotal, 45.30);
    expect(r.currencyCode, 'EUR');
    expect(r.confidence, greaterThan(0.8));
  });

  test('parses a US-style receipt (thousands comma, dot decimals, \$)', () {
    final r = ReceiptParser.parse('''
THE HARDWARE CO
Invoice #INV-2026-0088
2026-01-09
Items subtotal    1,200.00
Sales Tax           96.00
Amount Due       \$1,296.00
''');
    expect(r.merchantName, 'THE HARDWARE CO');
    expect(r.invoiceNo, 'INV-2026-0088');
    expect(r.documentDate, '2026-01-09');
    expect(r.netTotal, 1200.00);
    expect(r.vatTotal, 96.00);
    expect(r.grandTotal, 1296.00);
    expect(r.currencyCode, 'USD');
  });

  test('falls back to the largest amount when no total is labelled', () {
    final r = ReceiptParser.parse('''
Corner Cafe
Cappuccino   2.50
Croissant    1.80
Water        0.90
5.20
''');
    expect(r.grandTotal, 5.20);
    expect(r.merchantName, 'Corner Cafe');
    // Unlabelled total ⇒ lower confidence than a clean labelled read.
    expect(r.confidence, lessThan(0.6));
  });

  test('derives VAT from net and grand when not printed', () {
    final r = ReceiptParser.parse('''
Shop
Net total   100.00
Total       118.00
''');
    expect(r.netTotal, 100.00);
    expect(r.grandTotal, 118.00);
    expect(r.vatTotal, 18.00);
  });

  test('reads a named-month date', () {
    final r = ReceiptParser.parse('Store\n7 Feb 2026\nTotal 9.99');
    expect(r.documentDate, '2026-02-07');
  });

  test('empty/garbage text yields an empty low-confidence result', () {
    final r = ReceiptParser.parse('\n\n   \n');
    expect(r.isEmpty, isTrue);
    expect(r.confidence, 0);
  });
}
