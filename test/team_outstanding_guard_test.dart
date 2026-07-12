import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_hub_app/ledger/hub_interceptors.dart';
import 'package:mercantis_hub_app/ledger/ledger_derivation_service.dart';
import 'package:mercantis_hub_app/ledger/ledger_values.dart' hide isTrue;
import 'package:mercantis_hub_app/manifest/hub_manifest.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Phase 0.3 (gap analysis §8-C10): the local outstanding recompute must
/// keep its hands off documents the Team backend posted. The backend
/// maintains outstanding_amount itself and replicates it; a locally
/// computed write would only enqueue a mutation the sync plane 409s into
/// permanent quarantine.
void main() {
  setUpAll(sqfliteFfiInit);

  late MercantisDatabase db;
  late DocumentEngine engine;
  late LedgerDerivationService ledger;
  const roles = {'System Manager'};
  final today = DateTime.now().toIso8601String().split('T').first;

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
      userId: 'u',
      interceptors: const [LineItemTotalsInterceptor(), TaxCalculationInterceptor()],
    );
    // Not started: recomputeOutstanding is exercised directly.
    ledger = LedgerDerivationService(engine: engine, emitter: emitter);
    await engine.save(
        Document(id: 'CUST-1', docType: 'Customer', payload: {
          'customer_name': 'C', 'customer_type': 'Company',
        }),
        roles);
    await engine.save(
        Document(id: 'ITEM-A', docType: 'Item', payload: {
          'item_code': 'ITEM-A', 'item_name': 'A',
          'item_type': 'Service', 'stock_uom': 'Nos',
        }),
        roles);
  });

  tearDown(() async {
    ledger.dispose();
    await db.close();
  });

  Future<Document> submittedInvoice() async {
    final si = Document(id: '', docType: 'Sales Invoice', payload: {
      'customer': 'CUST-1',
      'posting_date': today,
    });
    si.children['items'] = [
      ChildRow(
        id: '', parentId: '', parentDocType: 'Sales Invoice',
        tableName: 'items', rowIndex: 0,
        payload: {'item': 'ITEM-A', 'qty': 1, 'rate': 44},
      ),
    ];
    return engine.submit(await engine.save(si, roles), roles);
  }

  Future<int> pendingMutations() async {
    final rows = await db.db.rawQuery(
        'SELECT COUNT(*) AS c FROM sync_queue WHERE status = ?',
        [MutationStatus.pending.name]);
    return (rows.first['c'] as int?) ?? 0;
  }

  test('backend-posted invoices (official_number) are never rewritten',
      () async {
    final invoice = await submittedInvoice();
    // Simulate the backend's replicated state: an official number and the
    // server-maintained outstanding (partially paid server-side).
    invoice.payload['official_number'] = 'SINV-00012';
    invoice.payload['outstanding_amount'] = 40;
    await engine.applyOnSubmitUpdate(invoice, roles);

    final before = await pendingMutations();
    // The local view has no settlements, so a naive recompute would "fix"
    // outstanding back to the grand total (44) and enqueue a doomed write.
    await ledger.recomputeOutstanding('Sales Invoice', invoice.id);

    final after = await engine.fetch('Sales Invoice', invoice.id);
    expect(asNum(after!.payload['outstanding_amount']), 40); // untouched
    expect(await pendingMutations(), before); // and nothing enqueued
  });

  test('locally posted invoices are still maintained (control)', () async {
    final invoice = await submittedInvoice();
    invoice.payload['outstanding_amount'] = 999; // force divergence
    await engine.applyOnSubmitUpdate(invoice, roles);

    await ledger.recomputeOutstanding('Sales Invoice', invoice.id);
    final after = await engine.fetch('Sales Invoice', invoice.id);
    expect(asNum(after!.payload['outstanding_amount']), 44); // corrected
  });
}
