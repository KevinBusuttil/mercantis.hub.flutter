import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_hub_app/ledger/hub_interceptors.dart';
import 'package:mercantis_hub_app/ledger/ledger_values.dart' hide isTrue;
import 'package:mercantis_hub_app/manifest/hub_manifest.dart';
import 'package:mercantis_hub_app/modules/projects/project_billing.dart';
import 'package:mercantis_hub_app/onboarding/business_preset.dart';
import 'package:mercantis_hub_app/onboarding/hub_seeder.dart';
import 'package:mercantis_hub_app/reports/aggregating_reports.dart';
import 'package:mercantis_hub_app/settings/hub_settings.dart';
import 'package:mercantis_hub_app/workspaces/hub_workspaces.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Projects (Phase 6): billing turns unbilled billable time + expenses into
/// a draft invoice exactly once; profitability reads invoiced vs costs; the
/// workspace follows the preset.
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
      interceptors: const [
        BusinessProfileDefaultsInterceptor(),
        LineItemTotalsInterceptor(),
        TaxCalculationInterceptor(),
        FiscalYearGuardInterceptor(),
        ExpenseDefaultsInterceptor(),
      ],
    );
    await HubSeeder(engine, roles: roles).seed(
        businessName: 'Acme', currencyCode: 'EUR', year: DateTime.now().year);
    await engine.save(
        Document(id: 'CUST-1', docType: 'Customer', payload: {
          'customer_name': 'Project client',
          'customer_type': 'Company',
        }),
        roles);
    await engine.save(
        Document(id: 'PROJ-1', docType: 'Project', payload: {
          'project_name': 'Website build',
          'customer': 'CUST-1',
          'status': 'Open',
          'default_billing_rate': 60,
        }),
        roles);
  });

  tearDown(() async => db.close());

  Future<Document> logTime(num hours,
      {num? rate, bool billable = true}) async {
    return engine.save(
        Document(id: '', docType: 'Timesheet', payload: {
          'project': 'PROJ-1',
          'activity_date': today,
          'hours': hours,
          'billable': billable ? 1 : 0,
          if (rate != null) 'billing_rate': rate,
          'description': 'Development',
        }),
        roles);
  }

  Future<Document> billableExpense(num net) async {
    return engine.submit(
        await engine.save(
            Document(id: '', docType: 'Expense', payload: {
              'posting_date': today,
              'description': 'Stock photos',
              'expense_account': 'COGS',
              'net_amount': net,
              'is_paid': 1,
              'project': 'PROJ-1',
              'billable': 1,
            }),
            roles),
        roles);
  }

  test('billing gathers unbilled work once; second run bills nothing',
      () async {
    await logTime(5); // 5h @ project default 60 = 300
    await logTime(2, rate: 100); // 2h @ own rate = 200
    await logTime(3, billable: false); // internal — never billed
    await billableExpense(45);

    final billing = ProjectBilling(engine: engine);
    final preview = await billing.preview('PROJ-1');
    expect(preview.timeValue, 500);
    expect(preview.expenseValue, 45);

    final invoice =
        await billing.createInvoice('PROJ-1', postingDate: today);
    expect(invoice, isNotNull);
    expect(invoice!.docStatus, 0); // draft — user reviews before sending
    expect(asNum(invoice.payload['grand_total']), 545);
    expect(invoice.payload['project'], 'PROJ-1');
    final hydrated = await engine.fetch('Sales Invoice', invoice.id);
    expect(hydrated!.children['items']!.length, 3); // 2 time + 1 expense

    // Sources are stamped billed with the invoice reference.
    final sheets =
        await engine.list('Timesheet', filters: {'project': 'PROJ-1'}, userRoles: roles);
    final billed = sheets.where((t) => t.payload['billed'] == 1);
    expect(billed.length, 2);
    expect(billed.every((t) => t.payload['sales_invoice'] == invoice.id),
        isTrue);

    // Retainer-safe: nothing left to bill.
    expect(await billing.createInvoice('PROJ-1', postingDate: today), isNull);
  });

  test('a project without a customer refuses to bill', () async {
    await engine.save(
        Document(id: 'PROJ-2', docType: 'Project', payload: {
          'project_name': 'Internal tooling',
          'status': 'Open',
        }),
        roles);
    await engine.save(
        Document(id: '', docType: 'Timesheet', payload: {
          'project': 'PROJ-2',
          'activity_date': today,
          'hours': 1,
          'billable': 1,
          'billing_rate': 50,
        }),
        roles);
    await expectLater(
      ProjectBilling(engine: engine)
          .createInvoice('PROJ-2', postingDate: today),
      throwsStateError,
    );
  });

  test('profitability: invoiced vs costs, hours, unbilled time', () async {
    await logTime(5); // unbilled 300
    await billableExpense(45); // cost 45

    // Bill and submit the invoice so it counts as invoiced.
    final billing = ProjectBilling(engine: engine);
    final invoice =
        (await billing.createInvoice('PROJ-1', postingDate: today))!;
    await engine.submit(await engine.fetch('Sales Invoice', invoice.id)
        as Document, roles);
    await logTime(2); // fresh unbilled 120 after billing

    final reports = HubAggregatingReports(engine.list, fetch: engine.fetch);
    final r = await reports.projectProfitability(userRoles: roles);
    final row = r.rows.firstWhere((row) => row[0] == 'Website build');
    expect(row[1], '345.00'); // invoiced 300 time + 45 expense
    expect(row[2], '45.00'); // costs
    expect(row[3], '7'); // 5 + 2 hours
    expect(row[4], '120.00'); // unbilled time value
    expect(row[5], '300.00'); // margin
  });

  test('projects workspace follows the preset', () {
    Set<String> ids(HubSettings s) =>
        hubWorkspaces(s).map((w) => w.id).toSet();
    expect(ids(const HubSettings().applyingPreset(BusinessPreset.services)),
        contains('projects'));
    expect(ids(const HubSettings().applyingPreset(BusinessPreset.retail)),
        isNot(contains('projects')));
    expect(ids(const HubSettings().applyingPreset(BusinessPreset.mixed)),
        contains('projects'));
  });
}
