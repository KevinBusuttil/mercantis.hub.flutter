import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_hub_app/modules/accounting/coa_repair.dart';
import 'package:mercantis_hub_app/manifest/hub_manifest.dart';
import 'package:mercantis_hub_app/onboarding/hub_seeder.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// H10 — Repair Chart of Accounts: re-create missing starter accounts and
/// re-wire broken Company default-account links.
void main() {
  setUpAll(sqfliteFfiInit);

  late MercantisDatabase db;
  late DocumentEngine engine;
  late ChartOfAccountsRepair repair;
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
    repair = ChartOfAccountsRepair(engine: engine, roles: roles);
    await HubSeeder(engine, roles: roles)
        .seed(businessName: 'Acme', currencyCode: 'EUR', year: 2026);
  });

  tearDown(() async => db.close());

  test('a healthy chart is left untouched (idempotent)', () async {
    final summary = await repair.repair();
    expect(summary.accountsCreated, 0);
    expect(summary.defaultsRewired, 0);
    expect(summary.repairedAnything, isFalse);
  });

  test('a missing starter account is re-created', () async {
    // Simulate drift: drop the Sales account.
    await engine.delete('Account', 'Sales', roles);
    expect(await engine.fetch('Account', 'Sales'), isNull);

    final summary = await repair.repair();
    expect(summary.accountsCreated, 1);
    final sales = await engine.fetch('Account', 'Sales');
    expect(sales, isNotNull);
    expect(sales!.payload['root_type'], 'Income');
  });

  test('blank company defaults are re-wired', () async {
    final company = (await engine.list('Company', userRoles: roles)).first;
    // Blank links save fine; the repair should re-point them.
    company.payload['default_receivable_account'] = '';
    company.payload['default_income_account'] = '';
    await engine.save(company, roles);

    final summary = await repair.repair();
    expect(summary.defaultsRewired, 2);
    final fixed = await engine.fetch('Company', company.id);
    expect(fixed!.payload['default_receivable_account'], 'Debtors');
    expect(fixed.payload['default_income_account'], 'Sales');
  });

  test('a default pointing at a deleted (custom) account is re-wired', () async {
    // A valid custom account referenced by the company, then removed — so the
    // stored link dangles without the company ever saving an invalid ref.
    await engine.save(
        Document(id: 'CUSTOM-RECV', docType: 'Account', payload: {
          'account_name': 'Custom Receivable', 'root_type': 'Asset',
        }),
        roles);
    final company = (await engine.list('Company', userRoles: roles)).first;
    company.payload['default_receivable_account'] = 'CUSTOM-RECV';
    await engine.save(company, roles);
    await engine.delete('Account', 'CUSTOM-RECV', roles); // now dangling

    final summary = await repair.repair();
    expect(summary.defaultsRewired, 1);
    final fixed = await engine.fetch('Company', company.id);
    expect(fixed!.payload['default_receivable_account'], 'Debtors');
  });

  test('re-creating a deleted starter account fixes the dangle without rewiring',
      () async {
    // Debtors is a starter account the company already points at; deleting it
    // dangles the ref, but step 1 re-creates it so no re-wire is needed.
    await engine.delete('Account', 'Debtors', roles);

    final summary = await repair.repair();
    expect(summary.accountsCreated, 1); // Debtors re-created
    expect(summary.defaultsRewired, 0); // ref valid again, untouched
    final company = (await engine.list('Company', userRoles: roles)).first;
    expect(company.payload['default_receivable_account'], 'Debtors');
  });
}
