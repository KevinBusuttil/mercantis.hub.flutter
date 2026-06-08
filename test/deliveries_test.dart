import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_hub_app/deliveries/delivery_route_planner.dart';
import 'package:mercantis_hub_app/deliveries/delivery_route_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  group('DeliveryRoutePlanner', () {
    test('emits an event only when the status changes', () {
      expect(DeliveryRoutePlanner.shouldEmitEvent(lastStatus: null, current: 'Pending'), isTrue);
      expect(DeliveryRoutePlanner.shouldEmitEvent(lastStatus: 'Pending', current: 'Loaded'), isTrue);
      expect(DeliveryRoutePlanner.shouldEmitEvent(lastStatus: 'Loaded', current: 'Loaded'), isFalse);
    });

    test('event id is deterministic', () {
      expect(DeliveryRoutePlanner.eventId(routeId: 'ROUTE-1', sequence: 2, existingCount: 0), 'DSE-ROUTE-1-2-0');
    });
  });

  group('DeliveryRouteService', () {
    setUpAll(sqfliteFfiInit);
    late MercantisDatabase database;
    late DocumentEngine engine;
    late DeliveryRouteService service;
    const roles = {'System Manager'};

    setUp(() async {
      database = await MercantisDatabase.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
      final registry = MetadataRegistry(database.db);
      engine = DocumentEngine(
        database: database.db,
        registry: registry,
        metaComposer: MetaComposer(registry, database.db),
        permissionEngine: const PermissionEngine(),
        workflowEngine: WorkflowEngine(database.db),
        expressionEvaluator: ExpressionEvaluator(),
        namingService: NamingService(),
        syncEngine: SyncEngine(database: database.db, registry: registry),
        emitter: EventEmitter(),
        deviceId: 'test-device',
        userId: 'test-user',
        interceptors: const [],
      );
      service = DeliveryRouteService(engine: engine, emitter: EventEmitter());

      await registry.register(const DocType(id: 'Delivery Note', name: 'Delivery Note', fields: [
        FieldDefinition(key: 'customer', label: 'Customer', type: FieldType.data),
        FieldDefinition(key: 'delivery_route', label: 'Delivery Route', type: FieldType.data),
        FieldDefinition(key: 'route_status', label: 'Route Status', type: FieldType.data),
      ]));
      await registry.register(const DocType(id: 'Delivery Route Stop', name: 'Delivery Route Stop', isChild: true, fields: [
        FieldDefinition(key: 'sequence', label: 'Sequence', type: FieldType.integer),
        FieldDefinition(key: 'sales_delivery', label: 'Delivery Note', type: FieldType.data),
        FieldDefinition(key: 'status', label: 'Status', type: FieldType.data),
      ]));
      await registry.register(const DocType(id: 'Delivery Route', name: 'Delivery Route', fields: [
        FieldDefinition(key: 'route_date', label: 'Route Date', type: FieldType.date),
        FieldDefinition(key: 'status', label: 'Status', type: FieldType.data),
        FieldDefinition(key: 'stops', label: 'Stops', type: FieldType.table, tableDocType: 'Delivery Route Stop'),
      ]));
      await registry.register(const DocType(id: 'Delivery Status Event', name: 'Delivery Status Event', fields: [
        FieldDefinition(key: 'delivery_route', label: 'Delivery Route', type: FieldType.data),
        FieldDefinition(key: 'sales_delivery', label: 'Delivery Note', type: FieldType.data),
        FieldDefinition(key: 'stop_sequence', label: 'Sequence', type: FieldType.integer),
        FieldDefinition(key: 'status', label: 'Status', type: FieldType.data),
        FieldDefinition(key: 'event_time', label: 'Time', type: FieldType.data),
      ]));
    });

    tearDown(() => database.close());

    ChildRow stop(String deliveryId, String status, {int seq = 1}) => ChildRow(
          id: '', parentId: '', parentDocType: 'Delivery Route', tableName: 'stops', rowIndex: 0,
          payload: {'sequence': seq, 'sales_delivery': deliveryId, 'status': status},
        );

    test('appends status events and mirrors route + status onto the note', () async {
      final note = await engine.save(Document(id: '', docType: 'Delivery Note', payload: {'customer': 'C1'}), roles);
      final route = await engine.save(
        Document(id: '', docType: 'Delivery Route', payload: {'route_date': '2026-01-01', 'status': 'Dispatched'},
            children: {'stops': [stop(note.id, 'Loaded')]}),
        roles,
      );

      await service.reconcile(route);

      final events = await engine.list('Delivery Status Event', userRoles: roles);
      expect(events.length, 1);
      expect(events.single.id, 'DSE-${route.id}-1-0');
      expect(events.single.payload['status'], 'Loaded');

      final mirrored = (await engine.fetch('Delivery Note', note.id))!;
      expect(mirrored.payload['delivery_route'], route.id);
      expect(mirrored.payload['route_status'], 'Loaded');
    });

    test('a status change appends a second event; re-running is idempotent', () async {
      final note = await engine.save(Document(id: '', docType: 'Delivery Note', payload: {'customer': 'C1'}), roles);
      var route = await engine.save(
        Document(id: '', docType: 'Delivery Route', payload: {'route_date': '2026-01-01'},
            children: {'stops': [stop(note.id, 'Loaded')]}),
        roles,
      );
      await service.reconcile(route);

      // Advance the stop to Delivered and reconcile again.
      route.children['stops']!.single.payload['status'] = 'Delivered';
      route = await engine.save(route, roles);
      await service.reconcile(route);

      var events = await engine.list('Delivery Status Event', userRoles: roles);
      expect(events.length, 2);
      expect(events.map((e) => e.payload['status']).toSet(), {'Loaded', 'Delivered'});
      expect((await engine.fetch('Delivery Note', note.id))!.payload['route_status'], 'Delivered');

      // No status change → no new event.
      await service.reconcile(route);
      events = await engine.list('Delivery Status Event', userRoles: roles);
      expect(events.length, 2);
    });
  });
}
