import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_hub_app/manifest/hub_manifest.dart';
import 'package:mercantis_hub_app/onboarding/business_preset.dart';
import 'package:mercantis_hub_app/onboarding/hub_seeder.dart';
import 'package:mercantis_hub_app/onboarding/setup_checklist.dart';
import 'package:mercantis_hub_app/settings/hub_settings.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The setup checklist computes its statuses live from the document store:
/// a freshly-seeded company is not invoice-ready until it has a customer and
/// an item; conditional steps follow the module toggles.
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
    );
    await HubSeeder(engine, roles: roles).seed(
        businessName: 'Acme', currencyCode: 'EUR', year: DateTime.now().year);
  });

  tearDown(() async => db.close());

  SetupChecklistItem item(SetupChecklist list, String id) =>
      list.items.firstWhere((i) => i.id == id);

  test('fresh seed: foundations done, masters todo, not invoice-ready',
      () async {
    final settings =
        const HubSettings().applyingPreset(BusinessPreset.services);
    final list = await buildSetupChecklist(engine, settings, roles: roles);

    expect(item(list, 'company').status, SetupItemStatus.done);
    expect(item(list, 'tax').status, SetupItemStatus.done);
    expect(item(list, 'fiscal_year').status, SetupItemStatus.done);
    expect(item(list, 'customers').status, SetupItemStatus.todo);
    expect(item(list, 'items').status, SetupItemStatus.todo);
    expect(item(list, 'branding').status, SetupItemStatus.todo);
    // Services preset: stock & POS steps don't apply.
    expect(item(list, 'stock').status, SetupItemStatus.notApplicable);
    expect(item(list, 'pos').status, SetupItemStatus.notApplicable);

    expect(list.readyToInvoice, isFalse);
    expect(list.missingForInvoicing.map((i) => i.id),
        containsAll(['customers', 'items']));
  });

  test('adding a customer and an item makes the business invoice-ready',
      () async {
    final settings =
        const HubSettings().applyingPreset(BusinessPreset.services);
    await engine.save(
        Document(id: 'CUST-1', docType: 'Customer', payload: {
          'customer_name': 'Acme Buyer',
          'customer_type': 'Company',
        }),
        roles);
    await engine.save(
        Document(id: 'SVC-1', docType: 'Item', payload: {
          'item_code': 'SVC-1',
          'item_name': 'Consulting hour',
          'item_type': 'Service',
          'stock_uom': 'Hour',
        }),
        roles);

    final list = await buildSetupChecklist(engine, settings, roles: roles);
    expect(item(list, 'customers').status, SetupItemStatus.done);
    expect(item(list, 'items').status, SetupItemStatus.done);
    expect(list.readyToInvoice, isTrue);
  });

  test('retail preset: stock step tracks stock items, POS tracks profiles',
      () async {
    final settings = const HubSettings().applyingPreset(BusinessPreset.retail);

    var list = await buildSetupChecklist(engine, settings, roles: roles);
    expect(item(list, 'stock').status, SetupItemStatus.todo);
    expect(item(list, 'pos').status, SetupItemStatus.todo);

    await engine.save(
        Document(id: 'ITM-1', docType: 'Item', payload: {
          'item_code': 'ITM-1',
          'item_name': 'Widget',
          'item_type': 'Stock',
          'stock_uom': 'Nos',
        }),
        roles);
    await engine.save(
        Document(id: 'POS-1', docType: 'POS Profile', payload: {
          'profile_name': 'Front till',
        }),
        roles);

    list = await buildSetupChecklist(engine, settings, roles: roles);
    expect(item(list, 'stock').status, SetupItemStatus.done);
    expect(item(list, 'pos').status, SetupItemStatus.done);
  });

  test('first document and opening balances flip when documents exist',
      () async {
    final settings =
        const HubSettings().applyingPreset(BusinessPreset.services);
    await engine.save(
        Document(id: 'CUST-1', docType: 'Customer', payload: {
          'customer_name': 'Acme Buyer',
          'customer_type': 'Company',
        }),
        roles);
    await engine.save(
        Document(id: '', docType: 'Quotation', payload: {
          'customer': 'CUST-1',
          'transaction_date':
              DateTime.now().toIso8601String().split('T').first,
        }),
        roles);
    await engine.save(
        Document(id: '', docType: 'Journal Entry', payload: {
          'voucher_type': 'Opening Entry',
          'posting_date':
              DateTime.now().toIso8601String().split('T').first,
        }),
        roles);

    final list = await buildSetupChecklist(engine, settings, roles: roles);
    expect(item(list, 'first_document').status, SetupItemStatus.done);
    expect(item(list, 'opening_balances').status, SetupItemStatus.done);
  });
}
