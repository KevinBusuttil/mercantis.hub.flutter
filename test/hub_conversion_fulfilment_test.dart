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
///
/// Uses Purchase Invoice as the downstream doc (the save+submit shape exercised
/// by capture_service_test / ledger_derivation_test) so the test turns on the
/// hydration behaviour, not on any one DocType's required fields.
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

  Document invoice(String orderId, num qty) {
    final pi = Document(
      id: '',
      docType: 'Purchase Invoice',
      payload: {
        'supplier': 'SUP-1',
        'posting_date': '2026-06-01',
        'purchase_order': orderId,
      },
    );
    pi.children['items'] = [
      ChildRow(
        id: '',
        parentId: '',
        parentDocType: 'Purchase Invoice',
        tableName: 'items',
        rowIndex: 0,
        payload: {'item': 'ITEM-A', 'description': 'A', 'qty': qty, 'rate': 10},
      ),
    ];
    return pi;
  }

  Future<Document> submittedInvoice(String orderId, num qty) async {
    final saved = await engine.save(invoice(orderId, qty), roles);
    return engine.submit(saved, roles);
  }

  test('totals the billed qty of submitted downstream docs (children hydrated)',
      () async {
    final pi = await submittedInvoice('PO-1', 4);
    expect(pi.docStatus, 1);

    // list() alone leaves children empty — summing it would total nothing,
    // which is exactly the bug this guards against.
    final listed =
        await engine.list('Purchase Invoice', filters: {'purchase_order': 'PO-1'});
    expect(listed.single.children['items'], isEmpty);

    // The helper re-fetches each match, so the billed qty is counted.
    final totals = await fulfilledByItemFromEngine(
        engine, 'Purchase Invoice', 'purchase_order', 'PO-1');
    expect(totals['ITEM-A'], 4);
  });

  test('sums across submitted docs and ignores drafts', () async {
    await submittedInvoice('PO-2', 3);
    await submittedInvoice('PO-2', 2);
    // A draft (docStatus 0) for the same order must not be counted.
    await engine.save(invoice('PO-2', 99), roles);

    final totals = await fulfilledByItemFromEngine(
        engine, 'Purchase Invoice', 'purchase_order', 'PO-2');
    expect(totals['ITEM-A'], 5); // 3 + 2, draft's 99 excluded
  });
}
