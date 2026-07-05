import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

import '../ledger/ledger_values.dart';

/// One posted line in an account's ledger, carrying the running balance after it.
class AccountLedgerRow {
  const AccountLedgerRow({
    required this.date,
    required this.voucherType,
    required this.voucherNo,
    required this.debit,
    required this.credit,
    required this.balance,
  });

  final String date;
  final String voucherType;
  final String voucherNo;
  final double debit;
  final double credit;

  /// Running balance after this line, signed by the account's nature (a debit
  /// account grows with debits; a credit account grows with credits).
  final double balance;
}

/// An account's ledger: its closing balance plus every posting against it,
/// newest first for display.
class AccountLedgerView {
  const AccountLedgerView({
    required this.accountId,
    required this.accountName,
    required this.rootType,
    required this.isGroup,
    required this.balance,
    required this.rows,
  });

  final String accountId;
  final String accountName;
  final String rootType;
  final bool isGroup;
  final double balance;
  final List<AccountLedgerRow> rows;
}

/// True for accounts whose balance grows with debits (Asset, Expense); the rest
/// (Liability, Income, Equity) grow with credits.
bool _isDebitNature(String rootType) =>
    rootType == 'Asset' || rootType == 'Expense';

double _toDouble(Object? v) =>
    v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;

/// Pure ledger computation: given an [account] and all [glEntries], returns the
/// account's balance and the postings against it (running balance in posting
/// order, then reversed to newest-first for display). Kept engine-free so the
/// balance maths is unit-testable.
AccountLedgerView buildAccountLedger(
    Document account, List<Document> glEntries) {
  final accountId = account.id;
  final rootType = (account.payload['root_type'] as String?) ?? 'Asset';
  final debitNature = _isDebitNature(rootType);

  final mine = [
    for (final e in glEntries)
      if (e.payload['account'] == accountId) e,
  ];
  // Oldest first so the running balance accumulates in posting order; ties
  // (same date) fall back to id for a stable sequence.
  mine.sort((a, b) {
    final da = (a.payload['posting_date'] as String?) ?? '';
    final db = (b.payload['posting_date'] as String?) ?? '';
    final c = da.compareTo(db);
    return c != 0 ? c : a.id.compareTo(b.id);
  });

  var running = 0.0;
  final rows = <AccountLedgerRow>[];
  for (final e in mine) {
    // Ledger balances are in the company's base (book) currency. A GL leg from
    // a multi-currency voucher carries the book value in base_debit/base_credit
    // (stamped at submit) while debit/credit stay in the transaction currency;
    // use the base amounts when present, falling back to the raw fields for
    // legacy/single-currency entries that were never base-stamped.
    final p = e.payload;
    final hasBase = p['base_debit'] != null || p['base_credit'] != null;
    final debit = _toDouble(hasBase ? p['base_debit'] : p['debit']);
    final credit = _toDouble(hasBase ? p['base_credit'] : p['credit']);
    running += debitNature ? (debit - credit) : (credit - debit);
    rows.add(AccountLedgerRow(
      date: (e.payload['posting_date'] as String?) ?? '',
      voucherType: (e.payload['voucher_type'] as String?) ?? '',
      voucherNo: (e.payload['voucher_no'] as String?) ?? '',
      debit: debit,
      credit: credit,
      balance: running,
    ));
  }

  return AccountLedgerView(
    accountId: accountId,
    accountName: (account.payload['account_name'] as String?) ?? accountId,
    rootType: rootType,
    isGroup: isTrue(account.payload['is_group']),
    balance: running,
    rows: rows.reversed.toList(), // newest first for display
  );
}

/// Builds the ledger for one account from the `GL Entry` postings that target
/// it. Null when the account doesn't exist.
final accountLedgerProvider =
    FutureProvider.family<AccountLedgerView?, String>((ref, accountId) async {
  final engine = await ref.watch(documentEngineProvider.future);
  final roles = ref.watch(currentUserProvider).roles;

  final acct = await engine.fetch('Account', accountId);
  if (acct == null) return null;
  // Filter in the query so a per-account ledger doesn't scale with the whole
  // GL table; buildAccountLedger re-checks the account defensively.
  final entries = await engine.list('GL Entry',
      filters: {'account': accountId}, userRoles: roles);
  return buildAccountLedger(acct, entries);
});

/// Per-account ledger: the account's balance and its transactions, from the
/// `GL Entry` postings. Reached via the "Ledger" action on an Account, with the
/// account id in the route's `?account=` query parameter.
class AccountLedgerScreen extends ConsumerWidget {
  const AccountLedgerScreen({super.key, this.accountId});

  final String? accountId;

  static String _money(double v) {
    final sign = v < 0 ? '-' : '';
    return '$sign€${v.abs().toStringAsFixed(2)}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = accountId;
    if (id == null || id.isEmpty) {
      return const ResponsiveScaffold(
        title: 'Account ledger',
        body: EmptyState(
          title: 'No account selected',
          message: 'Open the ledger from an account to see its balance.',
          icon: Icons.receipt_long_outlined,
        ),
      );
    }

    final theme = Theme.of(context);
    final bp = Breakpoint.of(context);
    final async = ref.watch(accountLedgerProvider(id));

    return ResponsiveScaffold(
      title: 'Account ledger',
      subtitle: 'Balance & transactions',
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (view) {
          if (view == null) {
            return EmptyState(
              title: 'Account not found',
              message: 'The account "$id" no longer exists.',
              icon: Icons.help_outline,
            );
          }
          return ListView(
            padding: EdgeInsets.all(
                bp.isPhone ? MercantisSpacing.lg : MercantisSpacing.xl),
            children: [
              SizedBox(
                width: bp.isPhone ? double.infinity : 280,
                child: KpiCard(
                  title: '${view.accountName} balance',
                  value: _money(view.balance),
                  subtitle: '${view.rootType} · ${view.rows.length} transaction'
                      '${view.rows.length == 1 ? '' : 's'}',
                  icon: Icons.account_balance_outlined,
                  accentColor: MercantisBrandColors.accentFinance,
                ),
              ),
              const SizedBox(height: MercantisSpacing.xl),
              Text('Transactions', style: theme.textTheme.titleMedium),
              const SizedBox(height: MercantisSpacing.sm),
              if (view.isGroup)
                const EmptyState(
                  title: 'Group account',
                  message: 'This is a summary (group) account — postings land on '
                      'its child accounts, not here.',
                  icon: Icons.account_tree_outlined,
                )
              else if (view.rows.isEmpty)
                const EmptyState(
                  title: 'No transactions yet',
                  message: 'Postings against this account will appear here.',
                  icon: Icons.receipt_long_outlined,
                )
              else
                ErpDataTable(
                  columns: const [
                    ErpDataColumn(label: 'Date', flex: 3),
                    ErpDataColumn(label: 'Voucher', flex: 4),
                    ErpDataColumn(label: 'Debit', flex: 3, numeric: true),
                    ErpDataColumn(label: 'Credit', flex: 3, numeric: true),
                    ErpDataColumn(label: 'Balance', flex: 3, numeric: true),
                  ],
                  rows: [
                    for (final r in view.rows)
                      ErpDataRow(
                        onTap: r.voucherNo.isEmpty
                            ? null
                            : () => context.go(
                                '/form/${r.voucherType}/${r.voucherNo}'),
                        cells: [
                          Text(r.date),
                          Text(
                            r.voucherNo.isEmpty ? r.voucherType : r.voucherNo,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(r.debit == 0 ? '' : _money(r.debit)),
                          Text(r.credit == 0 ? '' : _money(r.credit)),
                          Text(_money(r.balance)),
                        ],
                      ),
                  ],
                ),
            ],
          );
        },
      ),
    );
  }
}
