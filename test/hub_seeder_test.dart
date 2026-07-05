import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_hub_app/manifest/hub_manifest.dart';
import 'package:mercantis_hub_app/onboarding/hub_seeder.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Runs the onboarding seeder against an in-memory engine with the real Hub
/// DocTypes registered, asserting the foundational data + Company wiring and
/// idempotency.
void main() {
  setUpAll(sqfliteFfiInit);

  late MercantisDatabase database;
  late DocumentEngine engine;
  const roles = {'System Manager'};

  setUp(() async {
    database = await MercantisDatabase.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    final registry = MetadataRegistry(database.db);
    engine = DocumentEngine(
      database: database.db,
      registry: registry,
      metaComposer: MetaComposer(registry, database.db),
      permissionEngine: const PermissionEngine(),
      workflowEngine: WorkflowEngine(database.db),
      expressionEvaluator: ExpressionEvaluator(),
      namingService: NamingService(),
      syncEngine: SyncEngine(database: database.db, registry: registry),
      emitter: EventEmitter(),
      deviceId: 'test-device',
      userId: 'test-user',
      interceptors: const [],
    );
    for (final dt in HubManifest.build().docTypes) {
      await registry.register(dt);
    }
  });

  tearDown(() => database.close());

  test('pure helpers', () {
    expect(HubSeeder.fiscalYearBounds(2026), ('2026-01-01', '2026-12-31'));
    expect(HubSeeder.abbreviate('My Business'), 'MB');
    expect(HubSeeder.abbreviate('   '), 'MB');
    expect(HubSeeder.currencySymbol('EUR'), '€');
    expect(HubSeeder.currencyName('USD'), 'US Dollar');
  });

  test('seeds accounts, fiscal year, VAT codes, and a wired company', () async {
    final seeder = HubSeeder(engine, roles: roles);
    expect(await seeder.companyExists(), isFalse);

    await seeder.seed(businessName: 'Acme Ltd', currencyCode: 'eur', year: 2026);

    expect((await engine.fetch('Currency', 'EUR'))!.payload['symbol'], '€');
    expect(await engine.fetch('Warehouse', 'Main Store'), isNotNull);
    final fy = (await engine.fetch('Fiscal Year', 'FY-2026'))!;
    expect(fy.payload['year_start_date'], '2026-01-01');
    expect(fy.payload['year_end_date'], '2026-12-31');

    final accounts = await engine.list('Account', userRoles: roles);
    expect(accounts.length, 15); // 5 root groups + 10 posting accounts
    expect(await engine.fetch('Account', 'Opening Balance Equity'), isNotNull);
    expect(await engine.fetch('Account', 'Retained Earnings'), isNotNull);
    final vat = (await engine.fetch('Account', 'VAT'))!;
    expect(vat.payload['root_type'], 'Liability');
    expect(vat.payload['account_type'], 'Tax');

    // The chart is a two-level tree: a group per root type, leaves parented.
    final assets = (await engine.fetch('Account', 'Assets'))!;
    expect(assets.payload['is_group'], '1');
    expect(assets.payload['parent_account'], anyOf(isNull, ''));
    final bank = (await engine.fetch('Account', 'Bank'))!;
    expect(bank.payload['is_group'], '0');
    expect(bank.payload['parent_account'], 'Assets');
    expect(vat.payload['parent_account'], 'Liabilities');

    // Starter tree masters seed a small hierarchy each (root group + leaves).
    // Ids are namespaced (documents.id is a single global key), so "Services"
    // can appear under both Item Group and Supplier Group without colliding.
    final itemRoot = (await engine.fetch('Item Group', 'IG-All'))!;
    expect(itemRoot.payload['is_group'], '1');
    expect(itemRoot.payload['item_group_name'], 'All Item Groups');
    final products = (await engine.fetch('Item Group', 'IG-Products'))!;
    expect(products.payload['is_group'], '0');
    expect(products.payload['item_group_name'], 'Products');
    expect(products.payload['parent_item_group'], 'IG-All');
    expect(
        (await engine.fetch('Customer Group', 'CG-Retail'))!
            .payload['parent_customer_group'],
        'CG-All');
    expect((await engine.fetch('Cost Center', 'CC-Operations'))!
        .payload['parent_cost_center'], 'CC-Main');
    // "Services" exists under two masters, keyed by distinct ids.
    expect((await engine.fetch('Item Group', 'IG-Services'))!
        .payload['item_group_name'], 'Services');
    expect((await engine.fetch('Supplier Group', 'SG-Services'))!
        .payload['supplier_group_name'], 'Services');

    final codes = await engine.list('Tax Code', userRoles: roles);
    expect(codes.length, 5);
    final std = (await engine.fetch('Tax Code', 'VAT 18%'))!;
    expect(std.payload['rate'], 18);
    expect(std.payload['tax_account'], 'VAT');
    expect(std.payload['is_default'], '1');

    final company = (await engine.list('Company', userRoles: roles)).single;
    expect(company.payload['company_name'], 'Acme Ltd');
    expect(company.payload['abbr'], 'AL');
    expect(company.payload['default_currency'], 'EUR');
    expect(company.payload['default_receivable_account'], 'Debtors');
    expect(company.payload['default_income_account'], 'Sales');
    expect(company.payload['default_payable_account'], 'Creditors');
    expect(company.payload['default_expense_account'], 'COGS');
    expect(company.payload['default_cash_account'], 'Bank');
    expect(company.payload['default_vat_account'], 'VAT');
  });

  test('is idempotent — re-running creates nothing new', () async {
    final seeder = HubSeeder(engine, roles: roles);
    await seeder.seed(businessName: 'Acme', currencyCode: 'EUR', year: 2026);
    final second = await seeder.seed(businessName: 'Acme', currencyCode: 'EUR', year: 2026);

    expect(second.created, 0);
    expect((await engine.list('Company', userRoles: roles)).length, 1);
    expect((await engine.list('Account', userRoles: roles)).length, 15);
    expect((await engine.list('Tax Code', userRoles: roles)).length, 5);
    expect(await seeder.companyExists(), isTrue);
  });

  group('jurisdiction templates (H9)', () {
    test('byId resolves known regions and falls back to Malta', () {
      expect(JurisdictionPreset.byId('GB'), JurisdictionPreset.unitedKingdom);
      expect(JurisdictionPreset.byId('IE'), JurisdictionPreset.ireland);
      expect(JurisdictionPreset.byId(null), JurisdictionPreset.malta);
      expect(JurisdictionPreset.byId('ZZ'), JurisdictionPreset.malta);
    });

    test('the default seed is still Malta (18% standard)', () async {
      await HubSeeder(engine, roles: roles)
          .seed(businessName: 'Acme', currencyCode: 'EUR', year: 2026);
      final codes = await engine.list('Tax Code', userRoles: roles);
      expect(codes.length, 5);
      expect((await engine.fetch('Tax Code', 'VAT 18%'))!.payload['is_default'],
          '1');
    });

    test('a UK seed lays down the UK VAT bands, not Malta', () async {
      await HubSeeder(engine, roles: roles).seed(
        businessName: 'Acme',
        currencyCode: 'GBP',
        year: 2026,
        jurisdiction: JurisdictionPreset.unitedKingdom,
      );
      final codes = await engine.list('Tax Code', userRoles: roles);
      expect(codes.map((c) => c.id), containsAll(['VAT 20%', 'VAT 5%']));
      expect(await engine.fetch('Tax Code', 'VAT 18%'), isNull); // not Malta
      final std = (await engine.fetch('Tax Code', 'VAT 20%'))!;
      expect(std.payload['rate'], 20);
      expect(std.payload['is_default'], '1');
    });

    test('a second jurisdiction re-seed is additive (adaptive re-run)', () async {
      final seeder = HubSeeder(engine, roles: roles);
      await seeder.seed(
          businessName: 'Acme', currencyCode: 'EUR', year: 2026);
      await seeder.seed(
        businessName: 'Acme',
        currencyCode: 'EUR',
        year: 2026,
        jurisdiction: JurisdictionPreset.ireland,
      );
      final codes = await engine.list('Tax Code', userRoles: roles);
      // Malta's 5 + Ireland's new bands (23/13.5/9; Zero-Rated & Exempt shared).
      expect(codes.map((c) => c.id), containsAll(['VAT 18%', 'VAT 23%', 'VAT 9%']));
    });

    test('a region switch re-bases the company currency + sole default code',
        () async {
      final seeder = HubSeeder(engine, roles: roles);
      await seeder.seed(
          businessName: 'Acme', currencyCode: 'EUR', year: 2026);
      expect((await engine.list('Company', userRoles: roles)).first
          .payload['default_currency'], 'EUR');

      // Re-run picking the UK (GBP, VAT 20% default).
      await seeder.seed(
        businessName: 'Acme',
        currencyCode: 'GBP',
        year: 2026,
        jurisdiction: JurisdictionPreset.unitedKingdom,
      );

      expect((await engine.list('Company', userRoles: roles)).first
          .payload['default_currency'], 'GBP');
      // Exactly one default tax code, and it's the UK standard band.
      final defaults = (await engine.list('Tax Code', userRoles: roles))
          .where((c) => '${c.payload['is_default']}' == '1')
          .map((c) => c.id)
          .toList();
      expect(defaults, ['VAT 20%']);
    });
  });
}
