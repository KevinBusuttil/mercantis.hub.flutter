import 'package:mercantis_core/mercantis_core.dart';

import '../../ledger/ledger_values.dart';

/// One account's opening balance, entered as a debit *or* a credit (assets and
/// expenses are debits; liabilities, equity, and income are credits).
class OpeningBalanceEntry {
  const OpeningBalanceEntry(this.account, {this.debit = 0, this.credit = 0});
  final String account;
  final num debit;
  final num credit;
}

/// Builds the opening-balance Journal Entry (H2 — ported from the Swift
/// `OpeningBalanceBuilder`). Each supplied account balance becomes a line; any
/// net imbalance is carried to an equity account (Opening Balance Equity) so
/// the entry is always balanced and submittable. Returns a Draft `Journal
/// Entry` of voucher type `Opening Entry` for the caller to review and submit.
abstract final class OpeningBalanceBuilder {
  static Document build(
    List<OpeningBalanceEntry> entries, {
    required String postingDate,
    String equityAccount = 'Opening Balance Equity',
    String? company,
  }) {
    final rows = <ChildRow>[];
    num totalDebit = 0;
    num totalCredit = 0;
    for (final e in entries) {
      // Round each leg to the cent it will actually post at, and total those
      // same rounded values — so the equity balance matches what LedgerDerivation
      // will post (accumulating raw amounts could leave a sub-cent gap).
      final debit = round2(e.debit);
      final credit = round2(e.credit);
      totalDebit = round2(totalDebit + debit);
      totalCredit = round2(totalCredit + credit);
      rows.add(_row(rows.length, {
        'account': e.account,
        'debit': debit,
        'credit': credit,
      }));
    }

    // Carry any imbalance to equity: more debits ⇒ credit equity, and vice
    // versa, so the opening entry always balances.
    final diff = round2(totalDebit - totalCredit);
    if (diff != 0) {
      rows.add(_row(rows.length, {
        'account': equityAccount,
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
        'voucher_type': 'Opening Entry',
        'posting_date': postingDate,
        'total_debit': totalDebit,
        'total_credit': totalCredit,
        'difference': round2(totalDebit - totalCredit),
        'user_remark': 'Opening balances',
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
