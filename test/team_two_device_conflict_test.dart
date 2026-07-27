import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_hub_app/manifest/hub_manifest.dart';
import 'package:mercantis_hub_app/team/team_sync_runner.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// A-2 — the scripted two-device shakedown: two full engine + sync stacks
/// against one shared fake Team server, driving the exact flows a real
/// two-device book hits. Concurrent edits to the same record must surface
/// a manual conflict on the second writer (never silent last-write-wins),
/// resolution must converge both devices, and identical concurrent
/// creations (deterministic seeds) must merge silently.
void main() {
  setUpAll(sqfliteFfiInit);

  const roles = {'System Manager'};

  late _FakeTeamServer server;
  late _Device a;
  late _Device b;

  setUp(() async {
    server = _FakeTeamServer();
    a = await _Device.start('devA', server);
    b = await _Device.start('devB', server);
  });

  tearDown(() async {
    await a.close();
    await b.close();
  });

  Future<Document> saveCustomer(_Device d, String id, String name) =>
      d.engine.save(
        Document(id: id, docType: 'Customer', payload: {
          'customer_name': name,
          'customer_type': 'Company',
        }),
        roles,
      );

  Future<String?> customerName(_Device d, String id) async =>
      (await d.engine.fetch('Customer', id))?.payload['customer_name']
          as String?;

  /// Creates CUST-1 on A and replicates it to B, both ending synced.
  Future<void> replicateBaseline() async {
    await saveCustomer(a, 'CUST-1', 'Original');
    await a.run();
    await b.run();
    expect(await customerName(b, 'CUST-1'), 'Original');
    expect(await a.syncStateOf('CUST-1'), 'synced');
    expect(await b.syncStateOf('CUST-1'), 'synced');
  }

  /// Both devices edit CUST-1 while "offline"; A syncs first, then B —
  /// the second writer gets the conflict.
  Future<void> concurrentEdit() async {
    await replicateBaseline();
    await saveCustomer(a, 'CUST-1', 'Edit A');
    await saveCustomer(b, 'CUST-1', 'Edit B');
    await a.run(); // A wins the race to the server
    await b.run(); // B pulls A's edit onto its own unshipped edit
  }

  test('concurrent edits conflict on the second writer, never silently',
      () async {
    await concurrentEdit();

    // B: flagged, local edit preserved, remote candidate stored.
    expect(await b.syncStateOf('CUST-1'), 'conflict');
    expect(await customerName(b, 'CUST-1'), 'Edit B');
    final conflict = (await b.conflictService.listConflicts()).single;
    expect(conflict.documentId, 'CUST-1');
    expect(
        jsonDecode(conflict.remote.payload['payload'] as String)[
            'customer_name'],
        'Edit A');

    // B's own edit was HELD, not pushed — the server log must not carry it.
    expect(server.log.where((m) => m.deviceId == 'devB'), isEmpty);

    // A is untouched and unaware — only the second writer resolves.
    expect(await customerName(a, 'CUST-1'), 'Edit A');
    expect(await a.conflictService.count(), 0);
  });

  test('take-theirs converges both devices on the remote edit', () async {
    await concurrentEdit();

    await b.conflictService.takeTheirs('Customer', 'CUST-1');

    expect(await customerName(b, 'CUST-1'), 'Edit A');
    expect(await b.syncStateOf('CUST-1'), 'synced');
    expect(await b.conflictService.count(), 0);

    // Nothing left to ship; both devices settle on "Edit A".
    await b.run();
    await a.run();
    expect(await customerName(a, 'CUST-1'), 'Edit A');
    expect(server.log.where((m) => m.deviceId == 'devB'), isEmpty);
  });

  test('keep-mine converges both devices on the local edit', () async {
    await concurrentEdit();

    await b.conflictService.keepMine('Customer', 'CUST-1');
    expect(await b.conflictService.count(), 0);

    await b.run(); // ships "Edit B"
    await a.run(); // A is clean → fast-forwards onto B's version

    expect(await customerName(a, 'CUST-1'), 'Edit B');
    expect(await customerName(b, 'CUST-1'), 'Edit B');
    expect(await a.conflictService.count(), 0);
    expect(await a.syncStateOf('CUST-1'), 'synced');
  });

  test('identical concurrent creations merge silently (seed records)',
      () async {
    // Both devices lay down the same record — the deterministic-seed
    // situation at every second-device join. No conflict, no noise.
    await saveCustomer(a, 'CUST-SEED', 'Same Name');
    await saveCustomer(b, 'CUST-SEED', 'Same Name');
    await a.run();
    await b.run();

    expect(await b.conflictService.count(), 0);
    expect(await b.syncStateOf('CUST-SEED'), 'synced');
    expect(await customerName(b, 'CUST-SEED'), 'Same Name');
  });

  test('a clean device just fast-forwards a stream of foreign edits',
      () async {
    await replicateBaseline();
    await saveCustomer(a, 'CUST-1', 'Rev 2');
    await a.run();
    await saveCustomer(a, 'CUST-1', 'Rev 3');
    await a.run();
    await b.run();

    expect(await customerName(b, 'CUST-1'), 'Rev 3');
    expect(await b.conflictService.count(), 0);
  });
}

/// The Team backend reduced to its sync contract: an ordered mutation log
/// with server-assigned versions. Shared by both device adapters.
class _FakeTeamServer {
  final log = <MutationRecord>[];
  int _version = 0;

  void accept(List<MutationRecord> mutations) {
    for (final m in mutations) {
      log.add(MutationRecord.fromWireJson(m.toWireJson())
        ..syncVersion = '${++_version}');
    }
  }

  List<MutationRecord> after(String? afterVersion) {
    final cursor = int.tryParse(afterVersion ?? '') ?? 0;
    return [
      for (final m in log)
        if ((int.tryParse(m.syncVersion ?? '') ?? 0) > cursor)
          MutationRecord.fromWireJson(m.toWireJson())
            ..syncVersion = m.syncVersion,
    ];
  }
}

class _ServerAdapter extends NoOpCloudAdapter {
  _ServerAdapter(this.server);
  final _FakeTeamServer server;

  @override
  Future<void> push(List<MutationRecord> mutations) async =>
      server.accept(mutations);

  @override
  Future<List<MutationRecord>> pull(String? afterSyncVersion) async =>
      server.after(afterSyncVersion);
}

class _MemCursorStore extends TeamSyncCursorStore {
  int cursor = 0;

  @override
  Future<int> load(String companyId) async => cursor;

  @override
  Future<void> save(String companyId, int value) async => cursor = value;
}

/// One simulated device: its own database, engine, runner, and conflict
/// service — the full client stack minus the UI.
class _Device {
  _Device._(this.deviceId, this.db, this.registry, this.engine, this.runner,
      this.syncEngine, this.conflictService, this._tempDir);

  final String deviceId;
  final MercantisDatabase db;
  final Directory _tempDir;
  final MetadataRegistry registry;
  final DocumentEngine engine;
  final TeamSyncRunner runner;
  final SyncEngine syncEngine;
  final ConflictService conflictService;

  static Future<_Device> start(
      String deviceId, _FakeTeamServer server) async {
    // NOT inMemoryDatabasePath: the ffi factory caches databases by path,
    // so two ':memory:' opens would silently share ONE database — and a
    // "two-device" test against a single store proves nothing. Each
    // device gets its own temp file, removed in [close].
    final dir = await Directory.systemTemp.createTemp('atlas-2dev-');
    final db = await MercantisDatabase.open(
        factory: databaseFactoryFfi, path: '${dir.path}/$deviceId.db');
    final registry = MetadataRegistry(db.db);
    final sync = SyncEngine(database: db.db, registry: registry);
    await AppInstaller(database: db.db, registry: registry, syncEngine: sync)
        .install(HubManifest.build());
    final engine = DocumentEngine(
      database: db.db,
      registry: registry,
      metaComposer: MetaComposer(registry, db.db),
      permissionEngine: const PermissionEngine(),
      workflowEngine: WorkflowEngine(db.db),
      expressionEvaluator: ExpressionEvaluator(),
      namingService: NamingService(),
      syncEngine: sync,
      emitter: EventEmitter(),
      deviceId: deviceId,
      userId: 'user-$deviceId',
      interceptors: const [],
    );
    final runner = TeamSyncRunner(
      database: db.db,
      registry: registry,
      adapter: _ServerAdapter(server),
      localDeviceId: deviceId,
      companyId: 'comp-1',
      cursorStore: _MemCursorStore(),
    );
    final conflictService = ConflictService(
      database: db.db,
      syncEngine: sync,
      deviceId: deviceId,
      userId: 'user-$deviceId',
    );
    return _Device._(
        deviceId, db, registry, engine, runner, sync, conflictService, dir);
  }

  Future<TeamSyncResult> run() => runner.run();

  Future<String?> syncStateOf(String id) async {
    final rows =
        await db.db.query('documents', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : rows.single['sync_state'] as String?;
  }

  Future<void> close() async {
    syncEngine.dispose();
    await db.close();
    try {
      await _tempDir.delete(recursive: true);
    } catch (_) {}
  }
}
