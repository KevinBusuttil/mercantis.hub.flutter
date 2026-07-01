import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_hub_app/modules/accounting/invoice_status_service.dart';
import 'package:mercantis_hub_app/manifest/hub_manifest.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// H2 — the invoice status rule + the engine-wired lookups.
void main() {
  group('InvoiceStatus.compute (pure)', () {
    String s({
      int docStatus = 1,
      num grand = 100,
      required num outstanding,
      String? due,
      String? asOf,
      bool isReturn = false,
    }) =>
        InvoiceStatus.compute(
          docStatus: docStatus,
          grandTotal: grand,
          outstanding: outstanding,
          dueDate: due,
          asOf: asOf,
          isReturn: isReturn,
        );

    test('draft / cancelled / return short-circuit', () {
      expect(s(docStatus: 0, outstanding: 100), 'Draft');
      expect(s(docStatus: 2, outstanding: 100), 'Cancelled');
      expect(s(outstanding: -100, isReturn: true), 'Return');
    });

    test('fully settled is Paid', () {
      expect(s(outstanding: 0), 'Paid');
      expect(s(outstanding: 0.004), 'Paid'); // within a cent
    });

    test('nothing settled is Unpaid; part settled is Partly Paid', () {
      expect(s(outstanding: 100), 'Unpaid');
      expect(s(outstanding: 40), 'Partly Paid');
    });

    test('past the due date with a balance is Overdue', () {
      expect(s(outstanding: 100, due: '2026-06-01', asOf: '2026-06-15'), 'Overdue');
      expect(s(outstanding: 40, due: '2026-06-01', asOf: '2026-06-15'), 'Overdue');
      // On or before due date it is not overdue.
      expect(s(outstanding: 100, due: '2026-06-30', asOf: '2026-06-15'), 'Unpaid');
      // Paid never becomes overdue.
      expect(s(outstanding: 0, due: '2026-06-01', asOf: '2026-06-15'), 'Paid');
    });
  });

  group('InvoiceStatusService (engine)', () {
    setUpAll(sqfliteFfiInit);
    late MercantisDatabase db;
    late DocumentEngine engine;
    late InvoiceStatusService service;
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
      service = InvoiceStatusService(engine: engine, roles: roles);
      await engine.save(
          Document(id: 'CUST-1', docType: 'Customer', payload: {
            'customer_name': 'Buyer', 'customer_type': 'Company',
          }),
          roles);
    });

    tearDown(() async => db.close());

    Future<Document> invoice(String id,
        {required num outstanding, required String due, int status = 1}) async {
      final inv = await engine.save(
          Document(id: id, docType: 'Sales Invoice', payload: {
            'customer': 'CUST-1',
            'posting_date': '2026-05-01',
            'due_date': due,
            'grand_total': 100,
            'outstanding_amount': outstanding,
          }),
          roles);
      if (status == 1) return engine.submit(inv, roles);
      return inv;
    }

    test('statusOf derives the invoice status as of a date', () async {
      await invoice('SI-1', outstanding: 100, due: '2026-06-01');
      expect(await service.statusOf('Sales Invoice', 'SI-1', asOf: '2026-06-15'),
          'Overdue');
      expect(await service.statusOf('Sales Invoice', 'SI-1', asOf: '2026-05-15'),
          'Unpaid');
    });

    test('a submitted invoice with no outstanding still reads as open', () async {
      // Only grand_total is set (outstanding never populated).
      final inv = await engine.save(
          Document(id: 'SI-9', docType: 'Sales Invoice', payload: {
            'customer': 'CUST-1',
            'posting_date': '2026-05-01',
            'due_date': '2026-06-01',
            'grand_total': 100,
          }),
          roles);
      await engine.submit(inv, roles);

      expect(await service.statusOf('Sales Invoice', 'SI-9', asOf: '2026-06-15'),
          'Overdue'); // not Paid
      expect((await service.overdue('Sales Invoice', asOf: '2026-06-15'))
          .map((d) => d.id), contains('SI-9'));
    });

    test('overdue lists only past-due invoices with a balance', () async {
      await invoice('SI-1', outstanding: 100, due: '2026-06-01'); // overdue
      await invoice('SI-2', outstanding: 0, due: '2026-05-01'); // paid
      await invoice('SI-3', outstanding: 50, due: '2026-06-30'); // not yet due

      final overdue = await service.overdue('Sales Invoice', asOf: '2026-06-15');
      expect(overdue.map((d) => d.id), ['SI-1']);
    });
  });
}
