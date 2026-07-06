import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

import '../ledger/ledger_values.dart';
import '../modules/accounting/opening_balance_builder.dart';

const _systemRoles = {'System Manager'};

/// The posting (leaf) accounts an opening balance can be entered against,
/// grouped by root type, plus the active company id.
final _openingContextProvider = FutureProvider.autoDispose<
    ({List<Document> accounts, String? company})>((ref) async {
  final engine = await ref.watch(documentEngineProvider.future);
  final accounts = await engine.list('Account', userRoles: _systemRoles);
  final companies = await engine.list('Company', userRoles: _systemRoles);
  final leaves = [
    for (final a in accounts)
      if (!isTrue(a.payload['is_group'])) a,
  ]..sort((l, r) => l.id.compareTo(r.id));
  return (
    accounts: leaves,
    company: companies.isEmpty ? null : companies.first.id,
  );
});

/// Opening balances (Phase 1A): enter each account's take-on balance —
/// assets/expenses as debits, liabilities/equity/income as credits — and
/// post a balanced Opening Entry journal. Any imbalance is carried to
/// Opening Balance Equity by the tested [OpeningBalanceBuilder]; the entry
/// is created as a Draft and opened for review before submission.
class OpeningBalancesScreen extends ConsumerStatefulWidget {
  const OpeningBalancesScreen({super.key});

  @override
  ConsumerState<OpeningBalancesScreen> createState() =>
      _OpeningBalancesScreenState();
}

class _OpeningBalancesScreenState
    extends ConsumerState<OpeningBalancesScreen> {
  final _controllers = <String, TextEditingController>{};
  DateTime _postingDate = DateTime.now();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _controllerFor(String account) =>
      _controllers.putIfAbsent(account, TextEditingController.new);

  String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Debit-natured roots enter debits; everything else enters credits.
  bool _isDebitNature(Document account) =>
      const {'Asset', 'Expense'}
          .contains('${account.payload['root_type'] ?? ''}');

  Future<void> _post(List<Document> accounts, String? company) async {
    final entries = <OpeningBalanceEntry>[];
    for (final a in accounts) {
      final raw = _controllers[a.id]?.text.trim() ?? '';
      if (raw.isEmpty) continue;
      final amount = num.tryParse(raw);
      if (amount == null || amount == 0) continue;
      entries.add(_isDebitNature(a)
          ? OpeningBalanceEntry(a.id, debit: amount)
          : OpeningBalanceEntry(a.id, credit: amount));
    }
    if (entries.isEmpty) {
      setState(() => _error = 'Enter at least one balance.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final engine = await ref.read(documentEngineProvider.future);
      final draft = OpeningBalanceBuilder.build(
        entries,
        postingDate: _iso(_postingDate),
        company: company,
      );
      final saved = await engine.save(draft, _systemRoles);
      if (!mounted) return;
      // Open the draft for review — the user submits it from the form.
      context.go('/form/Journal Entry/${saved.id}');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e is DocumentEngineError ? e.humanMessage : '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(_openingContextProvider);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Opening balances')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load accounts: $e')),
        data: (ctx) {
          final byRoot = <String, List<Document>>{};
          for (final a in ctx.accounts) {
            byRoot
                .putIfAbsent(
                    '${a.payload['root_type'] ?? 'Other'}', () => [])
                .add(a);
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Bring balances over from your previous system. Enter each '
                'account\'s balance as of the take-on date — assets and '
                'expenses as positive debits, liabilities, equity and income '
                'as positive credits. Any difference is carried to Opening '
                'Balance Equity so the entry always balances; you review the '
                'draft journal before submitting it.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              AtlasDateFieldRow(
                label: 'Take-on date',
                readOnly: _saving,
                value: _iso(_postingDate),
                onChanged: (v) =>
                    setState(() => _postingDate = DateTime.parse(v)),
              ),
              const SizedBox(height: 8),
              for (final root in const [
                'Asset',
                'Liability',
                'Equity',
                'Income',
                'Expense'
              ])
                if (byRoot.containsKey(root)) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 12, bottom: 4),
                    child:
                        Text(root, style: theme.textTheme.titleSmall),
                  ),
                  for (final a in byRoot[root]!)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${a.payload['account_name'] ?? a.id}'),
                                Text(
                                  _isDebitNature(a) ? 'Debit' : 'Credit',
                                  style: theme.textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          SizedBox(
                            width: 140,
                            child: TextField(
                              controller: _controllerFor(a.id),
                              enabled: !_saving,
                              textAlign: TextAlign.right,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              decoration: const InputDecoration(
                                  hintText: '0.00', isDense: true),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed:
                    _saving ? null : () => _post(ctx.accounts, ctx.company),
                icon: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.playlist_add_check),
                label: const Text('Create opening entry (draft)'),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(_error!,
                      style: TextStyle(color: theme.colorScheme.error)),
                ),
            ],
          );
        },
      ),
    );
  }
}
