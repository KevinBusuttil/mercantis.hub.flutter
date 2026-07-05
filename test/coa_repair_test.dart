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
    expect(summary.accountsReparented, 0);
    expect(summary.mastersCreated, 0);
    expect(summary.mastersReparented, 0);
    expect(summary.repairedAnything, isFalse);
  });

  test('a missing tree-master node is re-created', () async {
    await engine.delete('Item Group', 'Products', roles);
    final summary = await repair.repair();
    expect(summary.mastersCreated, greaterThanOrEqualTo(1));
    final products = await engine.fetch('Item Group', 'Products');
    expect(products, isNotNull);
    expect(products!.payload['parent_item_group'], 'All Item Groups');
  });

  test('a flat tree master is re-grouped — blank parents back-filled', () async {
    final retail = (await engine.fetch('Customer Group', 'Retail'))!;
    retail.payload['parent_customer_group'] = '';
    await engine.save(retail, roles);

    final summary = await repair.repair();
    expect(summary.mastersReparented, greaterThanOrEqualTo(1));
    final fixed = await engine.fetch('Customer Group', 'Retail');
    expect(fixed!.payload['parent_customer_group'], 'All Customer Groups');
  });

  test('a flat chart is re-grouped — blank parents are back-filled', () async {
    // Simulate a chart seeded before grouping: strip a leaf's parent link.
    final cash = (await engine.fetch('Account', 'Cash'))!;
    cash.payload['parent_account'] = '';
    await engine.save(cash, roles);

    final summary = await repair.repair();
    expect(summary.accountsReparented, greaterThanOrEqualTo(1));
    expect(summary.repairedAnything, isTrue);
    final fixed = await engine.fetch('Account', 'Cash');
    expect(fixed!.payload['parent_account'], 'Assets');
  });

  test('an account the user has already parented is left alone', () async {
    final cash = (await engine.fetch('Account', 'Cash'))!;
    cash.payload['parent_account'] = 'Bank'; // a deliberate custom placement
    await engine.save(cash, roles);

    await repair.repair();
    final after = await engine.fetch('Account', 'Cash');
    expect(after!.payload['parent_account'], 'Bank'); // untouched
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
