import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_hub_app/ledger/hub_interceptors.dart';
import 'package:mercantis_hub_app/ledger/ledger_values.dart' hide isTrue;
import 'package:mercantis_hub_app/manifest/hub_manifest.dart';
import 'package:mercantis_hub_app/modules/selling/recurring_invoice_service.dart';
import 'package:mercantis_hub_app/onboarding/hub_seeder.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Recurring invoices: templates draft their own Sales Invoices per elapsed
/// period, advance next_invoice_date, respect end dates and the active flag,
/// and record failures on the template.
void main() {
  group('nextBillingDate (pure)', () {
    test('advances by period, clamping month-end', () {
      expect(nextBillingDate('2026-01-15', 'Monthly'), '2026-02-15');
      expect(nextBillingDate('2026-01-31', 'Monthly'), '2026-02-28');
      expect(nextBillingDate('2026-01-05', 'Weekly'), '2026-01-12');
      expect(nextBillingDate('2026-01-31', 'Quarterly'), '2026-04-30');
      expect(nextBillingDate('2024-02-29', 'Yearly'), '2025-02-28');
      expect(nextBillingDate('2026-12-10', 'Monthly'), '2027-01-10');
    });
  });

  group('RecurringInvoiceService (engine)', () {
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
        interceptors: const [
          BusinessProfileDefaultsInterceptor(),
          LineItemTotalsInterceptor(),
          TaxCalculationInterceptor(),
          FiscalYearGuardInterceptor(),
        ],
      );
      await HubSeeder(engine, roles: roles).seed(
          businessName: 'Acme',
          currencyCode: 'EUR',
          year: DateTime.now().year);
      await engine.save(
          Document(id: 'CUST-1', docType: 'Customer', payload: {
            'customer_name': 'Retainer client',
            'customer_type': 'Company',
          }),
          roles);
      await engine.save(
          Document(id: 'SVC-1', docType: 'Item', payload: {
            'item_code': 'SVC-1',
            'item_name': 'Monthly retainer',
            'item_type': 'Service',
            'stock_uom': 'Nos',
          }),
          roles);
    });

    tearDown(() async => db.close());

    Future<Document> template({
      required String next,
      String? end,
      bool active = true,
      bool autoSubmit = false,
    }) async {
      final t = Document(id: '', docType: 'Recurring Invoice', payload: {
        'customer': 'CUST-1',
        'frequency': 'Monthly',
        'start_date': next,
        'next_invoice_date': next,
        if (end != null) 'end_date': end,
        'active': active ? 1 : 0,
        'auto_submit': autoSubmit ? 1 : 0,
      });
      t.children['items'] = [
        ChildRow(
          id: '', parentId: '', parentDocType: 'Recurring Invoice',
          tableName: 'items', rowIndex: 0,
          payload: {'item': 'SVC-1', 'qty': 1, 'rate': 500},
        ),
      ];
      return engine.save(t, roles);
    }

    test('one draft per elapsed period; the date advances past today',
        () async {
      final now = DateTime.now();
      // Due twice: two months ago and one month ago (billing anchored on the
      // 1st so month-length clamping can't skew the count).
      final start = DateTime(now.year, now.month - 2, 1);
      final t = await template(
          next: start.toIso8601String().split('T').first);

      final asOf = now.toIso8601String().split('T').first;
      final result = await RecurringInvoiceService(engine: engine)
          .generateDue(asOf: asOf);
      expect(result.failures, isEmpty);
      expect(result.generated.length, 3); // 2 months ago, 1 month ago, today

      final invoices =
          await engine.list('Sales Invoice', userRoles: roles);
      expect(invoices.length, 3);
      expect(invoices.every((i) => i.docStatus == 0), isTrue); // drafts
      final first = await engine.fetch('Sales Invoice', result.generated.first);
      expect(asNum(first!.payload['grand_total']), 500);
      expect(first.payload['recurring_invoice'], t.id);

      // The template advanced beyond asOf; a second run makes nothing.
      final rerun = await RecurringInvoiceService(engine: engine)
          .generateDue(asOf: asOf);
      expect(rerun.generated, isEmpty);
      final after = await engine.fetch('Recurring Invoice', t.id);
      expect('${after!.payload['next_invoice_date']}'.compareTo(asOf) > 0,
          isTrue);
    });

    test('inactive and ended templates generate nothing', () async {
      final past = DateTime(2026, 1, 1).toIso8601String().split('T').first;
      await template(next: past, active: false);
      await template(next: past, end: '2025-12-31'); // ended before due

      final result = await RecurringInvoiceService(engine: engine)
          .generateDue(asOf: '2026-02-01');
      expect(result.generated, isEmpty);
    });

    test('auto_submit posts the invoice instead of leaving a draft',
        () async {
      final now = DateTime.now();
      final today = now.toIso8601String().split('T').first;
      await template(next: today, autoSubmit: true);

      final result = await RecurringInvoiceService(engine: engine)
          .generateDue(asOf: today);
      expect(result.failures, isEmpty);
      expect(result.generated.length, 1);
      final invoice =
          await engine.fetch('Sales Invoice', result.generated.single);
      expect(invoice!.docStatus, 1);
    });

    test('a broken template records last_error and does not block others',
        () async {
      final today = DateTime.now().toIso8601String().split('T').first;
      // auto_submit into a date outside every Fiscal Year → the posting
      // guard rejects the submit, which the run must survive and record.
      final broken = Document(id: '', docType: 'Recurring Invoice', payload: {
        'customer': 'CUST-1',
        'frequency': 'Monthly',
        'start_date': '2020-01-01',
        'next_invoice_date': '2020-01-01',
        'active': 1,
        'auto_submit': 1,
      });
      broken.children['items'] = [
        ChildRow(
          id: '', parentId: '', parentDocType: 'Recurring Invoice',
          tableName: 'items', rowIndex: 0,
          payload: {'item': 'SVC-1', 'qty': 1, 'rate': 100},
        ),
      ];
      final saved = await engine.save(broken, roles);
      await template(next: today); // a healthy one alongside

      final result = await RecurringInvoiceService(engine: engine)
          .generateDue(asOf: today);
      expect(result.generated.length, 1); // healthy template still ran
      expect(result.failures.keys, contains(saved.id));
      final after = await engine.fetch('Recurring Invoice', saved.id);
      expect('${after!.payload['last_error']}', isNotEmpty);
    });
  });
}
