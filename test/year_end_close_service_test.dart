import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_hub_app/modules/accounting/year_end_close_service.dart';

/// HU1 — year-end close: the pure P&L balance-gathering.
void main() {
  Document gl(String account, {num debit = 0, num credit = 0, String? company}) =>
      Document(id: '', docType: 'GL Entry', company: company, payload: {
        'account': account,
        'debit': debit,
        'credit': credit,
      });

  test('folds income (credit−debit) & expense (debit−credit); drops others', () {
    final balances = YearEndCloseService.balancesFrom(
      glEntries: [
        gl('Sales', credit: 1000),
        gl('Sales', debit: 100), // net income 900
        gl('COGS', debit: 400), // expense 400
        gl('Debtors', debit: 500), // Asset — not a P&L account, dropped
      ],
      rootTypeByAccount: {
        'Sales': 'Income',
        'COGS': 'Expense',
        'Debtors': 'Asset',
      },
    );
    // Sorted by account id (COGS < Sales); Debtors excluded.
    expect(
        balances.map((b) => '${b.account}:${b.isIncome}:${b.balance}').toList(),
        ['COGS:false:400', 'Sales:true:900']);
  });

  test('drops zero net balances and scopes to the company', () {
    final balances = YearEndCloseService.balancesFrom(
      glEntries: [
        gl('Sales', credit: 500, company: 'A'),
        gl('Sales', debit: 500, company: 'A'), // nets to 0 → dropped
        gl('Sales', credit: 300, company: 'B'), // other company → excluded
      ],
      rootTypeByAccount: {'Sales': 'Income'},
      company: 'A',
    );
    expect(balances, isEmpty);
  });
}
