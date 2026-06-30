import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_hub_app/ledger/hub_interceptors.dart';
import 'package:mercantis_hub_app/ledger/ledger_derivation.dart';
import 'package:mercantis_hub_app/ledger/ledger_derivation_service.dart';
import 'package:mercantis_hub_app/ledger/ledger_values.dart';
import 'package:mercantis_hub_app/manifest/hub_manifest.dart';
import 'package:mercantis_hub_app/onboarding/hub_seeder.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// H5 valuation: the runtime service costs a stock issue at the item's
/// valuation-method cost (moving average / FIFO), never at the line's selling
/// rate, and a cancel reuses the original cost so it backs out exactly.
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

    // Decouple the test from the guard's Bin-timing: we assert what the costing
    // pass writes, not whether the issue is in stock.
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
    for (final m in const ['Moving Average', 'FIFO']) {
      final id = m == 'FIFO' ? 'FIFO' : 'MA';
      await engine.save(
          Document(id: id, docType: 'Item', payload: {
            'item_code': id,
            'item_name': id,
            'stock_uom': 'Nos',
            'valuation_method': m,
          }),
          roles);
      // Two receipt layers: 10 @ 10 (older), then 10 @ 20.
      await _seedReceipt(engine, roles, id, qty: 10, rate: 10, date: '2026-06-01');
      await _seedReceipt(engine, roles, id, qty: 10, rate: 20, date: '2026-06-02');
    }
  });

  tearDown(() async {
    ledger.dispose();
    await db.close();
  });

  Future<Document?> issueSle(String voucherNo) async {
    for (var i = 0; i < 80; i++) {
      final rows = await engine.list(LedgerDerivation.stockLedger,
          filters: {'voucher_no': voucherNo}, userRoles: roles);
      final issue = rows.where((r) => asNum(r.payload['qty_change']) < 0);
      if (issue.isNotEmpty) return issue.first;
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    return null;
  }

  Future<Document> deliver(String item, num qty) async {
    final dn = Document(id: '', docType: 'Delivery Note', payload: {
      'customer': 'CUST-1',
      'posting_date': '2026-06-10',
      'set_warehouse': 'WH',
    });
    dn.children['items'] = [
      ChildRow(
        id: '', parentId: '', parentDocType: 'Delivery Note',
        tableName: 'items', rowIndex: 0,
        payload: {'item': item, 'qty': qty, 'rate': 99}, // selling rate, ignored
      ),
    ];
    return engine.submit(await engine.save(dn, roles), roles);
  }

  test('a moving-average issue is costed at the running average', () async {
    final dn = await deliver('MA', 5);
    final sle = await issueSle(dn.id);
    expect(sle, isNotNull);
    expect(asNum(sle!.payload['valuation_rate']), 15); // not 99
  });

  test('a FIFO issue is costed at the oldest layer', () async {
    final dn = await deliver('FIFO', 5);
    final sle = await issueSle(dn.id);
    expect(sle, isNotNull);
    expect(asNum(sle!.payload['valuation_rate']), 10); // oldest layer, not 99
  });

  test('FIFO breaks same-day ties by creation order (oldest layer first)',
      () async {
    await engine.save(
        Document(id: 'FIFO2', docType: 'Item', payload: {
          'item_code': 'FIFO2',
          'item_name': 'FIFO2',
          'stock_uom': 'Nos',
          'valuation_method': 'FIFO',
        }),
        roles);
    // Two receipts on the SAME posting date; the 10-cost layer is saved first
    // and gets the lexically-smaller id, so it must be consumed first.
    await _seedReceiptId(engine, roles, 'FIFO2', 'SLE-seed-FIFO2-a',
        qty: 10, rate: 10, date: '2026-06-05');
    await _seedReceiptId(engine, roles, 'FIFO2', 'SLE-seed-FIFO2-b',
        qty: 10, rate: 20, date: '2026-06-05');

    final dn = await deliver('FIFO2', 5);
    final sle = await issueSle(dn.id);
    expect(sle, isNotNull);
    expect(asNum(sle!.payload['valuation_rate']), 10); // oldest same-day layer
  });

  test('a cancel reuses the original issue cost', () async {
    final dn = await deliver('MA', 5);
    final original = await issueSle(dn.id);
    expect(asNum(original!.payload['valuation_rate']), 15);

    await engine.cancel(
        (await engine.fetch('Delivery Note', dn.id))!, roles);

    Document? reversal;
    for (var i = 0; i < 80; i++) {
      reversal = await engine.fetch(
          LedgerDerivation.stockLedger, '${original.id}-reversal');
      if (reversal != null) break;
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    expect(reversal, isNotNull);
    expect(asNum(reversal!.payload['valuation_rate']), 15); // reused, not re-costed
    expect(asNum(reversal.payload['qty_change']), 5); // restores the issued qty
  });
}

Future<void> _seedReceipt(
  DocumentEngine engine,
  Set<String> roles,
  String item, {
  required num qty,
  required num rate,
  required String date,
}) =>
    _seedReceiptId(engine, roles, item, 'SLE-seed-$item-$date',
        qty: qty, rate: rate, date: date);

Future<void> _seedReceiptId(
  DocumentEngine engine,
  Set<String> roles,
  String item,
  String id, {
  required num qty,
  required num rate,
  required String date,
}) =>
    engine.save(
      Document(id: id, docType: 'Stock Ledger Entry',
          payload: {
            'trans_type': 'Receipt',
            'item': item,
            'warehouse': 'WH',
            'posting_date': date,
            'voucher_type': 'Stock Entry',
            'voucher_no': 'SEED-$item-$date',
            'qty_change': qty,
            'valuation_rate': rate,
            'is_reversal': false,
          }),
      roles,
    );
