import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_hub_app/ledger/hub_interceptors.dart';
import 'package:mercantis_hub_app/ledger/ledger_derivation.dart';
import 'package:mercantis_hub_app/ledger/ledger_derivation_service.dart';
import 'package:mercantis_hub_app/ledger/ledger_values.dart';
import 'package:mercantis_hub_app/manifest/hub_manifest.dart';
import 'package:mercantis_hub_app/onboarding/hub_seeder.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// H6 stock returns: a sales return (Delivery Note with is_return) adds the
/// goods back to stock at the cost they were sold at — read from the original
/// delivery via return_against — never at the line's selling rate.
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
        Document(id: 'ITM', docType: 'Item', payload: {
          'item_code': 'ITM', 'item_name': 'Widget', 'stock_uom': 'Nos',
        }),
        roles);
    await engine.save(
        Document(id: 'CUST-1', docType: 'Customer', payload: {
          'customer_name': 'Acme Buyer', 'customer_type': 'Company',
        }),
        roles);
    // On hand: 100 @ 10 (cost).
    await engine.save(
        Document(id: 'SLE-seed', docType: 'Stock Ledger Entry', payload: {
          'trans_type': 'Receipt', 'item': 'ITM', 'warehouse': 'WH',
          'posting_date': '2026-05-01', 'voucher_type': 'Stock Entry',
          'voucher_no': 'SEED', 'qty_change': 100, 'valuation_rate': 10,
          'is_reversal': false,
        }),
        roles);
  });

  tearDown(() async {
    ledger.dispose();
    await db.close();
  });

  Future<Document?> sle(String voucherNo, {required bool positive}) async {
    for (var i = 0; i < 80; i++) {
      final rows = await engine.list(LedgerDerivation.stockLedger,
          filters: {'voucher_no': voucherNo}, userRoles: roles);
      final match = rows.where((r) =>
          positive == (asNum(r.payload['qty_change']) > 0) &&
          asNum(r.payload['qty_change']) != 0);
      if (match.isNotEmpty) return match.first;
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    return null;
  }

  test('a sales return restocks at the original sale cost, not the sell rate',
      () async {
    // Original sale: deliver 5 at sell rate 99 → issued at cost 10.
    final dn = Document(id: '', docType: 'Delivery Note', payload: {
      'customer': 'CUST-1', 'posting_date': '2026-06-01', 'set_warehouse': 'WH',
    });
    dn.children['items'] = [
      ChildRow(id: '', parentId: '', parentDocType: 'Delivery Note',
          tableName: 'items', rowIndex: 0,
          payload: {'item': 'ITM', 'qty': 5, 'rate': 99}),
    ];
    final orig = await engine.submit(await engine.save(dn, roles), roles);
    final issued = await sle(orig.id, positive: false);
    expect(issued, isNotNull);
    expect(asNum(issued!.payload['valuation_rate']), 10); // costed, not 99

    // Return: a Delivery Note with is_return + return_against and negative qty.
    final ret = Document(id: '', docType: 'Delivery Note', payload: {
      'customer': 'CUST-1', 'posting_date': '2026-06-05', 'set_warehouse': 'WH',
      'is_return': 1, 'return_against': orig.id,
    });
    ret.children['items'] = [
      ChildRow(id: '', parentId: '', parentDocType: 'Delivery Note',
          tableName: 'items', rowIndex: 0,
          payload: {'item': 'ITM', 'qty': -5, 'rate': 99}),
    ];
    final posted = await engine.submit(await engine.save(ret, roles), roles);

    final back = await sle(posted.id, positive: true);
    expect(back, isNotNull);
    expect(asNum(back!.payload['qty_change']), 5); // stock added back
    expect(asNum(back.payload['valuation_rate']), 10); // original cost, not 99
  });
}
