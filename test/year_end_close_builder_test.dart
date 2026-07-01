import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_hub_app/modules/accounting/year_end_close_builder.dart';

/// H2 — the year-end closing Journal Entry builder.
void main() {
  num rowDebit(dynamic r) => (r.payload['debit'] as num?) ?? 0;
  num rowCredit(dynamic r) => (r.payload['credit'] as num?) ?? 0;

  test('closes P&L accounts and posts a profit to Retained Earnings', () {
    // Income 1000 (credit balance), expenses 600 (debit balance) → profit 400.
    final je = YearEndCloseBuilder.build(
      const [
        YearEndBalance('Sales', isIncome: true, balance: 1000),
        YearEndBalance('COGS', isIncome: false, balance: 600),
      ],
      postingDate: '2026-12-31',
    );

    expect(je.docType, 'Journal Entry');
    expect(je.payload['voucher_type'], 'Closing Entry');
    expect(je.payload['workflow_state'], 'Draft');

    final rows = je.children['accounts']!;
    // Income debited to close, expense credited, profit to equity.
    expect(rowDebit(rows.firstWhere((r) => r.payload['account'] == 'Sales')), 1000);
    expect(rowCredit(rows.firstWhere((r) => r.payload['account'] == 'COGS')), 600);
    final re = rows.firstWhere((r) => r.payload['account'] == 'Retained Earnings');
    expect(rowCredit(re), 400); // profit increases equity
    expect(je.payload['total_debit'], je.payload['total_credit']);
    expect(je.payload['difference'], 0);
  });

  test('a loss is debited to Retained Earnings', () {
    // Income 500, expenses 800 → loss 300.
    final je = YearEndCloseBuilder.build(
      const [
        YearEndBalance('Sales', isIncome: true, balance: 500),
        YearEndBalance('COGS', isIncome: false, balance: 800),
      ],
      postingDate: '2026-12-31',
      company: 'ACME',
    );

    final re = je.children['accounts']!
        .firstWhere((r) => r.payload['account'] == 'Retained Earnings');
    expect(je.company, 'ACME');
    expect(rowDebit(re), 300); // loss reduces equity
    expect(rowCredit(re), 0);
    expect(je.payload['total_debit'], 800);
    expect(je.payload['total_credit'], 800);
  });

  test('zero-balance accounts are skipped', () {
    final je = YearEndCloseBuilder.build(
      const [
        YearEndBalance('Sales', isIncome: true, balance: 0),
        YearEndBalance('COGS', isIncome: false, balance: 250),
      ],
      postingDate: '2026-12-31',
    );
    final accounts =
        je.children['accounts']!.map((r) => r.payload['account']).toList();
    expect(accounts, isNot(contains('Sales'))); // zero balance dropped
    expect(accounts, contains('COGS'));
    expect(accounts, contains('Retained Earnings'));
  });
}
