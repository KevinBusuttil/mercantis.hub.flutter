import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_hub_app/ledger/hub_interceptors.dart';
import 'package:mercantis_hub_app/manifest/hub_manifest.dart';
import 'package:mercantis_hub_app/onboarding/hub_seeder.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// H5 posting guards: the books-lock (period close) and negative-stock guards.
/// Runs against a real in-memory engine with the full Hub manifest + seed and
/// the Hub interceptor chain (including the two new guards).
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
  });

  tearDown(() async => db.close());

  Future<Document> company() async =>
      (await engine.list('Company', userRoles: roles)).first;

  group('Books-lock guard', () {
    Future<Document> invoice(String date) => engine.save(
        Document(id: '', docType: 'Sales Invoice', payload: {
          'customer': 'CUST-1',
          'posting_date': date,
        }),
        roles);

    setUp(() async {
      await engine.save(
          Document(id: 'CUST-1', docType: 'Customer', payload: {
            'customer_name': 'Acme Buyer',
            'customer_type': 'Company',
          }),
          roles);
    });

    test('blocks a posting on/before the lock date, allows after', () async {
      final co = await company();
      co.payload['books_lock_date'] = '2026-06-30';
      await engine.save(co, roles);

      final locked = await invoice('2026-06-15');
      await expectLater(
          engine.submit(locked, roles), throwsA(isA<DocumentEngineError>()));
      expect((await engine.fetch('Sales Invoice', locked.id))!.docStatus, 0);

      final open = await invoice('2026-07-15');
      expect((await engine.submit(open, roles)).docStatus, 1);
    });

    test('dormant when no lock date is configured', () async {
      final si = await invoice('2026-02-01');
      expect((await engine.submit(si, roles)).docStatus, 1);
    });
  });

  group('Negative-stock guard', () {
    Future<void> seedMasters({required num onHand}) async {
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
          Document(id: 'CUST-1', docType: 'Customer', payload: {
            'customer_name': 'Acme Buyer',
            'customer_type': 'Company',
          }),
          roles);
      if (onHand != 0) {
        await engine.save(
            Document(id: 'BIN-ITM-WH', docType: 'Bin', payload: {
              'item': 'ITM',
              'warehouse': 'WH',
              'actual_qty': onHand,
              'valuation_rate': 10,
              'stock_value': onHand * 10,
            }),
            roles);
      }
    }

    Future<Document> delivery(num qty) async {
      final dn = Document(id: '', docType: 'Delivery Note', payload: {
        'customer': 'CUST-1',
        'posting_date': '2026-06-01',
        'set_warehouse': 'WH',
      });
      dn.children['items'] = [
        ChildRow(
          id: '',
          parentId: '',
          parentDocType: 'Delivery Note',
          tableName: 'items',
          rowIndex: 0,
          payload: {'item': 'ITM', 'qty': qty, 'rate': 10},
        ),
      ];
      return engine.save(dn, roles);
    }

    test('blocks an issue that exceeds on-hand', () async {
      await seedMasters(onHand: 5);
      final dn = await delivery(8);
      await expectLater(
          engine.submit(dn, roles), throwsA(isA<DocumentEngineError>()));
      expect((await engine.fetch('Delivery Note', dn.id))!.docStatus, 0);
    });

    test('allows an issue within on-hand', () async {
      await seedMasters(onHand: 5);
      final dn = await delivery(3);
      expect((await engine.submit(dn, roles)).docStatus, 1);
    });

    test('allow_negative_stock lets a short issue through', () async {
      await seedMasters(onHand: 0);
      final co = await company();
      co.payload['allow_negative_stock'] = 1;
      await engine.save(co, roles);
      final dn = await delivery(4);
      expect((await engine.submit(dn, roles)).docStatus, 1);
    });

    test('skips non-stock (service) items — not blocked for having no Bin', () async {
      await engine.save(
          Document(id: 'WH', docType: 'Warehouse',
              payload: {'warehouse_name': 'Main'}),
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
      final dn = Document(id: '', docType: 'Delivery Note', payload: {
        'customer': 'CUST-1',
        'posting_date': '2026-06-01',
        'set_warehouse': 'WH',
      });
      dn.children['items'] = [
        ChildRow(
          id: '',
          parentId: '',
          parentDocType: 'Delivery Note',
          tableName: 'items',
          rowIndex: 0,
          payload: {'item': 'SVC', 'qty': 5, 'rate': 10},
        ),
      ];
      final saved = await engine.save(dn, roles);
      expect((await engine.submit(saved, roles)).docStatus, 1);
    });
  });
}
