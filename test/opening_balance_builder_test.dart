import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_hub_app/modules/accounting/opening_balance_builder.dart';

/// H2 — the opening-balance Journal Entry builder.
void main() {
  num rowDebit(dynamic r) => (r.payload['debit'] as num?) ?? 0;
  num rowCredit(dynamic r) => (r.payload['credit'] as num?) ?? 0;

  test('a balanced set of balances needs no equity line', () {
    final je = OpeningBalanceBuilder.build(
      const [
        OpeningBalanceEntry('Bank', debit: 1000),
        OpeningBalanceEntry('Creditors', credit: 1000),
      ],
      postingDate: '2026-01-01',
    );

    expect(je.docType, 'Journal Entry');
    expect(je.docStatus, 0);
    expect(je.payload['voucher_type'], 'Opening Entry');
    expect(je.payload['workflow_state'], 'Draft');
    expect(je.children['accounts'], hasLength(2)); // no balancing line
    expect(je.payload['total_debit'], 1000);
    expect(je.payload['total_credit'], 1000);
    expect(je.payload['difference'], 0);
  });

  test('net debits are balanced by a credit to Opening Balance Equity', () {
    final je = OpeningBalanceBuilder.build(
      const [
        OpeningBalanceEntry('Bank', debit: 1000),
        OpeningBalanceEntry('Stock', debit: 500),
        OpeningBalanceEntry('Creditors', credit: 300),
      ],
      postingDate: '2026-01-01',
    );

    final rows = je.children['accounts']!;
    expect(rows, hasLength(4)); // 3 + equity
    final equity = rows.last;
    expect(equity.payload['account'], 'Opening Balance Equity');
    expect(rowCredit(equity), 1200); // 1500 debit − 300 credit
    expect(rowDebit(equity), 0);
    expect(je.payload['total_debit'], je.payload['total_credit']);
    expect(je.payload['difference'], 0);
  });

  test('totals come from the rounded posted rows, so the entry truly balances', () {
    // Each 0.33x rounds to 0.33; the equity contra must match the posted 0.66,
    // not the raw-sum 0.665 → 0.67.
    final je = OpeningBalanceBuilder.build(
      const [
        OpeningBalanceEntry('Bank', debit: 0.334),
        OpeningBalanceEntry('Cash', debit: 0.331),
      ],
      postingDate: '2026-01-01',
    );

    final equity = je.children['accounts']!.last;
    expect(rowCredit(equity), 0.66);
    expect(je.payload['total_debit'], 0.66);
    expect(je.payload['total_credit'], 0.66);
    expect(je.payload['difference'], 0);
  });

  test('net credits are balanced by a debit to equity, and company carries', () {
    final je = OpeningBalanceBuilder.build(
      const [OpeningBalanceEntry('Retained Earnings', credit: 800)],
      postingDate: '2026-01-01',
      equityAccount: 'Opening Equity',
      company: 'ACME',
    );

    final equity = je.children['accounts']!.last;
    expect(je.company, 'ACME');
    expect(equity.payload['account'], 'Opening Equity');
    expect(rowDebit(equity), 800);
    expect(rowCredit(equity), 0);
    expect(je.payload['total_debit'], 800);
    expect(je.payload['total_credit'], 800);
  });
}
