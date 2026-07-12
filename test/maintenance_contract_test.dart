import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_hub_app/field_service/maintenance_contract_service.dart';
import 'package:mercantis_hub_app/ledger/ledger_values.dart' hide isTrue;
import 'package:mercantis_hub_app/manifest/hub_manifest.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// V1-5: a Maintenance Contract generates its own jobs — one per elapsed
/// period, template tables copied fresh, next date advanced, dispatch
/// queue fed. Same guarantees as recurring invoices: capped catch-up,
/// idempotent re-runs, failures stamped on the contract.
void main() {
  setUpAll(sqfliteFfiInit);

  late MercantisDatabase db;
  late DocumentEngine engine;
  late MaintenanceContractService service;
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
    service = MaintenanceContractService(engine: engine);

    await engine.save(
        Document(id: 'CUST-1', docType: 'Customer', payload: {
          'customer_name': 'C', 'customer_type': 'Company',
        }),
        roles);
    await engine.save(
        Document(id: 'FILTER', docType: 'Item', payload: {
          'item_code': 'FILTER', 'item_name': 'Filter',
          'item_type': 'Stock', 'stock_uom': 'Nos',
        }),
        roles);
  });

  tearDown(() async => db.close());

  Future<Document> contract({
    String frequency = 'Quarterly',
    String next = '2026-01-15',
    String? end,
    bool active = true,
  }) async {
    final doc = Document(id: '', docType: 'Maintenance Contract', payload: {
      'subject': 'Aircon service',
      'customer': 'CUST-1',
      'address': 'Roof plant room',
      'frequency': frequency,
      'start_date': '2026-01-15',
      'next_job_date': next,
      if (end != null) 'end_date': end,
      'active': active ? 1 : 0,
      'priority': 'Medium',
      'description': 'Clean coils, check gas.',
    });
    doc.children['checklist'] = [
      ChildRow(
        id: '', parentId: '', parentDocType: 'Maintenance Contract',
        tableName: 'checklist', rowIndex: 0,
        payload: {'task': 'Clean coils', 'done': 1}, // template noise
      ),
    ];
    doc.children['materials'] = [
      ChildRow(
        id: '', parentId: '', parentDocType: 'Maintenance Contract',
        tableName: 'materials', rowIndex: 0,
        payload: {'item': 'FILTER', 'qty': 2},
      ),
    ];
    return engine.save(doc, roles);
  }

  test('elapsed periods each yield a job with the template copied fresh',
      () async {
    final mc = await contract(); // due 15 Jan, quarterly
    final run = await service.generateDue(asOf: '2026-05-01');

    // Jan 15 and Apr 15 have elapsed; Jul 15 has not.
    expect(run.generated, hasLength(2));
    expect(run.failures, isEmpty);

    final job = await engine.fetch('Job', run.generated.first);
    expect(job!.payload['subject'], contains('Aircon service'));
    expect(job.payload['subject'], contains('2026-01-15'));
    expect(job.payload['customer'], 'CUST-1');
    expect(job.payload['maintenance_contract'], mc.id);
    expect(job.payload['status'], 'Draft'); // dispatch queue, not scheduled
    expect(job.children['checklist']!.single.payload['task'],
        'Clean coils');
    // The template's ticked box does NOT carry over — fresh job, unticked.
    expect(job.children['checklist']!.single.payload['done'], isNull);
    expect(job.children['materials']!.single.payload['item'], 'FILTER');

    final updated = await engine.fetch('Maintenance Contract', mc.id);
    expect(updated!.payload['next_job_date'], '2026-07-15');
    expect(updated.payload['last_generated_on'], '2026-04-15');

    // Re-running the same day creates nothing new.
    final again = await service.generateDue(asOf: '2026-05-01');
    expect(again.generated, isEmpty);
  });

  test('inactive contracts and end dates stop generation', () async {
    await contract(active: false);
    expect((await service.generateDue(asOf: '2026-05-01')).generated,
        isEmpty);

    await contract(next: '2026-01-15', end: '2026-02-01');
    final run = await service.generateDue(asOf: '2026-12-31');
    expect(run.generated, hasLength(1)); // only the January visit
  });

  test('a contract that cannot generate stamps last_error and the run '
      'continues', () async {
    final broken = await contract();
    // Sabotage: point the contract at a customer that no longer exists.
    broken.payload['customer'] = '';
    await db.db.rawUpdate(
      "UPDATE documents SET payload = REPLACE(payload, 'CUST-1', 'GONE') "
      'WHERE id = ?',
      [broken.id],
    );
    final healthy = await contract(next: '2026-01-15');

    final run = await service.generateDue(asOf: '2026-02-01');
    expect(run.generated, hasLength(1)); // the healthy one still ran
    expect(run.failures.keys, [broken.id]);
    final stamped =
        await engine.fetch('Maintenance Contract', broken.id);
    expect('${stamped!.payload['last_error']}', isNotEmpty);
  });
}
