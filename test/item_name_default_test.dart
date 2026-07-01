import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_hub_app/ledger/hub_interceptors.dart';
import 'package:mercantis_hub_app/manifest/hub_manifest.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// An Item saves with only its code (Item Name is optional and defaults to the
/// code), and an explicit name is preserved.
void main() {
  setUpAll(sqfliteFfiInit);
  late MercantisDatabase db;
  late DocumentEngine engine;
  const roles = {'System Manager'};

  setUp(() async {
    db = await MercantisDatabase.open(
        factory: databaseFactoryFfi, path: inMemoryDatabasePath);
    final registry = MetadataRegistry(db.db);
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
      deviceId: 'd',
      userId: 'u',
      interceptors: const [ItemNameDefaultInterceptor()],
    );
  });

  tearDown(() async => db.close());

  test('a code-only Item saves, with the name defaulted to the code', () async {
    // No item_name — previously blocked by the required-field guard.
    await engine.save(
        Document(id: 'WIDGET', docType: 'Item',
            payload: {'item_code': 'WIDGET'}),
        roles);
    final saved = await engine.fetch('Item', 'WIDGET');
    expect(saved, isNotNull);
    expect(saved!.payload['item_name'], 'WIDGET');
  });

  test('an explicit Item Name is preserved', () async {
    await engine.save(
        Document(id: 'BOLT', docType: 'Item',
            payload: {'item_code': 'BOLT', 'item_name': 'Hex Bolt'}),
        roles);
    final saved = await engine.fetch('Item', 'BOLT');
    expect(saved!.payload['item_name'], 'Hex Bolt');
  });
}
