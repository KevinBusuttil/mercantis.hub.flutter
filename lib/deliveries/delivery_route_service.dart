import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

import '../ledger/ledger_values.dart';
import 'delivery_route_planner.dart';

/// Subscribes to saves and, for each saved Delivery Route, appends a
/// `Delivery Status Event` per stop whose status changed (append-only audit
/// log, deterministic ids) and mirrors `delivery_route` + `route_status` onto
/// the linked Delivery Note. Pure mirroring/audit — no ledger impact.
class DeliveryRouteService {
  DeliveryRouteService({
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
    _tokens.add(emitter.subscribe<DocumentSavedEvent>((e) {
      if (e.document.docType == 'Delivery Route') {
        reconcile(e.document);
      }
    }));
  }

  void dispose() {
    for (final t in _tokens) {
      t.cancel();
    }
    _tokens.clear();
  }

  /// Appends status events for changed stops and mirrors route + status onto
  /// each stop's Delivery Note. Public so it can be driven directly in tests.
  Future<void> reconcile(Document routeEvent) async {
    try {
      final route = await engine.fetch('Delivery Route', routeEvent.id) ?? routeEvent;
      final stops = route.children['stops'] ?? const [];
      if (stops.isEmpty || route.id.isEmpty) return;

      final existing = await engine.list(
        'Delivery Status Event',
        filters: {'delivery_route': route.id},
        userRoles: systemRoles,
      );

      for (var i = 0; i < stops.length; i++) {
        final sp = stops[i].payload;
        final deliveryId = asNonEmpty(sp['sales_delivery']);
        if (deliveryId == null) continue;
        final sequence = (asNum(sp['sequence']) == 0 ? i + 1 : asNum(sp['sequence'])).toInt();
        final status = asNonEmpty(sp['status']) ?? 'Pending';

        final seqEvents =
            existing.where((ev) => asNum(ev.payload['stop_sequence']).toInt() == sequence).toList()
              ..sort((a, b) => _eventOrder(a).compareTo(_eventOrder(b)));
        final lastStatus =
            seqEvents.isEmpty ? null : asNonEmpty(seqEvents.last.payload['status']);

        if (DeliveryRoutePlanner.shouldEmitEvent(lastStatus: lastStatus, current: status)) {
          final id = DeliveryRoutePlanner.eventId(
            routeId: route.id,
            sequence: sequence,
            existingCount: seqEvents.length,
          );
          if (await engine.fetch('Delivery Status Event', id) == null) {
            await engine.save(
              Document(
                id: id,
                docType: 'Delivery Status Event',
                company: route.company,
                payload: {
                  'delivery_route': route.id,
                  'sales_delivery': deliveryId,
                  'stop_sequence': sequence,
                  'status': status,
                  'event_time': DateTime.now().toIso8601String(),
                },
              ),
              systemRoles,
            );
          }
        }

        await _mirrorToDelivery(deliveryId, route.id, status);
      }
    } catch (e, s) {
      onError?.call(e, s);
    }
  }

  /// Stamps `delivery_route` + `route_status` on the Delivery Note, using
  /// applyOnSubmitUpdate for submitted notes (both fields are allowOnSubmit).
  Future<void> _mirrorToDelivery(String deliveryId, String routeId, String status) async {
    final note = await engine.fetch('Delivery Note', deliveryId);
    if (note == null) return;
    final changed = asNonEmpty(note.payload['delivery_route']) != routeId ||
        asNonEmpty(note.payload['route_status']) != status;
    if (!changed) return;

    note.payload['delivery_route'] = routeId;
    note.payload['route_status'] = status;
    if (note.docStatus == 1) {
      await engine.applyOnSubmitUpdate(note, systemRoles);
    } else {
      await engine.save(note, systemRoles);
    }
  }

  /// Orders events deterministically by their `-<n>` id suffix (falls back to
  /// event_time) so "latest status" is stable regardless of fetch order.
  int _eventOrder(Document ev) {
    final id = ev.id;
    final dash = id.lastIndexOf('-');
    final n = dash == -1 ? null : int.tryParse(id.substring(dash + 1));
    return n ?? 0;
  }
}

/// Constructs and starts the delivery-route service for the app lifetime.
final deliveryRouteServiceProvider =
    FutureProvider<DeliveryRouteService>((ref) async {
  final engine = await ref.watch(documentEngineProvider.future);
  final emitter = ref.watch(eventEmitterProvider);
  final service = DeliveryRouteService(engine: engine, emitter: emitter);
  service.start();
  ref.onDispose(service.dispose);
  return service;
});
