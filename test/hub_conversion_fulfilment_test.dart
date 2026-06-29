import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_hub_app/manifest/hub_manifest.dart';
import 'package:mercantis_hub_app/modules/selling/hub_conversion_actions.dart';
import 'package:mercantis_hub_app/onboarding/hub_seeder.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Regression: the remaining-qty conversions must net against what's already
/// been fulfilled. `DocumentEngine.list` hydrates only the parent payload — not
/// `document_children` — so [fulfilledByItemFromEngine] re-fetches each match by
/// id; otherwise totals come back empty and every repeat conversion re-proposes
/// the full original quantity (risking duplicate drafts).
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
      deviceId: 'devA',
      userId: 'u',
      interceptors: const [],
    );
    await HubSeeder(engine, roles: roles).seed(
        businessName: 'Acme', currencyCode: 'EUR', year: DateTime.now().year);
  });

  tearDown(() async => db.close());

  Future<Document> submittedDelivery(
      String orderId, List<({String item, num qty})> lines) async {
    final dn = Document(
      id: '',
      docType: 'Delivery Note',
      payload: {
        'customer': 'CUST-1',
        'posting_date': '2026-06-01',
        'sales_order': orderId,
      },
    );
    dn.children['items'] = [
      for (var i = 0; i < lines.length; i++)
        ChildRow(
          id: '',
          parentId: '',
          parentDocType: 'Delivery Note',
          tableName: 'items',
          rowIndex: i,
          payload: {'item': lines[i].item, 'qty': lines[i].qty, 'rate': 10},
        ),
    ];
    final saved = await engine.save(dn, roles);
    return engine.submit(saved, roles);
  }

  test('totals the shipped qty across submitted deliveries (children hydrated)',
      () async {
    final dn = await submittedDelivery('SO-1', [(item: 'ITEM-A', qty: 4)]);
    expect(dn.docStatus, 1);

    // list() alone leaves children empty — summing it would total nothing.
    final listed =
        await engine.list('Delivery Note', filters: {'sales_order': 'SO-1'});
    expect(listed.single.children['items'], isEmpty);

    // The helper re-fetches each match, so the shipped qty is counted.
    final totals = await fulfilledByItemFromEngine(
        engine, 'Delivery Note', 'sales_order', 'SO-1');
    expect(totals['ITEM-A'], 4);
  });

  test('sums across multiple submitted deliveries and ignores drafts',
      () async {
    await submittedDelivery('SO-2', [(item: 'ITEM-A', qty: 3)]);
    await submittedDelivery('SO-2', [(item: 'ITEM-A', qty: 2)]);

    // A draft (docStatus 0) for the same order must not be counted.
    final draft = Document(
      id: '',
      docType: 'Delivery Note',
      payload: {'customer': 'CUST-1', 'posting_date': '2026-06-01', 'sales_order': 'SO-2'},
    );
    draft.children['items'] = [
      ChildRow(
        id: '',
        parentId: '',
        parentDocType: 'Delivery Note',
        tableName: 'items',
        rowIndex: 0,
        payload: {'item': 'ITEM-A', 'qty': 99, 'rate': 10},
      ),
    ];
    await engine.save(draft, roles);

    final totals = await fulfilledByItemFromEngine(
        engine, 'Delivery Note', 'sales_order', 'SO-2');
    expect(totals['ITEM-A'], 5); // 3 + 2, draft's 99 excluded
  });
}
