import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

import '../ledger/ledger_values.dart';
import '../manufacturing/manufacturing.dart';

const _systemRoles = {'System Manager'};

final _workOrdersProvider = FutureProvider<List<Document>>((ref) async {
  final engine = await ref.watch(documentEngineProvider.future);
  return engine.list('Work Order', userRoles: _systemRoles);
});

/// Shop-floor completion: pick a Work Order, confirm the produced quantity, and
/// post its Manufacturing Stock Entry — consuming the BOM-exploded raw
/// materials from the source warehouse and producing the finished good into the
/// target warehouse (via the existing Stock Entry derivation).
class WorkOrderCompleteScreen extends ConsumerStatefulWidget {
  const WorkOrderCompleteScreen({super.key});

  @override
  ConsumerState<WorkOrderCompleteScreen> createState() => _WorkOrderCompleteScreenState();
}

class _WorkOrderCompleteScreenState extends ConsumerState<WorkOrderCompleteScreen> {
  String? _woId;
  Document? _wo;
  final _qtyCtrl = TextEditingController();
  bool _busy = false;
  String? _result;
  String? _error;

  @override
  void dispose() {
    _qtyCtrl.dispose();
    super.dispose();
  }

  Future<void> _select(String? id) async {
    setState(() {
      _woId = id;
      _wo = null;
      _result = null;
      _error = null;
    });
    if (id == null) return;
    final engine = await ref.read(documentEngineProvider.future);
    final wo = await engine.fetch('Work Order', id);
    if (!mounted) return;
    setState(() {
      _wo = wo;
      _qtyCtrl.text = asNum(wo?.payload['qty_to_produce']).toString();
    });
  }

  Future<void> _post() async {
    final wo = _wo;
    if (wo == null) return;
    final produced = num.tryParse(_qtyCtrl.text.trim()) ?? 0;
    if (produced <= 0) {
      setState(() => _error = 'Enter a produced quantity.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
    });
    try {
      final engine = await ref.read(documentEngineProvider.future);
      final se = Manufacturing.completionStockEntry(wo, producedQty: produced);
      final saved = await engine.save(se, _systemRoles);
      final posted = await engine.submit(saved, _systemRoles);
      // Record produced qty back on the (submitted) work order.
      if (wo.docStatus == 1) {
        wo.payload['produced_qty'] = produced;
        await engine.applyOnSubmitUpdate(wo, _systemRoles);
      }
      if (!mounted) return;
      ref.invalidate(_workOrdersProvider);
      setState(() {
        _busy = false;
        _result = 'Posted ${posted.id}';
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Production posted: ${posted.id}')));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e is DocumentEngineError ? e.humanMessage : '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final woAsync = ref.watch(_workOrdersProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Complete Work Order')),
      body: woAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('Failed to load: $e'))),
        data: (workOrders) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            DropdownButtonFormField<String>(
              initialValue: _woId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Work Order', border: OutlineInputBorder()),
              items: [
                for (final w in workOrders)
                  DropdownMenuItem(
                    value: w.id,
                    child: Text('${w.id} · ${(w.payload['item'] as String?) ?? ''}'),
                  ),
              ],
              onChanged: _busy ? null : _select,
            ),
            const SizedBox(height: 16),
            if (_wo != null) ..._details(_wo!),
            if (_result != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(_result!, style: TextStyle(color: Theme.of(context).colorScheme.primary)),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
          ],
        ),
      ),
    );
  }

  List<Widget> _details(Document wo) {
    final required = wo.children['required_items'] ?? const [];
    return [
      Text('Producing: ${(wo.payload['item'] as String?) ?? ''}', style: Theme.of(context).textTheme.titleMedium),
      Text('From ${(wo.payload['source_warehouse'] as String?) ?? '—'} → '
          '${(wo.payload['target_warehouse'] as String?) ?? '—'}'),
      const SizedBox(height: 12),
      Text('Raw materials to consume', style: Theme.of(context).textTheme.titleSmall),
      for (final r in required)
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text((r.payload['item'] as String?) ?? ''),
          trailing: Text(asNum(r.payload['required_qty']).toString()),
        ),
      const SizedBox(height: 12),
      TextField(
        controller: _qtyCtrl,
        enabled: !_busy,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(labelText: 'Produced quantity', border: OutlineInputBorder()),
      ),
      const SizedBox(height: 16),
      FilledButton.icon(
        onPressed: _busy ? null : _post,
        icon: _busy
            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.precision_manufacturing),
        label: const Text('Post production'),
      ),
    ];
  }
}
