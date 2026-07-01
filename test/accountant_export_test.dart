import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_hub_app/reports/accountant_export.dart';

/// HU1 — the accountant export CSV pack (pure).
void main() {
  ReportResult result(String id, List<List<String?>> rows) => ReportResult(
        reportId: id,
        name: id,
        columns: const [
          ReportColumn(fieldKey: 'account', label: 'Account'),
          ReportColumn(fieldKey: 'balance', label: 'Balance'),
        ],
        rows: rows,
      );

  test('concatenates each statement under a titled banner', () {
    final pack = buildAccountantExport([
      (title: 'Trial Balance', result: result('tb', [
        ['Sales', '1000'],
      ])),
      (title: 'AR Aging', result: result('ar', [
        ['Acme', '250'],
      ])),
    ]);

    expect(pack, contains('# Trial Balance'));
    expect(pack, contains('# AR Aging'));
    expect(pack, contains('Account,Balance'));
    expect(pack, contains('Sales,1000'));
    expect(pack, contains('Acme,250'));
    // Trial Balance banner comes before the AR one.
    expect(pack.indexOf('# Trial Balance'),
        lessThan(pack.indexOf('# AR Aging')));
  });

  test('a single statement needs no leading separator', () {
    final pack = buildAccountantExport([
      (title: 'Trial Balance', result: result('tb', const [])),
    ]);
    expect(pack.startsWith('# Trial Balance'), isTrue);
  });
}
