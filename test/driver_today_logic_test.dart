import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_hub_app/deliveries/driver_today_logic.dart';
import 'package:mercantis_hub_app/deliveries/pod_capture.dart';
import 'package:mercantis_hub_app/manifest/hub_manifest.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// S12 driver UX: which route the driver sees (per-driver, today-first),
/// starting a route in one tap, and the run completing itself when the
/// last stop resolves.
void main() {
  group('selectTodayRoute', () {
    Document route(String id,
            {String? driver,
            required String date,
            String status = 'Dispatched'}) =>
        Document(id: id, docType: 'Delivery Route', payload: {
          'driver': driver,
          'route_date': date,
          'status': status,
        });

    const today = '2026-07-11';

    test('today first, preferring routes still in motion', () {
      final picked = selectTodayRoute([
        route('R-OLD', date: '2026-07-01'),
        route('R-DONE', date: today, status: 'Completed'),
        route('R-LIVE', date: today, status: 'Dispatched'),
      ], today: today);
      expect(picked!.id, 'R-LIVE');
    });

    test('driver filter hides other drivers; cancelled never shows', () {
      final routes = [
        route('R-ANNA', driver: 'DRV-A', date: today),
        route('R-BERT', driver: 'DRV-B', date: today),
        route('R-CXL', driver: 'DRV-A', date: today, status: 'Cancelled'),
      ];
      expect(selectTodayRoute(routes, driver: 'DRV-B', today: today)!.id,
          'R-BERT');
      expect(
          selectTodayRoute([routes[2]], driver: 'DRV-A', today: today),
          isNull);
    });

    test('nothing today falls back to the most recent route', () {
      final picked = selectTodayRoute([
        route('R-1', date: '2026-07-01'),
        route('R-2', date: '2026-07-09'),
      ], today: today);
      expect(picked!.id, 'R-2'); // yesterday's unfinished run still shows
    });
  });

  group('route lifecycle', () {
    setUpAll(sqfliteFfiInit);

    late MercantisDatabase db;
    late DocumentEngine engine;
    const roles = {'System Manager'};

    setUp(() async {
      db = await MercantisDatabase.open(
          factory: databaseFactoryFfi, path: inMemoryDatabasePath);
      final registry = MetadataRegistry(db.db);
      final sync = SyncEngine(database: db.db, registry: registry);
      await AppInstaller(
              database: db.db, registry: registry, syncEngine: sync)
          .install(HubManifest.build());
      engine = DocumentEngine(
        database: db.db,
        registry: registry,
        metaComposer: MetaComposer(registry, db.db),
        permissionEngine: const PermissionEngine(),
        workflowEngine: WorkflowEngine(db.db),
        expressionEvaluator: ExpressionEvaluator(),
        namingService: NamingService(),
        syncEngine: sync,
        emitter: EventEmitter(),
        deviceId: 'devA',
        userId: 'driver-1',
        interceptors: const [],
      );
      await engine.save(
          Document(id: 'CUST-1', docType: 'Customer', payload: {
            'customer_name': 'C', 'customer_type': 'Company',
          }),
          roles);
    });

    tearDown(() async => db.close());

    Future<String> plannedRoute(List<String> stopStatuses) async {
      final route = Document(id: '', docType: 'Delivery Route', payload: {
        'route_date': '2026-07-11',
        'status': 'Draft',
      });
      route.children['stops'] = [];
      for (var i = 0; i < stopStatuses.length; i++) {
        final note = await engine.save(
            Document(id: '', docType: 'Delivery Note', payload: {
              'customer': 'CUST-1',
              'posting_date': '2026-07-11',
            }),
            roles);
        route.children['stops']!.add(ChildRow(
          id: '', parentId: '', parentDocType: 'Delivery Route',
          tableName: 'stops', rowIndex: i,
          payload: {
            'sequence': i + 1,
            'sales_delivery': note.id,
            'customer': 'CUST-1',
            'status': stopStatuses[i],
          },
        ));
      }
      return (await engine.save(route, roles)).id;
    }

    test('startRoute sends waiting stops out and dispatches the route',
        () async {
      final id = await plannedRoute(['Pending', 'Loaded', 'Delivered']);
      await startRoute(engine, id);

      final route = await engine.fetch('Delivery Route', id);
      expect(route!.payload['status'], 'Dispatched');
      final statuses = [
        for (final s in route.children['stops']!) s.payload['status'],
      ];
      // Waiting stops go out; the already-delivered one is left alone.
      expect(statuses,
          ['Out for Delivery', 'Out for Delivery', 'Delivered']);
    });

    test('the run completes itself when the last stop resolves', () async {
      final id = await plannedRoute(['Out for Delivery', 'Out for Delivery']);

      await markStopStatus(engine,
          routeId: id, sequence: 1, status: 'Delivered');
      var route = await engine.fetch('Delivery Route', id);
      expect(route!.payload['status'], isNot('Completed')); // one left

      await markStopStatus(engine,
          routeId: id, sequence: 2, status: 'Failed',
          pod: const PodCapture(note: 'Nobody home'));
      route = await engine.fetch('Delivery Route', id);
      expect(route!.payload['status'], 'Completed');
    });
  });
}
