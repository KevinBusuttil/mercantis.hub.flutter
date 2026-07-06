import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_hub_app/ledger/hub_interceptors.dart';
import 'package:mercantis_hub_app/ledger/ledger_derivation_service.dart';
import 'package:mercantis_hub_app/ledger/ledger_values.dart';
import 'package:mercantis_hub_app/manifest/hub_manifest.dart';
import 'package:mercantis_hub_app/modules/stock/stock_count.dart';
import 'package:mercantis_hub_app/onboarding/hub_seeder.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The stock-count workflow: differences post as adjustment SLEs with the
/// matching Stock Adjustment GL legs, and the bin lands on the counted qty.
void main() {
  setUpAll(sqfliteFfiInit);

  test('count down and up adjusts bin, inventory GL and adjustment account',
      () async {
    final db = await MercantisDatabase.open(
        factory: databaseFactoryFfi, path: inMemoryDatabasePath);
    addTearDown(db.close);
    const roles = {'System Manager'};
    final today = DateTime.now().toIso8601String().split('T').first;
    final registry = MetadataRegistry(db.db);
    final sync = SyncEngine(database: db.db, registry: registry);
    await AppInstaller(database: db.db, registry: registry, syncEngine: sync)
        .install(HubManifest.build());
    final emitter = EventEmitter();
    final engine = DocumentEngine(
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
        FiscalYearGuardInterceptor(),
        NegativeStockGuardInterceptor(),
      ],
    );
    await HubSeeder(engine, roles: roles).seed(
        businessName: 'Acme', currencyCode: 'EUR', year: DateTime.now().year);
    final ledger = LedgerDerivationService(engine: engine, emitter: emitter);
    ledger.start();
    addTearDown(ledger.dispose);

    await engine.save(
        Document(id: 'WH', docType: 'Warehouse',
            payload: {'warehouse_name': 'Main'}),
        roles);
    await engine.save(
        Document(id: 'ITEM-A', docType: 'Item', payload: {
          'item_code': 'ITEM-A',
          'item_name': 'Item A',
          'item_type': 'Stock',
          'stock_uom': 'Nos',
        }),
        roles);

    Future<void> until(Future<bool> Function() cond) async {
      for (var i = 0; i < 80; i++) {
        if (await cond()) return;
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
      fail('derivation did not settle');
    }

    Future<num> bin() async =>
        asNum((await engine.fetch('Bin', 'BIN-ITEM-A-WH'))?.payload['actual_qty']);

    Future<num> balance(String account) async {
      final rows = await engine.list('GL Entry',
          filters: {'account': account}, userRoles: roles);
      num b = 0;
      for (final r in rows) {
        b += asNum(r.payload['debit']) - asNum(r.payload['credit']);
      }
      return b;
    }

    // Seed 10 @ €5 via a receipt.
    final receipt = Document(id: '', docType: 'Stock Entry', payload: {
      'stock_entry_type': 'Material Receipt',
      'posting_date': today,
    });
    receipt.children['items'] = [
      ChildRow(
        id: '', parentId: '', parentDocType: 'Stock Entry',
        tableName: 'items', rowIndex: 0,
        payload: {'item': 'ITEM-A', 'qty': 10, 'target_warehouse': 'WH', 'valuation_rate': 5},
      ),
    ];
    await engine.submit(await engine.save(receipt, roles), roles);
    await until(() async => await bin() == 10);

    // Count finds only 7 → adjustment issues 3 at €5.
    final down = buildStockCountEntry(
      warehouse: 'WH',
      postingDate: today,
      lines: const [
        StockCountLine(item: 'ITEM-A', onHand: 10, counted: 7, valuationRate: 5),
      ],
    );
    expect(down.payload['stock_entry_type'], 'Stock Count');
    expect(down.children['items']!.length, 1);
    await engine.submit(await engine.save(down, roles), roles);
    await until(() async => await bin() == 7);
    expect(await balance('Stock'), 35); // 50 in, 15 out
    // The seed Material Receipt itself credited Stock Adjustment 50 (goods
    // appearing = gain); the count-down loss debits 15 back.
    expect(await balance('Stock Adjustment'), -35);

    // Recount finds 9 → gain of 2 at the bin's €5 rate.
    final up = buildStockCountEntry(
      warehouse: 'WH',
      postingDate: today,
      lines: const [
        StockCountLine(item: 'ITEM-A', onHand: 7, counted: 9, valuationRate: 5),
      ],
    );
    await engine.submit(await engine.save(up, roles), roles);
    await until(() async => await bin() == 9);
    expect(await balance('Stock'), 45);
    expect(await balance('Stock Adjustment'), -45); // −35 − 10 gain

    // A perfect count builds an entry with no rows.
    final noop = buildStockCountEntry(
      warehouse: 'WH',
      postingDate: today,
      lines: const [
        StockCountLine(item: 'ITEM-A', onHand: 9, counted: 9),
      ],
    );
    expect(noop.children['items'], isEmpty);
  });
}
