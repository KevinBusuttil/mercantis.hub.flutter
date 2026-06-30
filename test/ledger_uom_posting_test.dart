import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_hub_app/ledger/hub_interceptors.dart';
import 'package:mercantis_hub_app/ledger/ledger_derivation.dart';
import 'package:mercantis_hub_app/ledger/ledger_derivation_service.dart';
import 'package:mercantis_hub_app/ledger/ledger_values.dart';
import 'package:mercantis_hub_app/manifest/hub_manifest.dart';
import 'package:mercantis_hub_app/onboarding/hub_seeder.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// H5 valuation: stock posting converts a line's transaction UOM to the item's
/// stock UOM, value-preserving — qty × factor, rate ÷ factor — so the Bin
/// always tracks stock units and total stock value is unchanged by the unit.
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

    final co = (await engine.list('Company', userRoles: roles)).first;
    co.payload['allow_negative_stock'] = 1;
    await engine.save(co, roles);

    await engine.save(
        Document(id: 'WH', docType: 'Warehouse',
            payload: {'warehouse_name': 'Main'}),
        roles);
    // 1 Box = 12 Nos (stock UOM).
    final item = Document(id: 'BOXED', docType: 'Item', payload: {
      'item_code': 'BOXED',
      'item_name': 'Boxed widget',
      'stock_uom': 'Nos',
      'valuation_method': 'Moving Average',
    });
    item.children['uoms'] = [
      ChildRow(
        id: '', parentId: 'BOXED', parentDocType: 'Item',
        tableName: 'uoms', rowIndex: 0,
        payload: {'uom': 'Box', 'conversion_factor': 12},
      ),
    ];
    await engine.save(item, roles);
  });

  tearDown(() async {
    ledger.dispose();
    await db.close();
  });

  Future<Document> stockEntry(String type, Map<String, dynamic> line) async {
    final se = Document(id: '', docType: 'Stock Entry', payload: {
      'stock_entry_type': type,
      'posting_date': '2026-06-01',
    });
    se.children['items'] = [
      ChildRow(
        id: '', parentId: '', parentDocType: 'Stock Entry',
        tableName: 'items', rowIndex: 0, payload: line,
      ),
    ];
    return engine.submit(await engine.save(se, roles), roles);
  }

  Future<Document?> awaitBin() async {
    for (var i = 0; i < 80; i++) {
      final bin = await engine.fetch(LedgerDerivation.bin, 'BIN-BOXED-WH');
      if (bin != null) return bin;
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    return null;
  }

  test('a receipt in Box converts to stock Nos, preserving value', () async {
    // Receive 2 Box @ 120/Box → 24 Nos @ 10/Nos, value 240.
    await stockEntry('Material Receipt', {
      'item': 'BOXED', 'uom': 'Box', 'qty': 2,
      'target_warehouse': 'WH', 'valuation_rate': 120,
    });
    Document? bin;
    for (var i = 0; i < 80; i++) {
      bin = await awaitBin();
      if (bin != null && asNum(bin.payload['actual_qty']) == 24) break;
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    expect(asNum(bin!.payload['actual_qty']), 24);
    expect(asNum(bin.payload['valuation_rate']), 10);
    expect(asNum(bin.payload['stock_value']), 240);
  });

  test('an issue in Box draws down stock Nos at cost', () async {
    await stockEntry('Material Receipt', {
      'item': 'BOXED', 'uom': 'Box', 'qty': 2,
      'target_warehouse': 'WH', 'valuation_rate': 120,
    });
    // Wait for the receipt to settle the bin at 24 Nos before issuing.
    for (var i = 0; i < 80; i++) {
      final b = await engine.fetch(LedgerDerivation.bin, 'BIN-BOXED-WH');
      if (b != null && asNum(b.payload['actual_qty']) == 24) break;
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }

    // Issue 1 Box → 12 Nos out at cost 10, leaving 12 Nos worth 120.
    await stockEntry('Material Issue', {
      'item': 'BOXED', 'uom': 'Box', 'qty': 1, 'source_warehouse': 'WH',
    });
    Document? bin;
    for (var i = 0; i < 80; i++) {
      bin = await engine.fetch(LedgerDerivation.bin, 'BIN-BOXED-WH');
      if (bin != null && asNum(bin.payload['actual_qty']) == 12) break;
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    expect(asNum(bin!.payload['actual_qty']), 12);
    expect(asNum(bin.payload['valuation_rate']), 10);
    expect(asNum(bin.payload['stock_value']), 120);
  });
}
