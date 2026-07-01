import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_hub_app/modules/pos/pos_shift_report.dart';
import 'package:mercantis_hub_app/manifest/hub_manifest.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// H8 — POS shift (X/Z) reports.
void main() {
  group('PosShiftReportBuilder (pure)', () {
    test('X-report folds sales, tenders, tax; expected cash = float + cash', () {
      final r = PosShiftReportBuilder.build(
        const [
          PosSale(grandTotal: 100, taxTotal: 18, qty: 2,
              tenders: [PosTender('Cash', 60), PosTender('Card', 40)]),
          PosSale(grandTotal: 50, taxTotal: 9, qty: 1,
              tenders: [PosTender('Cash', 50)]),
        ],
        openingFloat: 20,
      );
      expect(r.transactions, 2);
      expect(r.grossSales, 150);
      expect(r.netSales, 150);
      expect(r.itemsSold, 3);
      expect(r.taxCollected, 27);
      expect(r.tenderTotals, {'Cash': 110, 'Card': 40});
      expect(r.expectedCash, 130); // 20 float + 110 cash
      expect(r.isZReport, isFalse);
      expect(r.overShort, isNull);
    });

    test('a refund nets sales, items, and cash down', () {
      final r = PosShiftReportBuilder.build(
        const [
          PosSale(grandTotal: 100, taxTotal: 18, qty: 2,
              tenders: [PosTender('Cash', 100)]),
          PosSale(grandTotal: -30, taxTotal: -5, qty: -1,
              tenders: [PosTender('Cash', -30)]),
        ],
        openingFloat: 10,
      );
      expect(r.grossSales, 100);
      expect(r.refunds, 30);
      expect(r.netSales, 70);
      expect(r.itemsSold, 1);
      expect(r.tenderTotals['Cash'], 70);
      expect(r.expectedCash, 80); // 10 + 70
    });

    test('Z-report computes the cash over/short', () {
      final short = PosShiftReportBuilder.build(
        const [PosSale(grandTotal: 100, taxTotal: 0, qty: 1,
            tenders: [PosTender('Cash', 100)])],
        openingFloat: 20,
        countedCash: 118,
      );
      expect(short.isZReport, isTrue);
      expect(short.expectedCash, 120);
      expect(short.overShort, -2); // counted 118 vs expected 120 → short

      final over = PosShiftReportBuilder.build(
        const [PosSale(grandTotal: 100, taxTotal: 0, qty: 1,
            tenders: [PosTender('Cash', 100)])],
        openingFloat: 20,
        countedCash: 123,
      );
      expect(over.overShort, 3);
    });
  });

  group('PosShiftReportService (engine)', () {
    setUpAll(sqfliteFfiInit);
    late MercantisDatabase db;
    late DocumentEngine engine;
    late PosShiftReportService service;
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
        interceptors: const [],
      );
      service = PosShiftReportService(engine: engine, roles: roles);

      await engine.save(
          Document(id: 'ITM', docType: 'Item', payload: {
            'item_code': 'ITM', 'item_name': 'Widget', 'stock_uom': 'Nos',
          }),
          roles);
      await engine.save(
          Document(id: 'PP-1', docType: 'POS Profile', payload: {
            'profile_name': 'Front Till', 'enabled': '1',
          }),
          roles);
      await engine.save(
          Document(id: 'PS-1', docType: 'POS Session', payload: {
            'pos_profile': 'PP-1', 'status': 'Open', 'opening_amount': 20,
          }),
          roles);
    });

    tearDown(() async => db.close());

    Future<void> sale(String id,
        {required num grand, required num tax, required num qty,
        required List<List<Object>> tenders}) async {
      final inv = Document(id: id, docType: 'POS Invoice', payload: {
        'pos_session': 'PS-1',
        'posting_date': '2026-06-30',
        'grand_total': grand,
        'tax_total': tax,
      });
      inv.children['items'] = [
        ChildRow(id: '', parentId: '', parentDocType: 'POS Invoice',
            tableName: 'items', rowIndex: 0,
            payload: {'item': 'ITM', 'qty': qty, 'rate': 50}),
      ];
      inv.children['tenders'] = [
        for (var i = 0; i < tenders.length; i++)
          ChildRow(id: '', parentId: '', parentDocType: 'POS Invoice',
              tableName: 'tenders', rowIndex: i,
              payload: {'tender_type': tenders[i][0], 'amount': tenders[i][1]}),
      ];
      await engine.submit(await engine.save(inv, roles), roles);
    }

    test('report aggregates a session\'s submitted invoices', () async {
      await sale('INV1', grand: 100, tax: 18, qty: 2,
          tenders: [['Cash', 60], ['Card', 40]]);
      await sale('INV2', grand: 50, tax: 9, qty: 1, tenders: [['Cash', 50]]);

      final x = await service.report('PS-1');
      expect(x.transactions, 2);
      expect(x.netSales, 150);
      expect(x.itemsSold, 3);
      expect(x.taxCollected, 27);
      expect(x.tenderTotals, {'Cash': 110, 'Card': 40});
      expect(x.expectedCash, 130);
      expect(x.isZReport, isFalse);

      final z = await service.report('PS-1', countedCash: 128);
      expect(z.overShort, -2);
    });

    test('closeShift writes the Z totals and marks the session Closed', () async {
      await sale('INV1', grand: 100, tax: 18, qty: 2, tenders: [['Cash', 100]]);

      final session = await service.closeShift('PS-1',
          countedCash: 120, closingDate: '2026-06-30');
      expect(session.payload['status'], 'Closed');
      expect(session.payload['closing_amount'], 120);
      expect(session.payload['total_sales'], 100);
      expect(session.payload['total_qty'], 2);
      expect(session.payload['closing_date'], '2026-06-30');
    });
  });
}
