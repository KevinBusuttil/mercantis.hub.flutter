import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_hub_app/reports/aggregating_reports.dart';

/// Pure tests for the app-side aggregating reports. A fake [DocumentListFn]
/// returns canned rows by DocType, so the grouping / bucketing / balance math
/// is exercised without a database.
void main() {
  HubAggregatingReports build(Map<String, List<Document>> store) {
    Future<List<Document>> list(
      String docType, {
      Map<String, dynamic>? filters,
      String? whereExpression,
      List<({String field, bool ascending})>? sortBy,
      int? limit,
      int? offset,
      Set<String>? userRoles,
    }) async =>
        store[docType] ?? const [];
    return HubAggregatingReports(list);
  }

  Document gl(String id, String account, num debit, num credit, {bool reversal = false}) =>
      Document(id: id, docType: 'GL Entry', payload: {
        'account': account,
        'debit': debit,
        'credit': credit,
        'is_reversal': reversal,
      });

  Document account(String id, String rootType) =>
      Document(id: id, docType: 'Account', payload: {'root_type': rootType});

  Document salesInvoice(String id, String customer, num outstanding, String dueDate, {int docStatus = 1}) =>
      Document(id: id, docType: 'Sales Invoice', docStatus: docStatus, payload: {
        'customer': customer,
        'outstanding_amount': outstanding,
        'due_date': dueDate,
      });

  group('Trial Balance', () {
    test('groups GL by account, classifies by root type, balances', () async {
      final reports = build({
        'Account': [account('Debtors', 'Asset'), account('Sales', 'Income')],
        'GL Entry': [
          gl('g1', 'Debtors', 1180, 0),
          gl('g2', 'Sales', 0, 1000),
          gl('g3', 'VAT Output', 0, 180), // no Account master → Unclassified
        ],
      });

      final r = await reports.trialBalance();
      expect(r.columnLabels, ['Type', 'Account', 'Debit', 'Credit', 'Balance']);

      // Asset → Income → Unclassified ordering, then a Total row.
      expect(r.rows[0], ['Asset', 'Debtors', '1,180.00', '0.00', '1,180.00']);
      expect(r.rows[1], ['Income', 'Sales', '0.00', '1,000.00', '-1,000.00']);
      expect(r.rows[2], ['Unclassified', 'VAT Output', '0.00', '180.00', '-180.00']);

      final total = r.rows.last;
      expect(total[1], 'Total');
      expect(total[2], total[3]); // Σdebit == Σcredit → books balance
      expect(total[2], '1,180.00');
    });

    test('includes reversal rows (already sign-swapped) so they net out', () async {
      final reports = build({
        'Account': [account('Debtors', 'Asset')],
        'GL Entry': [
          gl('g1', 'Debtors', 1000, 0),
          gl('g2', 'Debtors', 0, 1000, reversal: true),
        ],
      });
      final r = await reports.trialBalance();
      // The reversal is counted, not dropped: debit and credit both 1000, net 0.
      expect(r.rows[0], ['Asset', 'Debtors', '1,000.00', '1,000.00', '0.00']);
    });
  });

  group('AR aging', () {
    test('buckets open invoices by due-date age, ordered by total desc', () async {
      final reports = build({
        'Sales Invoice': [
          salesInvoice('SINV-1', 'C1', 100, '2026-05-20'), // 12 days → 0–30
          salesInvoice('SINV-2', 'C1', 50, '2026-04-01'), // 61 days → 61–90
          salesInvoice('SINV-3', 'C2', 200, '2026-01-01'), // >90
          salesInvoice('SINV-4', 'C3', 999, '2026-05-01', docStatus: 0), // draft → skip
          salesInvoice('SINV-5', 'C4', 0, '2026-05-01'), // nothing outstanding → skip
        ],
      });

      final r = await reports.arAging(asOf: DateTime(2026, 6, 1));
      expect(r.columnLabels, ['Customer', '0–30 days', '31–60 days', '61–90 days', '90+ days', 'Outstanding']);

      // C2 (200) sorts above C1 (150); drafts and settled invoices excluded.
      expect(r.rows[0], ['C2', '0.00', '0.00', '0.00', '200.00', '200.00']);
      expect(r.rows[1], ['C1', '100.00', '0.00', '50.00', '0.00', '150.00']);
      expect(r.rows.last, ['Total', '100.00', '0.00', '50.00', '200.00', '350.00']);
    });

    test('future-dated invoices land in the current (0–30) bucket', () async {
      final reports = build({
        'Sales Invoice': [salesInvoice('SINV-1', 'C1', 100, '2026-07-01')],
      });
      final r = await reports.arAging(asOf: DateTime(2026, 6, 1));
      expect(r.rows[0], ['C1', '100.00', '0.00', '0.00', '0.00', '100.00']);
    });
  });

  group('AP aging', () {
    test('mirrors AR aging over Purchase Invoices by supplier', () async {
      final reports = build({
        'Purchase Invoice': [
          Document(id: 'PINV-1', docType: 'Purchase Invoice', docStatus: 1, payload: {
            'supplier': 'S1',
            'outstanding_amount': 300,
            'due_date': '2026-05-25', // 7 days → 0–30
          }),
        ],
      });
      final r = await reports.apAging(asOf: DateTime(2026, 6, 1));
      expect(r.columnLabels.first, 'Supplier');
      expect(r.rows[0], ['S1', '300.00', '0.00', '0.00', '0.00', '300.00']);
      expect(r.rows.last, ['Total', '300.00', '0.00', '0.00', '0.00', '300.00']);
    });
  });
}
