import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_hub_app/dashboards/owner_kpis.dart';

/// Pure tests for the owner dashboard KPIs (cash, overdue, bills due, month
/// sales, VAT estimate) over a fake list function with a frozen clock.
void main() {
  final now = DateTime(2026, 7, 6); // a Monday mid-quarter

  OwnerKpis build(Map<String, List<Document>> store) {
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
    return OwnerKpis(list, now: () => now);
  }

  Document invoice(String docType, String id, num outstanding, String due,
          {int docStatus = 1, num? grandTotal, String? postingDate}) =>
      Document(id: id, docType: docType, docStatus: docStatus, payload: {
        'outstanding_amount': outstanding,
        'due_date': due,
        'grand_total': grandTotal ?? outstanding,
        'posting_date': postingDate ?? due,
      });

  test('cash position sums Cash/Bank account GL balances only', () async {
    final kpis = build({
      'Account': [
        Document(id: 'Bank', docType: 'Account', payload: {'account_type': 'Bank'}),
        Document(id: 'Cash', docType: 'Account', payload: {'account_type': 'Cash'}),
        Document(id: 'Debtors', docType: 'Account', payload: {'account_type': 'Receivable'}),
      ],
      'GL Entry': [
        Document(id: 'g1', docType: 'GL Entry', payload: {'account': 'Bank', 'debit': 900, 'credit': 100}),
        Document(id: 'g2', docType: 'GL Entry', payload: {'account': 'Cash', 'debit': 50, 'credit': 0}),
        Document(id: 'g3', docType: 'GL Entry', payload: {'account': 'Debtors', 'debit': 500, 'credit': 0}),
      ],
    });
    expect((await kpis.cashPosition()).amount, 850);
  });

  test('overdue counts only submitted, unpaid, past-due sales invoices',
      () async {
    final kpis = build({
      'Sales Invoice': [
        invoice('Sales Invoice', 'a', 100, '2026-07-01'), // overdue
        invoice('Sales Invoice', 'b', 50, '2026-07-06'), // due today — not overdue
        invoice('Sales Invoice', 'c', 75, '2026-08-01'), // future
        invoice('Sales Invoice', 'd', 0, '2026-06-01'), // paid
        invoice('Sales Invoice', 'e', 10, '2026-06-01', docStatus: 0), // draft
      ],
    });
    final kpi = await kpis.overdueReceivables();
    expect(kpi.amount, 100);
    expect(kpi.caption, '1 invoice');
  });

  test('bills due includes overdue and the next 7 days', () async {
    final kpis = build({
      'Purchase Invoice': [
        invoice('Purchase Invoice', 'a', 40, '2026-07-01'), // overdue
        invoice('Purchase Invoice', 'b', 60, '2026-07-10'), // within horizon
        invoice('Purchase Invoice', 'c', 99, '2026-07-20'), // beyond horizon
      ],
    });
    final kpi = await kpis.billsDue();
    expect(kpi.amount, 100);
    expect(kpi.caption, '2 invoices');
  });

  test('sales this month spans SI + POS, current month only, returns net',
      () async {
    final kpis = build({
      'Sales Invoice': [
        invoice('Sales Invoice', 'a', 0, '2026-07-01',
            grandTotal: 100, postingDate: '2026-07-01'),
        invoice('Sales Invoice', 'ret', 0, '2026-07-02',
            grandTotal: -20, postingDate: '2026-07-02'), // credit note
        invoice('Sales Invoice', 'old', 0, '2026-06-30',
            grandTotal: 999, postingDate: '2026-06-30'), // last month
      ],
      'POS Invoice': [
        invoice('POS Invoice', 'p', 0, '2026-07-03',
            grandTotal: 30, postingDate: '2026-07-03'),
      ],
    });
    expect((await kpis.salesThisMonth()).amount, 110);
  });

  test('VAT estimate: output minus input for the current quarter', () async {
    Document tt(String id, String partyType, num amount, String date) =>
        Document(id: id, docType: 'Tax Transaction', payload: {
          'party_type': partyType,
          'tax_amount': amount,
          'posting_date': date,
        });
    final kpis = build({
      'Tax Transaction': [
        tt('o1', 'Customer', 180, '2026-07-01'), // output, Q3
        tt('i1', 'Supplier', 30, '2026-07-02'), // input, Q3
        tt('old', 'Customer', 999, '2026-06-01'), // Q2 — excluded
      ],
    });
    final kpi = await kpis.vatEstimate();
    expect(kpi.amount, 150);
    expect(kpi.caption, 'quarter to date');
  });
}
