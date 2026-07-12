import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

import '../construction/valuation_service.dart';
import '../ledger/ledger_values.dart';

const _systemRoles = {'System Manager'};

final contractsProvider =
    FutureProvider.autoDispose<List<Document>>((ref) async {
  final engine = await ref.watch(documentEngineProvider.future);
  final contracts = <Document>[];
  for (final header in await engine.list('Construction Contract',
      userRoles: _systemRoles)) {
    if ('${header.payload['status']}' == 'Closed') continue;
    // Valuations drive everything shown; list() doesn't hydrate them.
    contracts
        .add(await engine.fetch('Construction Contract', header.id) ??
            header);
  }
  contracts.sort((a, b) => '${a.payload['contract_name']}'
      .compareTo('${b.payload['contract_name']}'));
  return contracts;
});

/// V6: the contracts board — certified position, billed-to-date and
/// retention held per live contract, with the next action a tap away:
/// certify a new valuation, mark practical completion, release the
/// retention.
class ContractsScreen extends ConsumerStatefulWidget {
  const ContractsScreen({super.key});

  @override
  ConsumerState<ContractsScreen> createState() =>
      _ContractsScreenState();
}

class _ContractsScreenState extends ConsumerState<ContractsScreen> {
  Future<ValuationService> get _service async =>
      ValuationService(await ref.read(documentEngineProvider.future));

  void _toast(Object message) {
    if (!mounted) return;
    final text = '$message';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(text.startsWith('Bad state: ')
            ? text.substring('Bad state: '.length)
            : text)));
  }

  Future<void> _activate(Document contract) async {
    try {
      final engine = await ref.read(documentEngineProvider.future);
      final fresh = await engine.fetch(
          'Construction Contract', contract.id);
      if (fresh == null) return;
      fresh.payload['status'] = 'Active';
      await engine.save(fresh, _systemRoles);
    } catch (e) {
      _toast(e);
    } finally {
      ref.invalidate(contractsProvider);
    }
  }

  Future<void> _bill(Document contract) async {
    final certified = ValuationService.certifiedPercent(contract);
    final pctCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Certify — ${contract.payload['contract_name']}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Certified so far: $certified%. The application bills '
                'the difference, less retention.'),
            const SizedBox(height: 12),
            TextField(
              controller: pctCtrl,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                  labelText: 'Cumulative % complete',
                  border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Bill application')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final invoice = await (await _service).bill(contract.id,
          cumulativePercent: num.tryParse(pctCtrl.text.trim()) ?? 0);
      _toast('Billed as ${invoice.id} '
          '(${asNum(invoice.payload['grand_total']).toStringAsFixed(2)})');
    } catch (e) {
      _toast(e);
    } finally {
      ref.invalidate(contractsProvider);
    }
  }

  Future<void> _complete(Document contract) async {
    try {
      await (await _service).markPracticallyComplete(contract.id);
    } catch (e) {
      _toast(e);
    } finally {
      ref.invalidate(contractsProvider);
    }
  }

  Future<void> _release(Document contract) async {
    try {
      final invoice =
          await (await _service).releaseRetention(contract.id);
      _toast('Retention released as ${invoice.id} — contract closed.');
    } catch (e) {
      _toast(e);
    } finally {
      ref.invalidate(contractsProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(contractsProvider);
    final theme = Theme.of(context);
    return ResponsiveScaffold(
      title: 'Contracts',
      leading: Navigator.of(context).canPop() ? const BackButton() : null,
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (contracts) {
          if (contracts.isEmpty) {
            return const EmptyState(
              title: 'No live contracts',
              message: 'Create a Construction Contract, activate it, and '
                  'certify valuations here — each one bills the delta '
                  'less retention.',
              icon: Icons.engineering_outlined,
            );
          }
          return ListView(
            padding: const EdgeInsets.all(MercantisSpacing.lg),
            children: [
              for (final c in contracts) _contractRow(c, theme),
            ],
          );
        },
      ),
    );
  }

  Widget _contractRow(Document contract, ThemeData theme) {
    final status = '${contract.payload['status']}';
    final certified = ValuationService.certifiedPercent(contract);
    final held = ValuationService.retentionHeld(contract);
    num billed = 0;
    for (final row
        in contract.children['valuations'] ?? const <ChildRow>[]) {
      billed += asNum(row.payload['net_this_time']);
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: MercantisSpacing.md),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    '${contract.payload['contract_name']} · '
                    '${contract.id}',
                    style: theme.textTheme.titleSmall),
                Text(
                    '$status · $certified% certified · '
                    'billed ${billed.toStringAsFixed(2)} · '
                    'retention held ${held.toStringAsFixed(2)}',
                    style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          if (status == 'Draft')
            FilledButton.tonal(
                onPressed: () => _activate(contract),
                child: const Text('Activate'))
          else if (status == 'Active') ...[
            FilledButton(
                onPressed: () => _bill(contract),
                child: const Text('Certify & bill')),
            const SizedBox(width: MercantisSpacing.xs),
            OutlinedButton(
                onPressed: () => _complete(contract),
                child: const Text('Practically complete')),
          ] else if (status == 'Practically Complete')
            FilledButton(
                onPressed: () => _release(contract),
                child: const Text('Release retention')),
        ],
      ),
    );
  }
}
