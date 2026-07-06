import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

import '../ledger/ledger_values.dart';
import '../modules/stock/stock_count.dart';

const _systemRoles = {'System Manager'};

/// Warehouses plus, per stock item, the selected warehouse's bin snapshot.
final _countContextProvider = FutureProvider.autoDispose
    .family<({List<Document> warehouses, List<StockCountLine> lines}), String?>(
        (ref, warehouse) async {
  final engine = await ref.watch(documentEngineProvider.future);
  final warehouses = await engine.list('Warehouse', userRoles: _systemRoles);
  if (warehouse == null) {
    return (warehouses: warehouses, lines: const <StockCountLine>[]);
  }
  final items = await engine.list('Item', userRoles: _systemRoles);
  final lines = <StockCountLine>[];
  for (final item in items) {
    if (!isStockItem(item.payload)) continue;
    final bin = await engine.fetch('Bin', 'BIN-${item.id}-$warehouse');
    lines.add(StockCountLine(
      item: item.id,
      onHand: asNum(bin?.payload['actual_qty']),
      counted: asNum(bin?.payload['actual_qty']),
      valuationRate: asNum(bin?.payload['valuation_rate']),
    ));
  }
  lines.sort((a, b) => a.item.compareTo(b.item));
  return (warehouses: warehouses, lines: lines);
});

/// Stock count (Phase 1B A5): snapshot the selected warehouse, walk the
/// shelves entering counted quantities, and post the differences as an
/// adjustment Stock Entry (created as a draft and opened for review).
class StockCountScreen extends ConsumerStatefulWidget {
  const StockCountScreen({super.key});

  @override
  ConsumerState<StockCountScreen> createState() => _StockCountScreenState();
}

class _StockCountScreenState extends ConsumerState<StockCountScreen> {
  String? _warehouse;
  final _counted = <String, TextEditingController>{};
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final c in _counted.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _controllerFor(StockCountLine line) =>
      _counted.putIfAbsent(
          line.item, () => TextEditingController(text: '${line.counted}'));

  Future<void> _post(List<StockCountLine> snapshot) async {
    final lines = <StockCountLine>[
      for (final l in snapshot)
        StockCountLine(
          item: l.item,
          onHand: l.onHand,
          counted:
              num.tryParse(_counted[l.item]?.text.trim() ?? '') ?? l.onHand,
          valuationRate: l.valuationRate,
        ),
    ];
    if (lines.every((l) => l.delta == 0)) {
      setState(() => _error = 'Every count matches the system — nothing to post.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final engine = await ref.read(documentEngineProvider.future);
      final draft = buildStockCountEntry(
        warehouse: _warehouse!,
        postingDate: DateTime.now().toIso8601String().split('T').first,
        lines: lines,
      );
      final saved = await engine.save(draft, _systemRoles);
      if (!mounted) return;
      context.go('/form/Stock Entry/${saved.id}');
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
    final async = ref.watch(_countContextProvider(_warehouse));
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Stock count')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load: $e')),
        data: (ctx) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            DropdownButtonFormField<String>(
              initialValue: _warehouse,
              decoration: const InputDecoration(
                  labelText: 'Warehouse', border: OutlineInputBorder()),
              items: [
                for (final w in ctx.warehouses)
                  DropdownMenuItem(
                      value: w.id,
                      child: Text(
                          '${w.payload['warehouse_name'] ?? w.id}')),
              ],
              onChanged: _saving
                  ? null
                  : (v) => setState(() {
                        _warehouse = v;
                        for (final c in _counted.values) {
                          c.dispose();
                        }
                        _counted.clear();
                      }),
            ),
            const SizedBox(height: 12),
            if (_warehouse == null)
              Text('Pick a warehouse to start counting.',
                  style: theme.textTheme.bodySmall)
            else if (ctx.lines.isEmpty)
              Text('No stock items yet.', style: theme.textTheme.bodySmall)
            else ...[
              Text(
                'Enter what is actually on the shelf. Differences post as a '
                'stock adjustment (gains at current cost, losses at the '
                'item\'s valuation) after you review the draft entry.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              for (final l in ctx.lines)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(l.item),
                            Text('System: ${l.onHand}',
                                style: theme.textTheme.bodySmall),
                          ],
                        ),
                      ),
                      SizedBox(
                        width: 110,
                        child: TextField(
                          controller: _controllerFor(l),
                          enabled: !_saving,
                          textAlign: TextAlign.right,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration: const InputDecoration(
                              labelText: 'Counted', isDense: true),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _saving ? null : () => _post(ctx.lines),
                icon: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.fact_check_outlined),
                label: const Text('Create adjustment (draft)'),
              ),
            ],
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_error!,
                    style: TextStyle(color: theme.colorScheme.error)),
              ),
          ],
        ),
      ),
    );
  }
}
