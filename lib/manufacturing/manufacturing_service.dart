import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

import '../ledger/ledger_values.dart';
import 'manufacturing.dart';

/// Subscribes to submit + workflow-transition events to automate two flows:
///
/// 1. A submitted **Production Plan** becomes one draft Work Order per planned
///    item, seeding each Work Order's required items from its BOM explosion.
///    Deterministic ids (`WO-<planId>-<rowIndex>`) make it idempotent.
/// 2. A **Work Order** reaching `Completed` (via `wf-work-order`) auto-posts its
///    completion Stock Entry ([Manufacturing.completionStockEntry], submitted so
///    the stock moves derive). Deterministic id `SE-<woId>-completion` →
///    idempotent.
class ManufacturingDerivationService {
  ManufacturingDerivationService({
    required this.engine,
    required this.emitter,
    this.systemRoles = const {'System Manager'},
    this.onError,
  });

  final DocumentEngine engine;
  final EventEmitter emitter;
  final Set<String> systemRoles;
  final void Function(Object error, StackTrace stack)? onError;

  final List<SubscriptionToken> _tokens = [];

  void start() {
    _tokens.add(emitter.subscribe<DocumentSubmittedEvent>((e) {
      if (e.document.docType == 'Production Plan') {
        _generateWorkOrders(e.document);
      }
    }));
    _tokens.add(emitter.subscribe<WorkflowTransitionEvent>((e) {
      if (e.workflow == 'wf-work-order' && e.toState == 'Completed') {
        _postCompletion(e.documentId);
      }
    }));
  }

  /// Posts the completion Stock Entry for a Work Order that just reached
  /// `Completed`. Idempotent: a no-op once `SE-<woId>-completion` exists.
  Future<void> _postCompletion(String workOrderId) async {
    try {
      final seId = 'SE-$workOrderId-completion';
      if (await engine.fetch('Stock Entry', seId) != null) return;
      final wo = await engine.fetch('Work Order', workOrderId);
      if (wo == null) return;
      final se = Manufacturing.completionStockEntry(wo);
      final saved = await engine.save(se, systemRoles);
      await engine.submit(saved, systemRoles);
    } catch (e, s) {
      onError?.call(e, s);
    }
  }

  void dispose() {
    for (final t in _tokens) {
      t.cancel();
    }
    _tokens.clear();
  }

  Future<void> _generateWorkOrders(Document planEvent) async {
    try {
      final plan = await engine.fetch('Production Plan', planEvent.id) ?? planEvent;
      final rows = plan.children['items_to_manufacture'] ?? const [];
      final defaultSource = asNonEmpty(plan.payload['default_source_warehouse']);
      final defaultTarget = asNonEmpty(plan.payload['default_target_warehouse']);

      for (var i = 0; i < rows.length; i++) {
        final rp = rows[i].payload;
        final item = asNonEmpty(rp['item']);
        if (item == null) continue;
        final woId = 'WO-${plan.id}-$i';
        if (await engine.fetch('Work Order', woId) != null) continue; // idempotent

        final bomId = asNonEmpty(rp['bom']);
        final plannedQty = asNum(rp['planned_qty']);
        final wo = Document(
          id: woId,
          docType: 'Work Order',
          company: plan.company,
          payload: {
            'item': item,
            if (bomId != null) 'bom': bomId,
            'qty_to_produce': plannedQty,
            if (defaultSource != null) 'source_warehouse': defaultSource,
            if (defaultTarget != null) 'target_warehouse': defaultTarget,
            if (asNonEmpty(rp['against_sales_order']) != null)
              'against_sales_order': rp['against_sales_order'],
            'against_production_plan': plan.id,
          },
        );

        if (bomId != null) {
          final bom = await engine.fetch('BOM', bomId);
          if (bom != null) {
            final required = Manufacturing.requiredItemsFromBom(bom, plannedQty);
            wo.children['required_items'] = [
              for (var j = 0; j < required.length; j++)
                ChildRow(
                  id: '',
                  parentId: woId,
                  parentDocType: 'Work Order',
                  tableName: 'required_items',
                  rowIndex: j,
                  payload: required[j],
                ),
            ];
          }
        }

        await engine.save(wo, systemRoles);
      }
    } catch (e, s) {
      onError?.call(e, s);
    }
  }
}

/// Constructs and starts the manufacturing derivation service for the app life.
final manufacturingDerivationServiceProvider =
    FutureProvider<ManufacturingDerivationService>((ref) async {
  final engine = await ref.watch(documentEngineProvider.future);
  final emitter = ref.watch(eventEmitterProvider);
  final service = ManufacturingDerivationService(engine: engine, emitter: emitter);
  service.start();
  ref.onDispose(service.dispose);
  return service;
});
