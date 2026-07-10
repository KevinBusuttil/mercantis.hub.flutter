import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_hub_app/manifest/hub_manifest.dart';
import 'package:mercantis_hub_app/payments/pos_checkout.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Per-till POS receipt series (Phase 0.1, POS carve-out decision): a till
/// with a receipt series numbers independently — two registers can never
/// mint the same receipt id, even both offline. Without a series, the
/// shared yearly pattern still applies.
void main() {
  setUpAll(sqfliteFfiInit);

  late MercantisDatabase db;
  late DocumentEngine engine;
  const roles = {'System Manager'};
  final today = DateTime.now().toIso8601String().split('T').first;

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
      deviceId: 'devA',
      userId: 'u',
      interceptors: const [],
    );
    await engine.save(
        Document(id: 'ITEM-A', docType: 'Item', payload: {
          'item_code': 'ITEM-A',
          'item_name': 'Item A',
          'item_type': 'Service',
          'stock_uom': 'Nos',
        }),
        roles);
  });

  tearDown(() async => db.close());

  Future<Document> sale({String? tillSeries}) async {
    final draft = PosCheckout.buildPosInvoice(
      postingDate: today,
      tillSeries: tillSeries,
      lines: [const PosCartLine(item: 'ITEM-A', qty: 1, rate: 10)],
      tenders: [const PosTender(type: 'Cash', amount: 10)],
    );
    return engine.save(draft, roles);
  }

  test('each till series sequences independently; no cross-till collisions',
      () async {
    final t1a = await sale(tillSeries: 'TILL1');
    final t1b = await sale(tillSeries: 'TILL1');
    final t2a = await sale(tillSeries: 'TILL2');

    expect(t1a.id, contains('TILL1'));
    expect(t2a.id, contains('TILL2'));
    expect(t1a.id, isNot(t1b.id)); // same till increments
    // Both tills start their own series — same counter position, different
    // prefix — so ids can never collide across registers.
    expect(t1a.id.substring(t1a.id.lastIndexOf('-')),
        t2a.id.substring(t2a.id.lastIndexOf('-')));
    expect(t1a.payload['till_series'], 'TILL1');
  });

  test('no receipt series → the shared yearly pattern still applies',
      () async {
    final plain = await sale();
    expect(plain.id, startsWith('POS-'));
    expect(plain.id, contains('${DateTime.now().year}'));
    expect(plain.id, isNot(contains('TILL')));
  });
}
