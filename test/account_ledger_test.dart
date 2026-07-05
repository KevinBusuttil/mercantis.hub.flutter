import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_hub_app/modules/accounting/hub_account_actions.dart';
import 'package:mercantis_hub_app/screens/account_ledger_screen.dart';

/// The per-account ledger: the balance maths ([buildAccountLedger]) and the
/// "Ledger" command-bar action gating ([hubAccountActionsFor]).
void main() {
  Document account(String id, String rootType, {bool group = false}) =>
      Document(id: id, docType: 'Account', payload: {
        'account_name': id,
        'root_type': rootType,
        'is_group': group ? '1' : '0',
      });

  Document gl(String account, {num debit = 0, num credit = 0, required String date, String voucher = 'JV-1'}) =>
      Document(id: 'GL-$account-$date-$debit-$credit', docType: 'GL Entry', payload: {
        'account': account,
        'debit': debit,
        'credit': credit,
        'posting_date': date,
        'voucher_type': 'Journal Entry',
        'voucher_no': voucher,
      });

  group('buildAccountLedger', () {
    test('a debit-nature account grows with debits, newest row first', () {
      final view = buildAccountLedger(account('Bank', 'Asset'), [
        gl('Bank', debit: 100, date: '2026-01-01'),
        gl('Bank', credit: 30, date: '2026-01-03'),
        gl('Other', debit: 999, date: '2026-01-02'), // different account, ignored
      ]);

      expect(view.balance, 70); // 100 - 30
      expect(view.isGroup, isFalse);
      // Display order is newest-first, but the running balance is computed in
      // posting order (so the latest row shows the closing balance).
      expect(view.rows.map((r) => r.date), ['2026-01-03', '2026-01-01']);
      expect(view.rows.first.balance, 70);
      expect(view.rows.last.balance, 100);
    });

    test('a credit-nature account grows with credits', () {
      final view = buildAccountLedger(account('Sales', 'Income'), [
        gl('Sales', credit: 200, date: '2026-02-01'),
        gl('Sales', debit: 50, date: '2026-02-02'),
      ]);
      expect(view.balance, 150); // credit 200 - debit 50
    });

    test('an account with no postings has a zero balance and no rows', () {
      final view = buildAccountLedger(account('Cash', 'Asset'), [
        gl('Bank', debit: 100, date: '2026-01-01'),
      ]);
      expect(view.balance, 0);
      expect(view.rows, isEmpty);
    });

    test('a group account is flagged (postings land on children, not here)', () {
      final view =
          buildAccountLedger(account('Assets', 'Asset', group: true), const []);
      expect(view.isGroup, isTrue);
    });
  });

  group('hubAccountActionsFor', () {
    const accountType =
        DocType(id: 'Account', name: 'Account', module: 'Accounting', fields: []);

    test('offers Ledger on a saved leaf account', () {
      final actions = hubAccountActionsFor(account('Bank', 'Asset'), accountType);
      expect(actions.map((a) => a.id), ['account-ledger']);
      expect(actions.single.label, 'Ledger');
    });

    test('offers nothing on a group account', () {
      final actions = hubAccountActionsFor(
          account('Assets', 'Asset', group: true), accountType);
      expect(actions, isEmpty);
    });

    test('offers nothing on an unsaved account or another DocType', () {
      expect(
          hubAccountActionsFor(
              Document(id: '', docType: 'Account', payload: const {}),
              accountType),
          isEmpty);
      const other = DocType(id: 'Item', name: 'Item', module: 'Stock', fields: []);
      expect(hubAccountActionsFor(account('Bank', 'Asset'), other), isEmpty);
    });
  });
}
