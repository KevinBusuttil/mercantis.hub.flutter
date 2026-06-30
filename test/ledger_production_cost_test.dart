import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_hub_app/ledger/hub_interceptors.dart';
import 'package:mercantis_hub_app/ledger/ledger_derivation.dart';
import 'package:mercantis_hub_app/ledger/ledger_derivation_service.dart';
import 'package:mercantis_hub_app/ledger/ledger_values.dart';
import 'package:mercantis_hub_app/manifest/hub_manifest.dart';
import 'package:mercantis_hub_app/onboarding/hub_seeder.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// H5 valuation: a Manufacture Stock Entry posts the produced good into stock at
/// *production cost* — the raw material it consumed, spread over the qty made —
/// rather than at a zero/blank rate.
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

    for (final wh in const ['RAW', 'FG']) {
      await engine.save(
          Document(id: wh, docType: 'Warehouse',
              payload: {'warehouse_name': wh}),
          roles);
    }
    for (final code in const ['STEEL', 'BOLT', 'WIDGET']) {
      await engine.save(
          Document(id: code, docType: 'Item', payload: {
            'item_code': code, 'item_name': code, 'stock_uom': 'Nos',
          }),
          roles);
    }
    // Raw stock on hand in RAW: STEEL 100 @ 5, BOLT 100 @ 1.
    await _seed(engine, roles, 'STEEL', qty: 100, rate: 5);
    await _seed(engine, roles, 'BOLT', qty: 100, rate: 1);
  });

  tearDown(() async {
    ledger.dispose();
    await db.close();
  });

  Future<Document?> finishedSle(String voucherNo) async {
    for (var i = 0; i < 80; i++) {
      final rows = await engine.list(LedgerDerivation.stockLedger,
          filters: {'voucher_no': voucherNo, 'item': 'WIDGET'},
          userRoles: roles);
      final made = rows.where((r) => asNum(r.payload['qty_change']) > 0);
      if (made.isNotEmpty) return made.first;
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    return null;
  }

  test('produced good enters stock at rolled-up raw-material cost', () async {
    // Consume 10 STEEL (@5=50) + 20 BOLT (@1=20) → 70 of raw to make 5 WIDGET.
    final se = Document(id: '', docType: 'Stock Entry', payload: {
      'stock_entry_type': 'Manufacture',
      'posting_date': '2026-06-02',
    });
    se.children['items'] = [
      ChildRow(id: '', parentId: '', parentDocType: 'Stock Entry',
          tableName: 'items', rowIndex: 0,
          payload: {'item': 'STEEL', 'qty': 10, 'source_warehouse': 'RAW'}),
      ChildRow(id: '', parentId: '', parentDocType: 'Stock Entry',
          tableName: 'items', rowIndex: 1,
          payload: {'item': 'BOLT', 'qty': 20, 'source_warehouse': 'RAW'}),
      ChildRow(id: '', parentId: '', parentDocType: 'Stock Entry',
          tableName: 'items', rowIndex: 2,
          payload: {'item': 'WIDGET', 'qty': 5, 'target_warehouse': 'FG'}),
    ];
    final posted = await engine.submit(await engine.save(se, roles), roles);

    final sle = await finishedSle(posted.id);
    expect(sle, isNotNull);
    expect(asNum(sle!.payload['qty_change']), 5);
    expect(asNum(sle.payload['valuation_rate']), 14); // (50 + 20) / 5

    // The Bin is recomputed one async step after the SLE, so poll for it.
    Document? bin;
    for (var i = 0; i < 80; i++) {
      bin = await engine.fetch(LedgerDerivation.bin, 'BIN-WIDGET-FG');
      if (bin != null) break;
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    expect(bin, isNotNull);
    expect(asNum(bin!.payload['stock_value']), 70);
  });

  test('multi-output entry allocates consumed cost across outputs (no value '
      'creation)', () async {
    await engine.save(
        Document(id: 'GADGET', docType: 'Item', payload: {
          'item_code': 'GADGET', 'item_name': 'GADGET', 'stock_uom': 'Nos',
        }),
        roles);
    // Consume 70 of raw to make 5 WIDGET + 5 GADGET → 10 units total.
    final se = Document(id: '', docType: 'Stock Entry', payload: {
      'stock_entry_type': 'Manufacture',
      'posting_date': '2026-06-02',
    });
    se.children['items'] = [
      ChildRow(id: '', parentId: '', parentDocType: 'Stock Entry',
          tableName: 'items', rowIndex: 0,
          payload: {'item': 'STEEL', 'qty': 10, 'source_warehouse': 'RAW'}),
      ChildRow(id: '', parentId: '', parentDocType: 'Stock Entry',
          tableName: 'items', rowIndex: 1,
          payload: {'item': 'BOLT', 'qty': 20, 'source_warehouse': 'RAW'}),
      ChildRow(id: '', parentId: '', parentDocType: 'Stock Entry',
          tableName: 'items', rowIndex: 2,
          payload: {'item': 'WIDGET', 'qty': 5, 'target_warehouse': 'FG'}),
      ChildRow(id: '', parentId: '', parentDocType: 'Stock Entry',
          tableName: 'items', rowIndex: 3,
          payload: {'item': 'GADGET', 'qty': 5, 'target_warehouse': 'FG'}),
    ];
    final posted = await engine.submit(await engine.save(se, roles), roles);

    // Each output is valued at 70 / 10 = 7, so total output value is 70 — the
    // consumed cost — not 70 per row.
    Document? widget;
    for (var i = 0; i < 80; i++) {
      final rows = await engine.list(LedgerDerivation.stockLedger,
          filters: {'voucher_no': posted.id, 'item': 'GADGET'},
          userRoles: roles);
      if (rows.isNotEmpty) {
        widget = rows.first;
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    expect(widget, isNotNull);
    expect(asNum(widget!.payload['valuation_rate']), 7); // 70 / (5 + 5)
  });
}

Future<void> _seed(
  DocumentEngine engine,
  Set<String> roles,
  String item, {
  required num qty,
  required num rate,
}) =>
    engine.save(
      Document(id: 'SLE-seed-$item', docType: 'Stock Ledger Entry', payload: {
        'trans_type': 'Receipt', 'item': item, 'warehouse': 'RAW',
        'posting_date': '2026-05-01', 'voucher_type': 'Stock Entry',
        'voucher_no': 'SEED-$item', 'qty_change': qty, 'valuation_rate': rate,
        'is_reversal': false,
      }),
      roles,
    );
