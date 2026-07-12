import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_hub_app/deliveries/delivery_route_service.dart';
import 'package:mercantis_hub_app/deliveries/pod_capture.dart';
import 'package:mercantis_hub_app/ledger/ledger_values.dart' hide isTrue;
import 'package:mercantis_hub_app/manifest/hub_manifest.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// S3 capture: the driver marks a stop delivered WITH proof — signature
/// strokes, photo path, note, timestamp — persisted on the route stop, and
/// the existing route service turns the status change into an audit event
/// and mirrors it onto the Delivery Note.
void main() {
  setUpAll(sqfliteFfiInit);

  late MercantisDatabase db;
  late DocumentEngine engine;
  late DeliveryRouteService service;
  const roles = {'System Manager'};

  Future<void> until(Future<bool> Function() ready) async {
    for (var i = 0; i < 100; i++) {
      if (await ready()) return;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    fail('condition never became true');
  }

  setUp(() async {
    db = await MercantisDatabase.open(
        factory: databaseFactoryFfi, path: inMemoryDatabasePath);
    final registry = MetadataRegistry(db.db);
    final sync = SyncEngine(database: db.db, registry: registry);
    await AppInstaller(database: db.db, registry: registry, syncEngine: sync)
        .install(HubManifest.build());
    final emitter = EventEmitter();
    engine = DocumentEngine(
      database: db.db,
      registry: registry,
      metaComposer: MetaComposer(registry, db.db),
      permissionEngine: const PermissionEngine(),
      workflowEngine: WorkflowEngine(db.db),
      expressionEvaluator: ExpressionEvaluator(),
      namingService: NamingService(),
      syncEngine: sync,
      emitter: emitter,
      deviceId: 'devA',
      userId: 'driver-1',
      interceptors: const [],
    );
    service = DeliveryRouteService(engine: engine, emitter: emitter)
      ..start();

    await engine.save(
        Document(id: 'CUST-1', docType: 'Customer', payload: {
          'customer_name': 'C', 'customer_type': 'Company',
        }),
        roles);
  });

  tearDown(() async {
    service.dispose();
    await db.close();
  });

  Future<(String route, String note)> plannedRoute() async {
    final note = await engine.save(
        Document(id: '', docType: 'Delivery Note', payload: {
          'customer': 'CUST-1',
          'posting_date': '2026-07-11',
        }),
        roles);
    final route = Document(id: '', docType: 'Delivery Route', payload: {
      'route_date': '2026-07-11',
      'status': 'Dispatched',
    });
    route.children['stops'] = [
      ChildRow(
        id: '', parentId: '', parentDocType: 'Delivery Route',
        tableName: 'stops', rowIndex: 0,
        payload: {
          'sequence': 1,
          'sales_delivery': note.id,
          'customer': 'CUST-1',
          'status': 'Out for Delivery',
        },
      ),
    ];
    final saved = await engine.save(route, roles);
    return (saved.id, note.id);
  }

  test('marking delivered persists the proof and flows to event + note',
      () async {
    final (routeId, noteId) = await plannedRoute();

    await markStopStatus(engine,
        routeId: routeId,
        sequence: 1,
        status: 'Delivered',
        pod: const PodCapture(
          signature: '{"strokes":[[[0.1,0.1],[0.9,0.9]]]}',
          photoPath: '/tmp/pod.jpg',
          note: 'Left with neighbour',
        ));

    final route = await engine.fetch('Delivery Route', routeId);
    final stop = route!.children['stops']!.single;
    expect(stop.payload['status'], 'Delivered');
    expect(stop.payload['pod_signature'], contains('strokes'));
    expect(stop.payload['pod_image'], '/tmp/pod.jpg');
    expect(stop.payload['pod_note'], 'Left with neighbour');
    expect(asNonEmpty(stop.payload['pod_time']), isNotNull);

    // The route service picked the save up: audit event + note mirror.
    await until(() async {
      final events = await engine.list('Delivery Status Event',
          filters: {'delivery_route': routeId}, userRoles: roles);
      return events.any((e) => e.payload['status'] == 'Delivered');
    });
    await until(() async {
      final n = await engine.fetch('Delivery Note', noteId);
      return n?.payload['route_status'] == 'Delivered';
    });
  });

  test('a failed stop records the reason without any proof fields',
      () async {
    final (routeId, _) = await plannedRoute();
    await markStopStatus(engine,
        routeId: routeId,
        sequence: 1,
        status: 'Failed',
        pod: const PodCapture(note: 'Nobody home'));

    final route = await engine.fetch('Delivery Route', routeId);
    final stop = route!.children['stops']!.single;
    expect(stop.payload['status'], 'Failed');
    expect(stop.payload['pod_note'], 'Nobody home');
    expect(stop.payload['pod_signature'], isNull);
  });

  test('unknown route or stop is a clear error', () async {
    await expectLater(
      markStopStatus(engine,
          routeId: 'ROUTE-NOPE', sequence: 1, status: 'Delivered'),
      throwsA(isA<StateError>()),
    );
    final (routeId, _) = await plannedRoute();
    await expectLater(
      markStopStatus(engine,
          routeId: routeId, sequence: 99, status: 'Delivered'),
      throwsA(isA<StateError>()),
    );
  });
}
