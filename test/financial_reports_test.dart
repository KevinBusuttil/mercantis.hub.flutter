import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_hub_app/reports/aggregating_reports.dart';

/// Pure tests for the Phase-1A/1B statements: Profit & Loss, gross margin by
/// item, stock valuation, and the stock↔GL reconciliation trust check. Same
/// fake-list harness as aggregating_reports_test.
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
    Future<Document?> fetch(String docType, String id) async {
      for (final d in store[docType] ?? const <Document>[]) {
        if (d.id == id) return d;
      }
      return null;
    }

    return HubAggregatingReports(list, fetch: fetch);
  }

  Document gl(String id, String account, num debit, num credit) =>
      Document(id: id, docType: 'GL Entry', payload: {
        'account': account,
        'debit': debit,
        'credit': credit,
      });

  Document account(String id, String rootType, {String? accountType}) =>
      Document(id: id, docType: 'Account', payload: {
        'root_type': rootType,
        if (accountType != null) 'account_type': accountType,
      });

  group('Profit & Loss', () {
    test('income credit balances, expense debit balances, net profit', () async {
      final reports = build({
        'Account': [
          account('Sales', 'Income'),
          account('COGS', 'Expense'),
          account('Debtors', 'Asset'), // ignored
        ],
        'GL Entry': [
          gl('g1', 'Debtors', 36, 0),
          gl('g2', 'Sales', 0, 36),
          gl('g3', 'COGS', 15, 0),
          gl('g4', 'Stock', 0, 15),
        ],
      });

      final r = await reports.profitAndLoss();
      expect(r.rows, [
        ['Income', 'Sales', '36.00'],
        ['Income', 'Total income', '36.00'],
        ['Expenses', 'COGS', '15.00'],
        ['Expenses', 'Total expenses', '15.00'],
        ['', 'Net profit', '21.00'],
      ]);
    });
  });

  group('Gross margin by item', () {
    Document sle(String id, String voucherType, String item, num qtyChange,
            num rate) =>
        Document(id: id, docType: 'Stock Ledger Entry', payload: {
          'voucher_type': voucherType,
          'item': item,
          'qty_change': qtyChange,
          'valuation_rate': rate,
        });

    test('revenue from invoice lines, COGS from sale-voucher SLEs', () async {
      final invoice = Document(
          id: 'SINV-1', docType: 'Sales Invoice', docStatus: 1, payload: {});
      invoice.children['items'] = [
        ChildRow(
          id: 'l1', parentId: 'SINV-1', parentDocType: 'Sales Invoice',
          tableName: 'items', rowIndex: 0,
          payload: {'item': 'ITEM-A', 'qty': 3, 'rate': 12, 'amount': 36},
        ),
        ChildRow(
          id: 'l2', parentId: 'SINV-1', parentDocType: 'Sales Invoice',
          tableName: 'items', rowIndex: 1,
          payload: {'item': 'SVC-1', 'qty': 1, 'rate': 100, 'amount': 100},
        ),
      ];
      final reports = build({
        'Sales Invoice': [invoice],
        'Stock Ledger Entry': [
          sle('s1', 'Sales Invoice', 'ITEM-A', -3, 5), // COGS 15
          sle('s2', 'Purchase Invoice', 'ITEM-A', 10, 5), // not a sale — ignored
        ],
      });

      final r = await reports.grossMarginByItem();
      // Service line: 100 revenue, no COGS. Stock line: 36 − 15 = 21.
      expect(r.rows[0], ['SVC-1', '100.00', '0.00', '100.00', '100.0%']);
      expect(r.rows[1], ['ITEM-A', '36.00', '15.00', '21.00', '58.3%']);
      expect(r.rows.last, ['Total', '136.00', '15.00', '121.00', '89.0%']);
    });

    test('draft invoices and returns are handled', () async {
      final draft = Document(
          id: 'SINV-D', docType: 'Sales Invoice', docStatus: 0, payload: {});
      draft.children['items'] = [
        ChildRow(
          id: 'l1', parentId: 'SINV-D', parentDocType: 'Sales Invoice',
          tableName: 'items', rowIndex: 0,
          payload: {'item': 'ITEM-A', 'amount': 999},
        ),
      ];
      final reports = build({
        'Sales Invoice': [draft],
        'Stock Ledger Entry': [
          sle('s1', 'Sales Invoice', 'ITEM-A', -3, 5),
          sle('s2', 'Sales Invoice', 'ITEM-A', 3, 5), // return: nets to zero
        ],
      });

      final r = await reports.grossMarginByItem();
      expect(r.rows[0], ['ITEM-A', '0.00', '0.00', '0.00', '—']);
    });
  });

  group('Stock valuation', () {
    Document bin(String id, String item, num qty, num value) =>
        Document(id: id, docType: 'Bin', payload: {
          'item': item,
          'actual_qty': qty,
          'stock_value': value,
        });

    test('folds bins per item with a grand total', () async {
      final reports = build({
        'Bin': [
          bin('b1', 'ITEM-A', 7, 35),
          bin('b2', 'ITEM-A', 3, 15), // second warehouse
          bin('b3', 'ITEM-B', 2, 100),
        ],
      });

      final r = await reports.stockValuation();
      expect(r.rows[0], ['ITEM-B', '2', '50.00', '100.00']);
      expect(r.rows[1], ['ITEM-A', '10', '5.00', '50.00']);
      expect(r.rows.last, ['Total', '', '', '150.00']);
    });
  });

  group('Stock ↔ GL reconciliation', () {
    test('zero difference when the ledgers agree', () async {
      final reports = build({
        'Bin': [
          Document(id: 'b1', docType: 'Bin', payload: {
            'item': 'ITEM-A', 'actual_qty': 10, 'stock_value': 50,
          }),
        ],
        'Account': [
          account('Stock', 'Asset', accountType: 'Stock'),
          account('Bank', 'Asset', accountType: 'Bank'),
        ],
        'GL Entry': [
          gl('g1', 'Stock', 50, 0),
          gl('g2', 'Bank', 500, 0), // not inventory — ignored
        ],
      });

      final r = await reports.stockGlReconciliation();
      expect(r.rows[0][1], '50.00');
      expect(r.rows[1][1], '50.00');
      expect(r.rows[2], ['Difference', '0.00']);
    });

    test('drift is surfaced', () async {
      final reports = build({
        'Bin': [
          Document(id: 'b1', docType: 'Bin', payload: {
            'item': 'ITEM-A', 'actual_qty': 10, 'stock_value': 50,
          }),
        ],
        'Account': [account('Stock', 'Asset', accountType: 'Stock')],
        'GL Entry': [gl('g1', 'Stock', 30, 0)],
      });

      final r = await reports.stockGlReconciliation();
      expect(r.rows[2], ['Difference', '20.00']);
    });
  });
}
