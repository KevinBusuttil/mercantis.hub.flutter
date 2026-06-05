import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_hub_app/manifest/hub_reports.dart';

/// A no-op lister; these tests exercise the pure projection only.
Future<List<Document>> _noDocs(
  String docType, {
  Map<String, dynamic>? filters,
  String? whereExpression,
  List<({String field, bool ascending})>? sortBy,
  int? limit,
  int? offset,
  Set<String>? userRoles,
}) async =>
    const [];

void main() {
  test('catalogue exposes 14 unique reports, each with columns', () {
    final all = HubReports.all();
    expect(all.length, 14);
    expect(all.map((r) => r.id).toSet().length, 14, reason: 'ids must be unique');
    for (final r in all) {
      expect(r.columns, isNotEmpty, reason: '${r.id} has no columns');
    }
  });

  test('General Ledger projects + formats rows through the engine', () {
    final engine = ReportEngine(_noDocs);
    final def = HubReports.all().firstWhere((r) => r.id == 'general_ledger');
    final result = engine.project(def, [
      Document(id: 'GL-1', docType: 'GL Entry', payload: {
        'posting_date': '2026-01-15',
        'account': 'Debtors',
        'debit': 1000,
        'credit': 0,
        'party': 'C1',
        'voucher_type': 'Sales Invoice',
        'voucher_no': 'SINV-1',
      }),
    ]);

    expect(result.columnLabels,
        ['Date', 'Account', 'Debit', 'Credit', 'Party', 'Voucher Type', 'Voucher No']);
    final row = result.rows.single;
    expect(row[0], '2026-01-15'); // date
    expect(row[1], 'Debtors');
    expect(row[2], '1,000.00'); // currency
    expect(row[3], '0.00');
  });
}
