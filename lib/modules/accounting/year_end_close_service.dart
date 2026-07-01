import 'package:mercantis_core/mercantis_core.dart';

import '../../ledger/ledger_values.dart';
import 'year_end_close_builder.dart';

/// Gathers a period's P&L balances from the ledger and hands them to
/// [YearEndCloseBuilder] to draft the year-end Closing Entry (HU1). The
/// balance-gathering is pure ([balancesFrom]) so it's unit-testable without a
/// database; [prepare] wraps it around the engine.
class YearEndCloseService {
  YearEndCloseService({required this.engine, this.roles = const {'System Manager'}});

  final DocumentEngine engine;
  final Set<String> roles;

  /// Folds [glEntries] into one natural balance per Income/Expense account
  /// (income = credit − debit; expense = debit − credit), dropping other root
  /// types and zero balances. Optionally scoped to [company]. Deterministic
  /// (accounts sorted by id).
  static List<YearEndBalance> balancesFrom({
    required Iterable<Document> glEntries,
    required Map<String, String?> rootTypeByAccount,
    String? company,
  }) {
    final debit = <String, num>{};
    final credit = <String, num>{};
    for (final e in glEntries) {
      if (company != null && e.company != company) continue;
      final account = asNonEmpty(e.payload['account']);
      if (account == null) continue;
      debit[account] = (debit[account] ?? 0) + asNum(e.payload['debit']);
      credit[account] = (credit[account] ?? 0) + asNum(e.payload['credit']);
    }
    final out = <YearEndBalance>[];
    for (final account in ({...debit.keys, ...credit.keys}.toList()..sort())) {
      final rootType = rootTypeByAccount[account];
      final d = debit[account] ?? 0;
      final c = credit[account] ?? 0;
      if (rootType == 'Income') {
        final balance = round2(c - d);
        if (balance != 0) {
          out.add(YearEndBalance(account, isIncome: true, balance: balance));
        }
      } else if (rootType == 'Expense') {
        final balance = round2(d - c);
        if (balance != 0) {
          out.add(YearEndBalance(account, isIncome: false, balance: balance));
        }
      }
    }
    return out;
  }

  /// Builds and saves the Draft `Journal Entry` (voucher type `Closing Entry`)
  /// that closes the P&L into Retained Earnings for review + submission.
  Future<Document> prepare({required String postingDate, String? company}) async {
    final accounts = await engine.list('Account', userRoles: roles);
    final rootTypeByAccount = {
      for (final a in accounts) a.id: asNonEmpty(a.payload['root_type']),
    };
    final glEntries = await engine.list('GL Entry', userRoles: roles);
    final balances = balancesFrom(
      glEntries: glEntries,
      rootTypeByAccount: rootTypeByAccount,
      company: company,
    );
    final draft = YearEndCloseBuilder.build(balances,
        postingDate: postingDate, company: company);
    return engine.save(draft, roles);
  }
}
