import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_hub_app/ledger/hub_interceptors.dart';
import 'package:mercantis_hub_app/ledger/ledger_derivation.dart';
import 'package:mercantis_hub_app/ledger/ledger_derivation_service.dart';
import 'package:mercantis_hub_app/manifest/hub_manifest.dart';
import 'package:mercantis_hub_app/onboarding/hub_seeder.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// H5 (guard fix follow-up): the runtime ledger service must keep service /
/// non-stock items out of the stock ledger entirely. The posting guard skips
/// them, but [LedgerDerivation] emits an SLE for every item line (it can't
/// fetch the Item), so [LedgerDerivationService] is the layer that drops the
/// non-stock rows before they reach a Stock Ledger Entry or a Bin recompute.
void main() {
  setUpAll(sqfliteFfiInit);

  late MercantisDatabase db;
  late DocumentEngine engine;
  late EventEmitter emitter;
  late LedgerDerivationService ledger;
  const roles = {'System Manager'};

  setUp(() async {
    db = await MercantisDatabase.open(
        factory: databaseFactoryFfi, path: inMemoryDatabasePath);
    final registry = MetadataRegistry(db.db);
    final sync = SyncEngine(database: db.db, registry: registry);
    await AppInstaller(database: db.db, registry: registry, syncEngine: sync)
        .install(HubManifest.build());
    emitter = EventEmitter();
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
        LineItemTotalsInterceptor(),
        TaxCalculationInterceptor(),
        BomRollupInterceptor(),
        FiscalYearGuardInterceptor(),
        BooksLockGuardInterceptor(),
        NegativeStockGuardInterceptor(),
      ],
    );
    await HubSeeder(engine, roles: roles).seed(
        businessName: 'Acme', currencyCode: 'EUR', year: DateTime.now().year);
    ledger = LedgerDerivationService(engine: engine, emitter: emitter);
    ledger.start();

    // allow_negative_stock so the stock line clears the guard without seeding a
    // Bin first — we want to assert what the *service* writes, not the guard.
    final co = (await engine.list('Company', userRoles: roles)).first;
    co.payload['allow_negative_stock'] = 1;
    await engine.save(co, roles);

    await engine.save(
        Document(id: 'WH', docType: 'Warehouse',
            payload: {'warehouse_name': 'Main'}),
        roles);
    await engine.save(
        Document(id: 'ITM', docType: 'Item', payload: {
          'item_code': 'ITM',
          'item_name': 'Widget',
          'stock_uom': 'Nos',
        }),
        roles);
    await engine.save(
        Document(id: 'SVC', docType: 'Item', payload: {
          'item_code': 'SVC',
          'item_name': 'Installation',
          'is_stock_item': 0,
          'is_service_item': 1,
        }),
        roles);
    await engine.save(
        Document(id: 'CUST-1', docType: 'Customer', payload: {
          'customer_name': 'Acme Buyer',
          'customer_type': 'Company',
        }),
        roles);
  });

  tearDown(() async {
    ledger.dispose();
    await db.close();
  });

  // The service handles submit events fire-and-forget; poll until the stock
  // item's SLE lands so assertions can't race the derivation.
  Future<List<Document>> awaitSle(String item) async {
    for (var i = 0; i < 80; i++) {
      final rows = await engine.list(LedgerDerivation.stockLedger,
          filters: {'item': item}, userRoles: roles);
      if (rows.isNotEmpty) return rows;
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    return engine.list(LedgerDerivation.stockLedger,
        filters: {'item': item}, userRoles: roles);
  }

  // The Bin is recomputed one async step after the SLE is saved, so poll for it
  // rather than reading it the instant the SLE appears.
  Future<Document?> awaitBin(String id) async {
    for (var i = 0; i < 80; i++) {
      final bin = await engine.fetch(LedgerDerivation.bin, id);
      if (bin != null) return bin;
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    return null;
  }

  test('Delivery Note with a service line: no SLE or Bin for the service item',
      () async {
    final dn = Document(id: '', docType: 'Delivery Note', payload: {
      'customer': 'CUST-1',
      'posting_date': '2026-06-01',
      'set_warehouse': 'WH',
    });
    dn.children['items'] = [
      ChildRow(
        id: '', parentId: '', parentDocType: 'Delivery Note',
        tableName: 'items', rowIndex: 0,
        payload: {'item': 'ITM', 'qty': 2, 'rate': 10},
      ),
      ChildRow(
        id: '', parentId: '', parentDocType: 'Delivery Note',
        tableName: 'items', rowIndex: 1,
        payload: {'item': 'SVC', 'qty': 1, 'rate': 50},
      ),
    ];
    final saved = await engine.save(dn, roles);
    expect((await engine.submit(saved, roles)).docStatus, 1);

    // The stock line posts (proving the service ran)...
    expect(await awaitSle('ITM'), isNotEmpty);
    expect(await awaitBin('BIN-ITM-WH'), isNotNull);

    // ...but the service line leaves no trace in the stock ledger.
    expect(
        await engine.list(LedgerDerivation.stockLedger,
            filters: {'item': 'SVC'}, userRoles: roles),
        isEmpty);
    expect(await engine.fetch(LedgerDerivation.bin, 'BIN-SVC-WH'), isNull);
  });
}
