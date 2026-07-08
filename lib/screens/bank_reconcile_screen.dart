import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

import '../ledger/ledger_values.dart';
import '../modules/banking/bank_import_service.dart';
import '../modules/banking/bank_matcher.dart';
import '../modules/banking/bank_matching_service.dart';
import '../modules/banking/payout_import.dart';
import '../setup_library/setup_rule_engine.dart';

const _systemRoles = {'System Manager'};

/// Everything the workbench shows for one bank account: its unreconciled
/// lines, the ranked match suggestions, and the book balance.
typedef _Workbench = ({
  List<Document> accounts,
  List<Document> unreconciled,
  List<BankMatch> suggestions,
  num bookBalance,
  int reconciledCount,
});

final _workbenchProvider =
    FutureProvider.autoDispose.family<_Workbench, String?>((ref, accountId) async {
  final engine = await ref.watch(documentEngineProvider.future);
  final accounts = await engine.list('Bank Account', userRoles: _systemRoles);
  if (accountId == null) {
    return (
      accounts: accounts,
      unreconciled: const <Document>[],
      suggestions: const <BankMatch>[],
      bookBalance: 0,
      reconciledCount: 0,
    );
  }
  final service = BankMatchingService(engine: engine);
  final lines = await engine.list('Bank Statement Line',
      filters: {'bank_account': accountId}, userRoles: _systemRoles);
  lines.sort((a, b) =>
      '${b.payload['posting_date']}'.compareTo('${a.payload['posting_date']}'));
  return (
    accounts: accounts,
    unreconciled: [
      for (final l in lines)
        if ('${l.payload['status']}' == 'Unreconciled') l,
    ],
    suggestions: await service.suggest(accountId),
    bookBalance: await service.ledgerBalance(accountId),
    reconciledCount:
        lines.where((l) => '${l.payload['status']}' == 'Reconciled').length,
  );
});

/// The bank reconciliation workbench (Phase 4): import statement CSV, accept
/// ranked match suggestions, turn unmatched money-out lines into expenses,
/// and see the book balance against what remains unexplained.
class BankReconcileScreen extends ConsumerStatefulWidget {
  const BankReconcileScreen({super.key});

  @override
  ConsumerState<BankReconcileScreen> createState() =>
      _BankReconcileScreenState();
}

class _BankReconcileScreenState extends ConsumerState<BankReconcileScreen> {
  String? _account;
  bool _busy = false;

  String _money(num v) => '€${v.toDouble().toStringAsFixed(2)}';

  Future<void> _importCsv() async {
    final csv = await showDialog<String>(
      context: context,
      builder: (c) {
        final ctrl = TextEditingController();
        return AlertDialog(
          title: const Text('Import bank statement (CSV)'),
          content: SizedBox(
            width: 520,
            child: TextField(
              controller: ctrl,
              maxLines: 12,
              decoration: const InputDecoration(
                hintText: 'Paste the CSV exported from your bank — the '
                    'importer detects the delimiter, column names, and '
                    'EU/US amount formats. Re-importing the same file '
                    'creates nothing new.',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(c, ctrl.text),
                child: const Text('Import')),
          ],
        );
      },
    );
    if (csv == null || csv.trim().isEmpty || _account == null) return;

    setState(() => _busy = true);
    try {
      final engine = await ref.read(documentEngineProvider.future);
      final result = await BankImportService(engine: engine)
          .importCsv(bankAccountId: _account!, csv: csv);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${result.imported} imported, '
              '${result.duplicates} already in the book, '
              '${result.skipped} unreadable row${result.skipped == 1 ? '' : 's'}.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Import failed: $e')));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        ref.invalidate(_workbenchProvider);
      }
    }
  }

  /// Books a payment-provider payout report (Stripe etc.) against this bank
  /// account: Dr Bank net + Dr Payment Fees / Cr Payment Clearing — so the
  /// payout statement line has a voucher to match and the fees become a
  /// visible expense.
  Future<void> _importPayout() async {
    final accountId = _account;
    if (accountId == null) return;
    final csv = await showDialog<String>(
      context: context,
      builder: (c) {
        final ctrl = TextEditingController();
        return AlertDialog(
          title: const Text('Import payout report (Stripe CSV)'),
          content: SizedBox(
            width: 520,
            child: TextField(
              controller: ctrl,
              maxLines: 12,
              decoration: const InputDecoration(
                hintText: 'Paste the provider\'s balance/payout CSV (one row '
                    'per charge with Amount, Fee and Net columns). One draft '
                    'journal is created: bank receives the net, fees become '
                    'an expense, and Payment Clearing is credited the gross.',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(c, ctrl.text),
                child: const Text('Create journal')),
          ],
        );
      },
    );
    if (csv == null || csv.trim().isEmpty) return;

    setState(() => _busy = true);
    try {
      final engine = await ref.read(documentEngineProvider.future);
      final account = await engine.fetch('Bank Account', accountId);
      final gl = asNonEmpty(account?.payload['gl_account']);
      if (gl == null) {
        throw StateError('Set the Ledger Account on this Bank Account first.');
      }
      final je = await PayoutImportService(engine: engine).importPayoutCsv(
        csv: csv,
        postingDate: DateTime.now().toIso8601String().split('T').first,
        bankGlAccount: gl,
        provider: 'Stripe',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Draft journal ${je.id} created — review and '
              'submit it to post.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Payout import failed: $e')));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        ref.invalidate(_workbenchProvider);
      }
    }
  }

  Future<void> _accept(BankMatch match) async {
    setState(() => _busy = true);
    try {
      final engine = await ref.read(documentEngineProvider.future);
      await BankMatchingService(engine: engine).apply(match);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        ref.invalidate(_workbenchProvider);
      }
    }
  }

  Future<void> _markReconciled(Document line) async {
    setState(() => _busy = true);
    try {
      final engine = await ref.read(documentEngineProvider.future);
      await BankMatchingService(engine: engine).markReconciled(line.id);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        ref.invalidate(_workbenchProvider);
      }
    }
  }

  /// Turns a money-out line into a prefilled draft Expense and opens it; once
  /// submitted it becomes a match candidate for this very line.
  Future<void> _createExpense(Document line) async {
    setState(() => _busy = true);
    try {
      final engine = await ref.read(documentEngineProvider.future);
      final account = await engine.fetch('Bank Account', _account!);

      // Setup Library rules (deterministic, never AI): a matching
      // categorisation rule prefills the expense account — and says why.
      // The draft still opens for review; rules suggest, people post.
      final rules = await engine.list('Setup Rule', userRoles: _systemRoles);
      final match = SetupRuleEngine.categoriseBankLine(
        rules: rules,
        description: asNonEmpty(line.payload['description']),
        reference: asNonEmpty(line.payload['reference_number']),
        amount: asNum(line.payload['deposit']) -
            asNum(line.payload['withdrawal']),
      );

      final draft = Document(id: '', docType: 'Expense', payload: {
        'posting_date': line.payload['posting_date'],
        'description': asNonEmpty(line.payload['description']) ??
            'Bank transaction ${line.id}',
        'net_amount': asNum(line.payload['withdrawal']),
        'is_paid': 1,
        if (asNonEmpty(account?.payload['gl_account']) != null)
          'paid_from': account!.payload['gl_account'],
        if (match?.account != null) 'expense_account': match!.account,
      });
      final saved = await engine.save(draft, _systemRoles);
      if (!mounted) return;
      if (match != null) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(match.explanation)));
      }
      context.go('/form/Expense/${saved.id}');
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(_workbenchProvider(_account));
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bank reconciliation'),
        actions: [
          IconButton(
            tooltip: 'Import statement CSV',
            icon: const Icon(Icons.upload_file_outlined),
            onPressed: (_account == null || _busy) ? null : _importCsv,
          ),
          IconButton(
            tooltip: 'Import payout report (Stripe CSV)',
            icon: const Icon(Icons.credit_card_outlined),
            onPressed: (_account == null || _busy) ? null : _importPayout,
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load: $e')),
        data: (w) {
          final byLine = {
            for (final l in w.unreconciled) l.id: l,
          };
          num unexplained = 0;
          for (final l in w.unreconciled) {
            unexplained +=
                asNum(l.payload['deposit']) - asNum(l.payload['withdrawal']);
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              DropdownButtonFormField<String>(
                initialValue: _account,
                decoration: const InputDecoration(
                    labelText: 'Bank account', border: OutlineInputBorder()),
                items: [
                  for (final a in w.accounts)
                    DropdownMenuItem(
                        value: a.id,
                        child: Text(
                            '${a.payload['account_name'] ?? a.id}')),
                ],
                onChanged:
                    _busy ? null : (v) => setState(() => _account = v),
              ),
              if (_account == null) ...[
                const SizedBox(height: 12),
                Text(
                  w.accounts.isEmpty
                      ? 'Create a Bank Account first (Finance → Bank '
                          'Accounts), then import a statement here.'
                      : 'Pick an account to reconcile.',
                  style: theme.textTheme.bodySmall,
                ),
              ] else ...[
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _Stat(label: 'Book balance', value: _money(w.bookBalance)),
                        _Stat(
                            label: 'Unreconciled',
                            value: '${w.unreconciled.length} lines'),
                        _Stat(label: 'Unexplained', value: _money(unexplained)),
                        _Stat(
                            label: 'Reconciled',
                            value: '${w.reconciledCount} lines'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text('Suggested matches', style: theme.textTheme.titleSmall),
                if (w.suggestions.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text('No suggestions — import a statement or post '
                        'the payments/expenses that explain these lines.',
                        style: theme.textTheme.bodySmall),
                  ),
                for (final m in w.suggestions)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.link_outlined),
                      title: Text(
                          '${byLine[m.lineId]?.payload['description'] ?? m.lineId}'),
                      subtitle: Text(
                          '${byLine[m.lineId]?.payload['posting_date'] ?? ''} → '
                          '${m.voucherType} ${m.voucherId} · '
                          'confidence ${(m.score * 100).round()}%'),
                      trailing: FilledButton(
                        onPressed: _busy ? null : () => _accept(m),
                        child: const Text('Accept'),
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                Text('Unreconciled lines', style: theme.textTheme.titleSmall),
                if (w.unreconciled.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text('Nothing unexplained — the account is fully '
                        'reconciled.', style: theme.textTheme.bodySmall),
                  ),
                for (final l in w.unreconciled)
                  Card(
                    child: ListTile(
                      leading: Icon(asNum(l.payload['withdrawal']) > 0
                          ? Icons.north_east
                          : Icons.south_west),
                      title: Text('${l.payload['description'] ?? l.id}'),
                      subtitle: Text('${l.payload['posting_date']} · '
                          '${asNum(l.payload['withdrawal']) > 0 ? '−${_money(asNum(l.payload['withdrawal']))}' : '+${_money(asNum(l.payload['deposit']))}'}'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (asNum(l.payload['withdrawal']) > 0)
                            TextButton(
                              onPressed:
                                  _busy ? null : () => _createExpense(l),
                              child: const Text('Create expense'),
                            ),
                          TextButton(
                            onPressed:
                                _busy ? null : () => _markReconciled(l),
                            child: const Text('Reconcile'),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text(value, style: theme.textTheme.titleMedium),
        Text(label, style: theme.textTheme.bodySmall),
      ],
    );
  }
}
