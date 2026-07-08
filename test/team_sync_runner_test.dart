import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_hub_app/manifest/hub_manifest.dart';
import 'package:mercantis_hub_app/team/team_sync_runner.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Team milestone 3 — one sync exchange against the Team backend: push
/// pending mutations, pull past the cursor, apply only FOREIGN mutations
/// (own echoes are skipped but still advance the cursor), acknowledge.
/// A failed push strands nothing.
void main() {
  setUpAll(sqfliteFfiInit);

  late MercantisDatabase db;
  late MetadataRegistry registry;
  late DocumentEngine engine;
  const roles = {'System Manager'};
  const company = 'comp-1';

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = await MercantisDatabase.open(
        factory: databaseFactoryFfi, path: inMemoryDatabasePath);
    registry = MetadataRegistry(db.db);
    final sync = SyncEngine(database: db.db, registry: registry);
    await AppInstaller(database: db.db, registry: registry, syncEngine: sync)
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
      userId: 'u',
      interceptors: const [],
    );
  });

  tearDown(() async => db.close());

  TeamSyncRunner runner(http.Client client) => TeamSyncRunner(
        database: db.db,
        registry: registry,
        adapter: HttpCloudAdapter(
          baseUrl: 'https://sync.atlas.neuradix.app',
          companyId: company,
          deviceToken: 'dev-token',
          client: client,
        ),
        localDeviceId: 'devA',
        companyId: company,
      );

  /// A foreign device's create-document mutation, in the row-envelope shape
  /// applyRemoteMutations expects.
  Map<String, dynamic> foreignCustomer(String version) => MutationRecord(
        id: 'mut-devB-1',
        type: MutationType.createDocument,
        docType: 'Customer',
        documentId: 'CUST-B',
        payload: {
          'id': 'CUST-B',
          'doctype': 'Customer',
          'company': null,
          'docstatus': 0,
          'payload': jsonEncode({
            'customer_name': 'From device B',
            'customer_type': 'Individual',
          }),
          'created_at': 1751800000000,
          'modified_at': 1751800000000,
          'sync_version': null,
          'sync_state': 'local',
          'amended_from': null,
        },
        deviceId: 'devB',
        userId: 'maria',
        localTimestamp: DateTime.fromMillisecondsSinceEpoch(1751800000000),
        syncVersion: version,
      ).toWireJson();

  test('push → pull → apply foreign only → cursor advances → ack', () async {
    // A real local change recorded through the engine.
    await engine.save(
        Document(id: 'CUST-A', docType: 'Customer', payload: {
          'customer_name': 'From device A',
          'customer_type': 'Company',
        }),
        roles);

    final pushes = <Map<String, dynamic>>[];
    final acks = <List<dynamic>>[];
    Uri? pullUrl;
    final client = MockClient((req) async {
      if (req.url.path.endsWith('/sync/push')) {
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        pushes.add(body);
        final ids = [
          for (final m in body['mutations'] as List) '${(m as Map)['id']}',
        ];
        var version = 4;
        return http.Response(
            jsonEncode({
              'versions': {for (final id in ids) id: ++version},
            }),
            200);
      }
      if (req.url.path.endsWith('/sync/pull')) {
        pullUrl = req.url;
        // Echo back THIS device's customer mutation (deviceId devA) with its
        // assigned version, plus a foreign device's customer.
        final ownEcho = ((pushes.first['mutations'] as List)
                .cast<Map<String, dynamic>>())
            .firstWhere((m) => m['documentId'] == 'CUST-A');
        return http.Response(
            jsonEncode({
              'mutations': [
                {...ownEcho, 'syncVersion': '5'},
                foreignCustomer('6'),
              ],
            }),
            200);
      }
      if (req.url.path.endsWith('/sync/ack')) {
        acks.add(jsonDecode(req.body)['ids'] as List);
        return http.Response(jsonEncode({'acknowledged': 2}), 200);
      }
      fail('unexpected request: ${req.url}');
    });

    final result = await runner(client).run();

    expect(result.pushed, greaterThanOrEqualTo(1));
    expect(result.pulled, 2);
    expect(result.applied, 1); // the own echo was filtered

    // The foreign customer is now a local document; ours wasn't duplicated.
    final fromB = await engine.fetch('Customer', 'CUST-B');
    expect(fromB!.payload['customer_name'], 'From device B');
    expect(pullUrl!.queryParameters['after'], '0'); // first pull: everything

    // The cursor advanced over BOTH pulled mutations (echo included).
    expect(await TeamSyncCursorStore().load(company), 6);
    expect(acks.single, containsAll(['mut-devB-1']));

    // Nothing pending; local queue fully pushed.
    final queue = await db.db.query('sync_queue',
        where: 'status = ?', whereArgs: [MutationStatus.pending.name]);
    expect(queue, isEmpty);
  });

  test('the next run pulls from the saved cursor and applies nothing new',
      () async {
    SharedPreferences.setMockInitialValues(
        {'hub.team_cursor.$company': 6});
    Uri? pullUrl;
    final client = MockClient((req) async {
      if (req.url.path.endsWith('/sync/push')) {
        // The fresh install's own app-manifest mutations still ship.
        final ids = [
          for (final m
              in (jsonDecode(req.body) as Map)['mutations'] as List)
            '${(m as Map)['id']}',
        ];
        var version = 6;
        return http.Response(
            jsonEncode({'versions': {for (final id in ids) id: ++version}}),
            200);
      }
      if (req.url.path.endsWith('/sync/pull')) {
        pullUrl = req.url;
        return http.Response(jsonEncode({'mutations': []}), 200);
      }
      fail('unexpected request: ${req.url}');
    });

    final result = await runner(client).run();
    expect(pullUrl!.queryParameters['after'], '6');
    expect(result.pulled, 0);
    expect(result.applied, 0);
  });

  test('a failed push strands nothing: the batch retries next run',
      () async {
    await engine.save(
        Document(id: 'CUST-C', docType: 'Customer', payload: {
          'customer_name': 'Retry me',
          'customer_type': 'Company',
        }),
        roles);

    var failPush = true;
    final client = MockClient((req) async {
      if (req.url.path.endsWith('/sync/push')) {
        if (failPush) {
          return http.Response(jsonEncode({'error': 'internal error'}), 500);
        }
        final ids = [
          for (final m
              in (jsonDecode(req.body) as Map)['mutations'] as List)
            '${(m as Map)['id']}',
        ];
        var version = 0;
        return http.Response(
            jsonEncode({'versions': {for (final id in ids) id: ++version}}),
            200);
      }
      if (req.url.path.endsWith('/sync/pull')) {
        return http.Response(jsonEncode({'mutations': []}), 200);
      }
      if (req.url.path.endsWith('/sync/ack')) {
        return http.Response(jsonEncode({'acknowledged': 0}), 200);
      }
      fail('unexpected request: ${req.url}');
    });

    await expectLater(
      runner(client).run(),
      throwsA(isA<CloudHttpException>()
          .having((e) => e.statusCode, 'statusCode', 500)),
    );
    // Returned to pending — not stranded in `pushing`.
    var queue = await db.db.query('sync_queue',
        where: 'status = ?', whereArgs: [MutationStatus.pending.name]);
    expect(queue, isNotEmpty);

    failPush = false;
    final retry = await runner(client).run();
    expect(retry.pushed, greaterThanOrEqualTo(1));
    queue = await db.db.query('sync_queue',
        where: 'status = ?', whereArgs: [MutationStatus.pending.name]);
    expect(queue, isEmpty);
  });
}
