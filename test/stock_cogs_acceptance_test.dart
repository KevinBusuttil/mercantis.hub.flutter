import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_hub_app/ledger/hub_interceptors.dart';
import 'package:mercantis_hub_app/ledger/ledger_derivation.dart';
import 'package:mercantis_hub_app/ledger/ledger_derivation_service.dart';
import 'package:mercantis_hub_app/ledger/ledger_values.dart';
import 'package:mercantis_hub_app/manifest/hub_manifest.dart';
import 'package:mercantis_hub_app/onboarding/hub_seeder.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The MANDATORY perpetual-inventory acceptance test (fixture #1 of
/// docs/STOCK_COGS_IMPLEMENTATION_PLAN.md §5):
///
///   1. Buy 10 × Item A @ €5           → qty 10, Bin value €50, GL Inventory €50
///   2. Sell 3 @ €12 (VAT-exclusive)   → qty 7,  Bin value €35, Revenue €36,
///                                       COGS €15, GL Inventory €35
///   3. Service-item sale              → no SLE, no inventory/COGS movement
///   4. Cancel the sale                → GL + stock fully reversed
///   5. Sales return                   → inventory back at cost, COGS reversed
///
/// The stock ledger must reconcile to the GL inventory account at every step.
void main() {
  setUpAll(sqfliteFfiInit);

  late MercantisDatabase db;
  late DocumentEngine engine;
  late EventEmitter emitter;
  late LedgerDerivationService ledger;
  const roles = {'System Manager'};
  final today = DateTime.now().toIso8601String().split('T').first;

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
        FiscalYearGuardInterceptor(),
        NegativeStockGuardInterceptor(),
        GroupAccountPostingGuardInterceptor(),
        JournalBalanceGuardInterceptor(),
      ],
    );
    await HubSeeder(engine, roles: roles).seed(
        businessName: 'Acme', currencyCode: 'EUR', year: DateTime.now().year);
    // onError stays silent: a disposed test's in-flight handler may touch the
    // closed DB during teardown; failing here would poison the next test. The
    // `until(...)` polls make a genuinely missing posting fail loudly anyway.
    ledger = LedgerDerivationService(engine: engine, emitter: emitter);
    ledger.start();

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
    await engine.save(
        Document(id: 'SUPP-1', docType: 'Supplier', payload: {
          'supplier_name': 'Apex Supplies',
          'supplier_type': 'Company',
        }),
        roles);
    await engine.save(
        Document(id: 'ITEM-A', docType: 'Item', payload: {
          'item_code': 'ITEM-A',
          'item_name': 'Item A',
          'item_type': 'Stock',
          'stock_uom': 'Nos',
          'valuation_method': 'Moving Average',
        }),
        roles);
    await engine.save(
        Document(id: 'SVC-1', docType: 'Item', payload: {
          'item_code': 'SVC-1',
          'item_name': 'Consulting',
          'item_type': 'Service',
          'stock_uom': 'Hour',
        }),
        roles);
  });

  tearDown(() async {
    ledger.dispose();
    await db.close();
  });

  ChildRow line(String parentType, Map<String, dynamic> payload,
          [int index = 0]) =>
      ChildRow(
        id: '', parentId: '', parentDocType: parentType,
        tableName: 'items', rowIndex: index,
        payload: payload,
      );

  // The derivation runs on unawaited submit/cancel events (same pattern as
  // ledger_valuation_test): poll until the condition holds.
  Future<void> until(Future<bool> Function() cond) async {
    for (var i = 0; i < 80; i++) {
      if (await cond()) return;
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    fail('derivation did not settle');
  }

  Future<int> glCount(String voucherNo) async => (await engine.list('GL Entry',
          filters: {'voucher_no': voucherNo}, userRoles: roles))
      .length;

  Future<Document?> bin() => engine.fetch('Bin', 'BIN-ITEM-A-WH');

  Future<Document> buy10At5() async {
    final pi = Document(id: '', docType: 'Purchase Invoice', payload: {
      'supplier': 'SUPP-1',
      'posting_date': today,
      'update_stock': 1,
      'set_warehouse': 'WH',
    });
    pi.children['items'] = [
      line('Purchase Invoice', {'item': 'ITEM-A', 'qty': 10, 'rate': 5}),
    ];
    final doc = await engine.submit(await engine.save(pi, roles), roles);
    // AP + GRNI split + the Dr Inventory / Cr GRNI pair, and the Bin updated.
    await until(() async =>
        await glCount(doc.id) >= 4 &&
        asNum((await bin())?.payload['actual_qty'] ?? -1) == 10);
    return doc;
  }

  Future<Document> sell3At12() async {
    final si = Document(id: '', docType: 'Sales Invoice', payload: {
      'customer': 'CUST-1',
      'posting_date': today,
      'update_stock': 1,
      'set_warehouse': 'WH',
    });
    si.children['items'] = [
      line('Sales Invoice', {'item': 'ITEM-A', 'qty': 3, 'rate': 12}),
    ];
    final doc = await engine.submit(await engine.save(si, roles), roles);
    // AR + revenue + the Dr COGS / Cr Inventory pair, and the Bin updated.
    await until(() async =>
        await glCount(doc.id) >= 4 &&
        asNum((await bin())?.payload['actual_qty'] ?? -1) == 7);
    return doc;
  }

  Future<num> accountBalance(String account) async {
    final rows = await engine.list('GL Entry',
        filters: {'account': account}, userRoles: roles);
    num bal = 0;
    for (final r in rows) {
      bal += asNum(r.payload['debit']) - asNum(r.payload['credit']);
    }
    return bal;
  }

  Future<num> voucherAccount(String account, String voucherNo) async {
    final rows = await engine.list('GL Entry',
        filters: {'account': account, 'voucher_no': voucherNo},
        userRoles: roles);
    num bal = 0;
    for (final r in rows) {
      bal += asNum(r.payload['debit']) - asNum(r.payload['credit']);
    }
    return bal;
  }


  test('buy 10 @ 5: qty 10, inventory €50 in Bin AND GL; GRNI nets zero',
      () async {
    final pi = await buy10At5();

    final b = await bin();
    expect(asNum(b!.payload['actual_qty']), 10);
    expect(asNum(b.payload['stock_value']), 50);

    expect(await accountBalance('Stock'), 50); // GL inventory asset
    expect(await accountBalance('GRNI'), 0); // Dr split leg == Cr SLE leg
    expect(await voucherAccount('Creditors', pi.id), -50); // Cr AP
    expect(await accountBalance('COGS'), 0); // nothing expensed on purchase
  });

  test('sell 3 @ 12: qty 7, inventory €35, revenue €36, COGS €15, GP €21',
      () async {
    await buy10At5();
    final si = await sell3At12();

    final b = await bin();
    expect(asNum(b!.payload['actual_qty']), 7);
    expect(asNum(b.payload['stock_value']), 35);

    expect(await accountBalance('Stock'), 35); // 50 − 15
    final revenue = -await voucherAccount('Sales', si.id); // credit balance
    expect(revenue, 36);
    final cogs = await accountBalance('COGS');
    expect(cogs, 15); // 3 × €5 valuation, never the €12 selling price
    expect(revenue - cogs, 21); // gross profit
    expect(await voucherAccount('Debtors', si.id), 36); // AR gross (no VAT row)

    // Stock ledger ↔ GL inventory reconcile.
    expect(asNum(b.payload['stock_value']), await accountBalance('Stock'));
  });

  test('service items never touch stock or COGS', () async {
    final si = Document(id: '', docType: 'Sales Invoice', payload: {
      'customer': 'CUST-1',
      'posting_date': today,
      'update_stock': 1,
      'set_warehouse': 'WH',
    });
    si.children['items'] = [
      line('Sales Invoice', {'item': 'SVC-1', 'qty': 2, 'rate': 100}),
    ];
    final doc = await engine.submit(await engine.save(si, roles), roles);
    await until(() async => await glCount(doc.id) >= 2);

    final sles = await engine.list('Stock Ledger Entry',
        filters: {'voucher_no': doc.id}, userRoles: roles);
    expect(sles, isEmpty);
    expect(await accountBalance('COGS'), 0);
    expect(await accountBalance('Stock'), 0);
    expect(await voucherAccount('Debtors', doc.id), 200); // revenue still posts
  });

  test('cancelling the sale reverses accounting and stock exactly', () async {
    await buy10At5();
    final si = await sell3At12();
    final before = await glCount(si.id);
    await engine.cancel(si, roles);
    await until(() async =>
        await glCount(si.id) >= before * 2 &&
        asNum((await bin())?.payload['actual_qty'] ?? -1) == 10);

    final b = await bin();
    expect(asNum(b!.payload['actual_qty']), 10); // back to 10
    expect(asNum(b.payload['stock_value']), 50);
    expect(await accountBalance('Stock'), 50);
    expect(await accountBalance('COGS'), 0);
    expect(await voucherAccount('Sales', si.id), 0); // revenue netted out
    expect(await voucherAccount('Debtors', si.id), 0);
  });

  test('a sales return restores inventory at cost and reverses COGS',
      () async {
    await buy10At5();
    final si = await sell3At12();

    // Credit note: same doc type, is_return + negated quantities.
    final ret = Document(id: '', docType: 'Sales Invoice', payload: {
      'customer': 'CUST-1',
      'posting_date': today,
      'update_stock': 1,
      'set_warehouse': 'WH',
      'is_return': 1,
      'return_against': si.id,
    });
    ret.children['items'] = [
      line('Sales Invoice', {'item': 'ITEM-A', 'qty': -3, 'rate': 12}),
    ];
    final retDoc = await engine.submit(await engine.save(ret, roles), roles);
    await until(() async =>
        await glCount(retDoc.id) >= 4 &&
        asNum((await bin())?.payload['actual_qty'] ?? -1) == 10);

    final b = await bin();
    expect(asNum(b!.payload['actual_qty']), 10);
    // Goods re-enter at the €5 issue cost, not the €12 selling price.
    expect(asNum(b.payload['stock_value']), 50);
    expect(await accountBalance('Stock'), 50);
    expect(await accountBalance('COGS'), 0); // 15 − 15
    expect(await accountBalance('Sales'), 0); // 36 − 36
  });

  test('two-document purchase: receipt then bill clears GRNI', () async {
    // Purchase Receipt: goods in.
    final pr = Document(id: '', docType: 'Purchase Receipt', payload: {
      'supplier': 'SUPP-1',
      'posting_date': today,
      'set_warehouse': 'WH',
    });
    pr.children['items'] = [
      line('Purchase Receipt', {'item': 'ITEM-A', 'qty': 10, 'rate': 5}),
    ];
    final received = await engine.submit(await engine.save(pr, roles), roles);
    await until(() async =>
        await glCount(received.id) >= 2 &&
        asNum((await bin())?.payload['actual_qty'] ?? -1) == 10);

    expect(await accountBalance('Stock'), 50);
    expect(await accountBalance('GRNI'), -50); // credit: awaiting the bill

    // Purchase Invoice (no update_stock): bill for the received goods.
    final pi = Document(id: '', docType: 'Purchase Invoice', payload: {
      'supplier': 'SUPP-1',
      'posting_date': today,
    });
    pi.children['items'] = [
      line('Purchase Invoice', {'item': 'ITEM-A', 'qty': 10, 'rate': 5}),
    ];
    final billed = await engine.submit(await engine.save(pi, roles), roles);
    await until(() async => await glCount(billed.id) >= 2);

    expect(await accountBalance('GRNI'), 0); // cleared
    expect(await voucherAccount('Creditors', billed.id), -50);
    expect(await accountBalance('COGS'), 0); // still nothing expensed
    expect(await accountBalance('Stock'), 50); // stock unchanged by the bill

    final b = await bin();
    expect(asNum(b!.payload['actual_qty']), 10);
  });

  test('LedgerDerivation.derive still balances for every voucher (pure)', () {
    // The service adds stock GL legs itself; the pure derivation must stay
    // balanced without them.
    final doc = Document(id: 'SINV-X', docType: 'Sales Invoice', payload: {
      'customer': 'CUST-1',
      'debit_to': 'Debtors',
      'income_account': 'Sales',
      'grand_total': 100,
      'posting_date': today,
      'update_stock': 1,
      'set_warehouse': 'WH',
    });
    doc.children['items'] = [
      line('Sales Invoice', {'item': 'ITEM-A', 'qty': 1, 'rate': 100}),
    ];
    final rows = LedgerDerivation.derive(doc, reversal: false);
    num debit = 0, credit = 0;
    for (final r in rows) {
      if (r.docType != 'GL Entry') continue;
      debit += asNum(r.payload['debit']);
      credit += asNum(r.payload['credit']);
    }
    expect(debit, credit);
    // And it now carries the issue SLE for the runtime to cost.
    expect(rows.where((r) => r.docType == 'Stock Ledger Entry').length, 1);
  });
}
