import 'package:mercantis_core/mercantis_core.dart';

import '../../ledger/ledger_values.dart';

/// One profit-and-loss account's balance at the period end. [balance] is the
/// account's natural positive balance (income accounts sit on the credit side,
/// expense accounts on the debit side); [isIncome] says which.
class YearEndBalance {
  const YearEndBalance(this.account, {required this.isIncome, required this.balance});
  final String account;
  final bool isIncome;
  final num balance;
}

/// Builds the year-end closing Journal Entry (H2 — ported from the Swift
/// `YearEndCloseBuilder`). It zeroes every P&L account — debiting income
/// (a credit balance) and crediting expenses (a debit balance) — and posts the
/// resulting profit or loss to Retained Earnings, so the income statement
/// resets for the new year and equity absorbs the result. Returns a Draft
/// `Journal Entry` of voucher type `Closing Entry` for review and submission.
abstract final class YearEndCloseBuilder {
  static Document build(
    List<YearEndBalance> balances, {
    required String postingDate,
    String retainedEarningsAccount = 'Retained Earnings',
    String? company,
  }) {
    final rows = <ChildRow>[];
    num totalDebit = 0;
    num totalCredit = 0;
    for (final b in balances) {
      final amount = round2(b.balance);
      if (amount == 0) continue;
      if (b.isIncome) {
        // Income carries a credit balance → debit it to close.
        rows.add(_row(rows.length, {'account': b.account, 'debit': amount, 'credit': 0}));
        totalDebit = round2(totalDebit + amount);
      } else {
        // Expense carries a debit balance → credit it to close.
        rows.add(_row(rows.length, {'account': b.account, 'debit': 0, 'credit': amount}));
        totalCredit = round2(totalCredit + amount);
      }
    }

    // The net (profit when income > expense) goes to Retained Earnings: a
    // profit credits equity, a loss debits it, and the entry balances.
    final diff = round2(totalDebit - totalCredit);
    if (diff != 0) {
      rows.add(_row(rows.length, {
        'account': retainedEarningsAccount,
        'debit': diff < 0 ? round2(-diff) : 0,
        'credit': diff > 0 ? diff : 0,
      }));
      if (diff > 0) {
        totalCredit = round2(totalCredit + diff);
      } else {
        totalDebit = round2(totalDebit - diff);
      }
    }

    final doc = Document(
      id: '',
      docType: 'Journal Entry',
      company: company,
      docStatus: 0,
      payload: {
        'workflow_state': 'Draft',
        'voucher_type': 'Closing Entry',
        'posting_date': postingDate,
        'total_debit': totalDebit,
        'total_credit': totalCredit,
        'difference': round2(totalDebit - totalCredit),
        'user_remark': 'Year-end close',
      },
    );
    doc.children['accounts'] = rows;
    return doc;
  }

  static ChildRow _row(int index, Map<String, dynamic> payload) => ChildRow(
        id: '',
        parentId: '',
        parentDocType: 'Journal Entry',
        tableName: 'accounts',
        rowIndex: index,
        payload: payload,
      );
}
