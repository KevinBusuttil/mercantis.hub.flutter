import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_hub_app/modules/selling/customer_statement.dart';

/// The customer statement: opening balance from pre-period rows, running
/// balance through the period, closing balance = the customer's position.
void main() {
  CustomerStatementBuilder build(List<Document> rows) {
    Future<List<Document>> list(
      String docType, {
      Map<String, dynamic>? filters,
      String? whereExpression,
      List<({String field, bool ascending})>? sortBy,
      int? limit,
      int? offset,
      Set<String>? userRoles,
    }) async =>
        docType == 'Customer Transaction' ? rows : const [];
    return CustomerStatementBuilder(list);
  }

  Document ct(String id, String date, num amount, String kind,
          {String voucher = 'SINV-1'}) =>
      Document(id: id, docType: 'Customer Transaction', payload: {
        'customer': 'CUST-1',
        'posting_date': date,
        'amount': amount,
        'trans_type': kind,
        'voucher_type': kind == 'Payment' ? 'Payment Entry' : 'Sales Invoice',
        'voucher_no': voucher,
      });

  test('opening, running and closing balances', () async {
    final builder = build([
      ct('c1', '2026-05-01', 500, 'Invoice'), // before period → opening
      ct('c2', '2026-06-02', 1180, 'Invoice', voucher: 'SINV-2'),
      ct('c3', '2026-06-10', -1000, 'Payment', voucher: 'PAY-1'),
      ct('c4', '2026-06-20', -180, 'CreditNote', voucher: 'SINV-3'),
      ct('c5', '2026-09-01', 999, 'Invoice', voucher: 'SINV-4'), // after → excluded
    ]);

    final s = await builder.build(
        customer: 'CUST-1', from: '2026-06-01', to: '2026-06-30');
    expect(s.openingBalance, 500);
    expect(s.lines.length, 3);
    expect(s.lines[0].balance, 1680); // 500 + 1180
    expect(s.lines[1].balance, 680); // − 1000 payment
    expect(s.lines[2].balance, 500); // − 180 credit note
    expect(s.closingBalance, 500);

    final text = s.toText();
    expect(text, contains('Opening balance: €500.00'));
    expect(text, contains('Closing balance: €500.00'));
    expect(text, contains('PAY-1'));
  });

  test('an empty period keeps the opening as closing', () async {
    final builder = build([ct('c1', '2026-01-01', 250, 'Invoice')]);
    final s = await builder.build(
        customer: 'CUST-1', from: '2026-06-01', to: '2026-06-30');
    expect(s.openingBalance, 250);
    expect(s.lines, isEmpty);
    expect(s.closingBalance, 250);
  });

  test('same-day rows order deterministically by id', () async {
    final builder = build([
      ct('b', '2026-06-02', 100, 'Invoice', voucher: 'SINV-B'),
      ct('a', '2026-06-02', 50, 'Invoice', voucher: 'SINV-A'),
    ]);
    final s = await builder.build(
        customer: 'CUST-1', from: '2026-06-01', to: '2026-06-30');
    expect(s.lines[0].reference, contains('SINV-A'));
    expect(s.lines[1].balance, 150);
  });
}
