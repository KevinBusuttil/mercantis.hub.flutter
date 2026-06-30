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
/// stock UOM, value-preserving — qty × factor, receipt rate ÷ factor — so the
/// stock ledger always records stock units and total value is unchanged.
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
    await engine.save(
        Document(id: 'CUST-1', docType: 'Customer', payload: {
          'customer_name': 'Acme Buyer',
          'customer_type': 'Company',
        }),
        roles);
    // 1 Box = 12 Nos (the stock UOM). UOM is a select, so the conversion row's
    // value matches the literal UOM the transaction lines carry.
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

  // Poll the stock ledger for the voucher's row matching [wantPositive] sign.
  Future<Document?> sleFor(String voucherNo, {required bool wantPositive}) async {
    for (var i = 0; i < 80; i++) {
      final rows = await engine.list(LedgerDerivation.stockLedger,
          filters: {'voucher_no': voucherNo}, userRoles: roles);
      final match = rows.where((r) =>
          wantPositive == (asNum(r.payload['qty_change']) > 0) &&
          asNum(r.payload['qty_change']) != 0);
      if (match.isNotEmpty) return match.first;
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    return null;
  }

  test('a receipt in Box records stock Nos at rate ÷ factor', () async {
    // Receive 2 Box @ 120/Box → 24 Nos @ 10/Nos (value preserved at 240).
    final se = Document(id: '', docType: 'Stock Entry', payload: {
      'stock_entry_type': 'Material Receipt',
      'posting_date': '2026-06-01',
    });
    se.children['items'] = [
      ChildRow(
        id: '', parentId: '', parentDocType: 'Stock Entry',
        tableName: 'items', rowIndex: 0,
        payload: {
          'item': 'BOXED', 'uom': 'Box', 'qty': 2,
          'target_warehouse': 'WH', 'valuation_rate': 120,
        },
      ),
    ];
    final posted = await engine.submit(await engine.save(se, roles), roles);

    final sle = await sleFor(posted.id, wantPositive: true);
    expect(sle, isNotNull);
    expect(asNum(sle!.payload['qty_change']), 24); // 2 Box × 12
    expect(asNum(sle.payload['valuation_rate']), 10); // 120 ÷ 12
  });

  test('an issue in Box draws down stock Nos at cost', () async {
    // Stock on hand: 100 Nos @ 10 (already in stock units).
    await engine.save(
        Document(id: 'SLE-seed', docType: 'Stock Ledger Entry', payload: {
          'trans_type': 'Receipt', 'item': 'BOXED', 'warehouse': 'WH',
          'posting_date': '2026-05-01', 'voucher_type': 'Stock Entry',
          'voucher_no': 'SEED', 'qty_change': 100, 'valuation_rate': 10,
          'is_reversal': false,
        }),
        roles);

    // Deliver 1 Box → 12 Nos out, costed at the moving average (10).
    final dn = Document(id: '', docType: 'Delivery Note', payload: {
      'customer': 'CUST-1',
      'posting_date': '2026-06-01',
      'set_warehouse': 'WH',
    });
    dn.children['items'] = [
      ChildRow(
        id: '', parentId: '', parentDocType: 'Delivery Note',
        tableName: 'items', rowIndex: 0,
        payload: {'item': 'BOXED', 'uom': 'Box', 'qty': 1, 'rate': 99},
      ),
    ];
    final posted = await engine.submit(await engine.save(dn, roles), roles);

    final sle = await sleFor(posted.id, wantPositive: false);
    expect(sle, isNotNull);
    expect(asNum(sle!.payload['qty_change']), -12); // 1 Box × 12, leaving
    expect(asNum(sle.payload['valuation_rate']), 10); // cost, not the 99 rate
  });
}
