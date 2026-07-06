import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_hub_app/ledger/ledger_values.dart';
import 'package:mercantis_hub_app/modules/stock/inventory_takeon.dart';

/// The one-time inventory take-on: measures the bins-vs-GL gap and drafts
/// the balancing Opening Entry; agreement yields nothing to post.
void main() {
  InventoryTakeOn build(Map<String, List<Document>> store) {
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
    return InventoryTakeOn(list);
  }

  Document bin(String id, num value) => Document(
      id: id, docType: 'Bin', payload: {'item': id, 'stock_value': value});

  Document account(String id, {String type = 'Stock'}) => Document(
      id: id, docType: 'Account', payload: {'account_type': type});

  Document gl(String id, String acct, num debit, num credit) =>
      Document(id: id, docType: 'GL Entry', payload: {
        'account': acct,
        'debit': debit,
        'credit': credit,
      });

  test('pre-perpetual history: bins carry value, GL is empty → Dr Stock',
      () async {
    final takeOn = build({
      'Bin': [bin('A', 50), bin('B', 25)],
      'Account': [account('Stock'), account('Bank', type: 'Bank')],
      'GL Entry': [gl('g1', 'Bank', 500, 0)], // no inventory postings
    });
    expect(await takeOn.gap(), 75);

    final draft = await takeOn.build(postingDate: '2026-07-06');
    expect(draft, isNotNull);
    expect(draft!.payload['voucher_type'], 'Opening Entry');
    final rows = draft.children['accounts']!;
    expect(rows[0].payload['account'], 'Stock');
    expect(asNum(rows[0].payload['debit']), 75);
    expect(rows[1].payload['account'], 'Opening Balance Equity');
    expect(asNum(rows[1].payload['credit']), 75);
    // Balanced by construction — the journal balance guard will accept it.
    expect(asNum(draft.payload['total_debit']),
        asNum(draft.payload['total_credit']));
  });

  test('a negative gap flips the legs', () async {
    final takeOn = build({
      'Bin': [bin('A', 10)],
      'Account': [account('Stock')],
      'GL Entry': [gl('g1', 'Stock', 40, 0)], // GL says 40, bins say 10
    });
    final draft = await takeOn.build(postingDate: '2026-07-06');
    final rows = draft!.children['accounts']!;
    expect(asNum(rows[0].payload['credit']), 30); // Cr Stock
    expect(asNum(rows[1].payload['debit']), 30); // Dr equity
  });

  test('agreement (within a cent) posts nothing', () async {
    final takeOn = build({
      'Bin': [bin('A', 50)],
      'Account': [account('Stock')],
      'GL Entry': [gl('g1', 'Stock', 50.004, 0)],
    });
    expect(await takeOn.build(postingDate: '2026-07-06'), isNull);
  });
}
