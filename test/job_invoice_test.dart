import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_hub_app/field_service/job_service.dart';
import 'package:mercantis_hub_app/ledger/hub_interceptors.dart';
import 'package:mercantis_hub_app/ledger/ledger_derivation_service.dart';
import 'package:mercantis_hub_app/ledger/ledger_values.dart' hide isTrue;
import 'package:mercantis_hub_app/manifest/hub_manifest.dart';
import 'package:mercantis_hub_app/pricing/price_resolver.dart';
import 'package:mercantis_hub_app/scheduling/scheduling_service.dart';
import 'package:mercantis_hub_app/onboarding/hub_seeder.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// V1-2 acceptance: a plumber's day makes correct books.
///
///   1. Buy 5 valves @ €10 into the VAN     → van stock 5, value €50
///   2. Job uses 2 valves + 2h labour @ €40 → invoice: 2×€25 + 2×€40 = €130
///   3. Submit the invoice                  → van stock 3, COGS €20,
///                                            income €130, receivable €130
void main() {
  setUpAll(sqfliteFfiInit);

  late MercantisDatabase db;
  late DocumentEngine engine;
  late LedgerDerivationService ledger;
  late JobService jobs;
  const roles = {'System Manager'};
  final today = DateTime.now().toIso8601String().split('T').first;

  Future<void> until(Future<bool> Function() ready) async {
    for (var i = 0; i < 200; i++) {
      if (await ready()) return;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    fail('condition never became true');
  }

  Future<num> glBalance(String account) async {
    num balance = 0;
    for (final gl in await engine.list('GL Entry', userRoles: roles)) {
      if (gl.payload['account'] != account) continue;
      balance += asNum(gl.payload['debit']) - asNum(gl.payload['credit']);
    }
    return balance;
  }

  Future<num> binQty(String item, String warehouse) async {
    for (final b in await engine.list('Bin', userRoles: roles)) {
      if (b.payload['item'] == item && b.payload['warehouse'] == warehouse) {
        return asNum(b.payload['actual_qty']);
      }
    }
    return 0;
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
      userId: 'u',
      interceptors: const [
        BusinessProfileDefaultsInterceptor(),
        PriceResolutionInterceptor(),
        LineItemTotalsInterceptor(),
        TaxCalculationInterceptor(),
        NegativeStockGuardInterceptor(),
        AppointmentConflictInterceptor(),
      ],
    );
    await HubSeeder(engine, roles: roles).seed(
        businessName: 'Pipes Ltd',
        currencyCode: 'EUR',
        year: DateTime.now().year);
    ledger = LedgerDerivationService(engine: engine, emitter: emitter)
      ..start();
    jobs = JobService(engine);

    await engine.save(
        Document(id: 'VAN', docType: 'Warehouse',
            payload: {'warehouse_name': 'Van 1'}),
        roles);
    await engine.save(
        Document(id: 'CUST-1', docType: 'Customer', payload: {
          'customer_name': 'C', 'customer_type': 'Individual',
        }),
        roles);
    await engine.save(
        Document(id: 'SUPP-1', docType: 'Supplier', payload: {
          'supplier_name': 'S', 'supplier_type': 'Company',
        }),
        roles);
    await engine.save(
        Document(id: 'VALVE', docType: 'Item', payload: {
          'item_code': 'VALVE', 'item_name': 'Valve',
          'item_type': 'Stock', 'stock_uom': 'Nos',
          'valuation_method': 'Moving Average',
          'standard_rate': 25,
        }),
        roles);
    await engine.save(
        Document(id: 'LABOUR', docType: 'Item', payload: {
          'item_code': 'LABOUR', 'item_name': 'Labour',
          'item_type': 'Service', 'stock_uom': 'Hour',
        }),
        roles);

    // 5 valves @ €10 into the van.
    final pi = Document(id: '', docType: 'Purchase Invoice', payload: {
      'supplier': 'SUPP-1',
      'posting_date': today,
      'update_stock': 1,
      'set_warehouse': 'VAN',
    });
    pi.children['items'] = [
      ChildRow(
        id: '', parentId: '', parentDocType: 'Purchase Invoice',
        tableName: 'items', rowIndex: 0,
        payload: {'item': 'VALVE', 'qty': 5, 'rate': 10},
      ),
    ];
    await engine.submit(await engine.save(pi, roles), roles);
    await until(() async => (await binQty('VALVE', 'VAN')) == 5);
  });

  tearDown(() async {
    ledger.dispose();
    await db.close();
  });

  Future<Document> jobWithWork() async {
    final job = Document(id: '', docType: 'Job', payload: {
      'subject': 'Replace valves',
      'customer': 'CUST-1',
      'status': 'In Progress',
    });
    job.children['materials'] = [
      ChildRow(
        id: '', parentId: '', parentDocType: 'Job',
        tableName: 'materials', rowIndex: 0,
        payload: {'item': 'VALVE', 'qty': 2, 'warehouse': 'VAN'},
      ),
    ];
    job.children['labour'] = [
      ChildRow(
        id: '', parentId: '', parentDocType: 'Job',
        tableName: 'labour', rowIndex: 0,
        payload: {
          'description': 'Replace and test',
          'hours': 2,
          'rate': 40,
          'labour_item': 'LABOUR',
        },
      ),
    ];
    return engine.save(job, roles);
  }

  test('a job invoices its materials and labour, issuing van stock + COGS',
      () async {
    final job = await jobWithWork();
    final draft = await jobs.invoiceForJob(job.id, postingDate: today);

    // The draft: valve line priced by S8 (standard rate 25), labour 2×40,
    // stock issue armed from the van.
    expect(draft.docStatus, 0);
    expect(asNum(draft.payload['update_stock']), 1);
    expect(draft.payload['set_warehouse'], 'VAN');
    final lines = draft.children['items']!;
    expect(lines, hasLength(2));
    expect(asNum(lines[0].payload['rate']), 25); // S8 standard rate
    expect(lines[0].payload['warehouse'], 'VAN');
    expect(asNum(lines[1].payload['qty']), 2); // hours
    expect(asNum(lines[1].payload['rate']), 40);
    expect(asNum(draft.payload['grand_total']), 130);

    // Job stamped and completed.
    final stamped = await engine.fetch('Job', job.id);
    expect(stamped!.payload['sales_invoice'], draft.id);
    expect(stamped.payload['status'], 'Completed');

    // No double billing.
    await expectLater(
        jobs.invoiceForJob(job.id), throwsA(isA<StateError>()));

    // Submit → the van empties by 2 and the books are right.
    await engine.submit(draft, roles);
    await until(() async => (await binQty('VALVE', 'VAN')) == 3);
    await until(() async => (await glBalance('COGS')) == 20);
    expect(await glBalance('Sales'), -130); // income (credit)
    expect(await glBalance('Debtors'), 130); // receivable
  });

  test('a labour-only job never arms update_stock', () async {
    final job = Document(id: '', docType: 'Job', payload: {
      'subject': 'Consultation',
      'customer': 'CUST-1',
    });
    job.children['labour'] = [
      ChildRow(
        id: '', parentId: '', parentDocType: 'Job',
        tableName: 'labour', rowIndex: 0,
        payload: {'hours': 1, 'rate': 60, 'labour_item': 'LABOUR'},
      ),
    ];
    final saved = await engine.save(job, roles);
    final draft = await jobs.invoiceForJob(saved.id, postingDate: today);
    expect(draft.payload['update_stock'], isNull);
    expect(asNum(draft.payload['grand_total']), 60);
  });

  test('billable labour without a labour item is a clear error', () async {
    final job = Document(id: '', docType: 'Job', payload: {
      'subject': 'Oops',
      'customer': 'CUST-1',
    });
    job.children['labour'] = [
      ChildRow(
        id: '', parentId: '', parentDocType: 'Job',
        tableName: 'labour', rowIndex: 0,
        payload: {'hours': 3, 'rate': 40},
      ),
    ];
    final saved = await engine.save(job, roles);
    await expectLater(
      jobs.invoiceForJob(saved.id),
      throwsA(isA<StateError>().having(
          (e) => '$e', 'message', contains('labour item'))),
    );
  });

  test('an empty job has nothing to bill', () async {
    final saved = await engine.save(
        Document(id: '', docType: 'Job', payload: {
          'subject': 'Empty',
          'customer': 'CUST-1',
        }),
        roles);
    await expectLater(
        jobs.invoiceForJob(saved.id), throwsA(isA<StateError>()));
  });

  test('techTodayJobs picks the technician\'s day, soonest first', () {
    Document j(String id, String tech, String start,
            {String status = 'Scheduled'}) =>
        Document(id: id, docType: 'Job', payload: {
          'subject': id,
          'technician': tech,
          'starts_at': start,
          'status': status,
        });
    final picked = techTodayJobs([
      j('J-LATE', 'TECH-A', '2026-07-14T15:00:00'),
      j('J-EARLY', 'TECH-A', '2026-07-14T08:00:00'),
      j('J-OTHER-TECH', 'TECH-B', '2026-07-14T09:00:00'),
      j('J-OTHER-DAY', 'TECH-A', '2026-07-15T09:00:00'),
      j('J-CXL', 'TECH-A', '2026-07-14T10:00:00', status: 'Cancelled'),
      j('J-DONE', 'TECH-A', '2026-07-14T07:00:00', status: 'Completed'),
    ], technician: 'TECH-A', today: '2026-07-14');
    expect([for (final x in picked) x.id], ['J-DONE', 'J-EARLY', 'J-LATE']);
  });

  test('completeJob stores the sign-off and invoices; billable-less jobs '
      'still complete', () async {
    final job = await jobWithWork();
    final draft = await jobs.completeJob(
      job.id,
      signature: '{"strokes":[[[0.1,0.1],[0.9,0.9]]]}',
      note: 'Customer happy',
    );
    expect(draft, isNotNull);
    final done = await engine.fetch('Job', job.id);
    expect(done!.payload['completion_signature'], contains('strokes'));
    expect(done.payload['completion_note'], 'Customer happy');
    expect(done.payload['status'], 'Completed');
    expect(done.payload['sales_invoice'], draft!.id);

    // A job with no materials or labour completes without an invoice.
    final empty = await engine.save(
        Document(id: '', docType: 'Job', payload: {
          'subject': 'Quick look',
          'customer': 'CUST-1',
        }),
        roles);
    final none = await jobs.completeJob(empty.id, note: 'No work needed');
    expect(none, isNull);
    final finished = await engine.fetch('Job', empty.id);
    expect(finished!.payload['status'], 'Completed');
    expect(finished.payload['sales_invoice'], isNull);
  });
}
