import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_hub_app/ledger/hub_tax_engine.dart';

/// Pure unit tests for the VAT calculator. No database — exercises the exact
/// grouping / rounding / zero-rate rules ported from the Swift `HubTaxEngine`.
void main() {
  TaxRateInfo info(String id, num rate, {String? account = 'VAT', String type = 'VAT'}) =>
      TaxRateInfo(codeId: id, description: '$id ($rate%)', rate: rate, account: account, taxType: type);

  group('HubTaxEngine.compute', () {
    test('single standard-rated code: net, tax, grand', () {
      final c = HubTaxEngine.compute(
        const [TaxLine(1000, 'V18')],
        {'V18': info('V18', 18)},
      );
      expect(c.netTotal, 1000);
      expect(c.totalTax, 180);
      expect(c.grandTotal, 1180);
      expect(c.taxRows.length, 1);
      expect(c.taxRows.single.taxableAmount, 1000);
      expect(c.taxRows.single.taxAmount, 180);
      expect(c.taxRows.single.account, 'VAT');
    });

    test('lines sharing a code are grouped into one row', () {
      final c = HubTaxEngine.compute(
        const [TaxLine(600, 'V18'), TaxLine(400, 'V18')],
        {'V18': info('V18', 18)},
      );
      expect(c.taxRows.length, 1);
      expect(c.taxRows.single.taxableAmount, 1000);
      expect(c.taxRows.single.taxAmount, 180);
    });

    test('two codes appear in first-seen order', () {
      final c = HubTaxEngine.compute(
        const [TaxLine(100, 'V7'), TaxLine(200, 'V18'), TaxLine(50, 'V7')],
        {'V7': info('V7', 7), 'V18': info('V18', 18)},
      );
      expect(c.taxRows.map((r) => r.taxCode).toList(), ['V7', 'V18']);
      expect(c.taxRows[0].taxableAmount, 150);
      expect(c.taxRows[0].taxAmount, 10.5);
      expect(c.taxRows[1].taxableAmount, 200);
      expect(c.taxRows[1].taxAmount, 36);
      expect(c.totalTax, 46.5);
      expect(c.netTotal, 350);
      expect(c.grandTotal, 396.5);
    });

    test('zero-rated code still produces a row with 0 tax (for the VAT return)', () {
      final c = HubTaxEngine.compute(
        const [TaxLine(500, 'V0')],
        {'V0': info('V0', 0)},
      );
      expect(c.taxRows.length, 1);
      expect(c.taxRows.single.taxableAmount, 500);
      expect(c.taxRows.single.taxAmount, 0);
      expect(c.totalTax, 0);
      expect(c.grandTotal, 500);
    });

    test('untaxed line (no/unknown code) is net-only, no tax row', () {
      final c = HubTaxEngine.compute(
        const [TaxLine(300, null), TaxLine(700, 'V18')],
        {'V18': info('V18', 18)},
      );
      expect(c.netTotal, 1000);
      expect(c.taxRows.length, 1);
      expect(c.taxRows.single.taxableAmount, 700);
      expect(c.totalTax, 126);
      expect(c.grandTotal, 1126);
    });

    test('per-row rounding to 2 decimals', () {
      final c = HubTaxEngine.compute(
        const [TaxLine(33.33, 'V18')],
        {'V18': info('V18', 18)},
      );
      // 33.33 * 0.18 = 5.9994 → 6.00
      expect(c.taxRows.single.taxAmount, 6);
      expect(c.grandTotal, 39.33);
    });

    test('empty lines → empty computation', () {
      final c = HubTaxEngine.compute(const [], const {});
      expect(c.netTotal, 0);
      expect(c.totalTax, 0);
      expect(c.grandTotal, 0);
      expect(c.taxRows, isEmpty);
    });
  });
}
