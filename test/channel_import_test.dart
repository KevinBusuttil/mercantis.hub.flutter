import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_hub_app/ledger/hub_interceptors.dart';
import 'package:mercantis_hub_app/ledger/ledger_derivation_service.dart';
import 'package:mercantis_hub_app/ledger/ledger_values.dart' hide isTrue;
import 'package:mercantis_hub_app/manifest/hub_manifest.dart';
import 'package:mercantis_hub_app/modules/channels/channel_import_service.dart';
import 'package:mercantis_hub_app/modules/channels/channel_order_csv_importer.dart';
import 'package:mercantis_hub_app/onboarding/hub_seeder.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Sales channels (Phase 5, CSV first): a storefront's order-lines export is
/// staged as Channel Orders (idempotently), then posted as OFFICIAL Sales
/// Invoices — through the same ledger spine as any other sale, so stock
/// issues and COGS posts. Unmapped SKUs fail their order loudly; the same
/// buyer across orders becomes one Customer.
void main() {
  setUpAll(sqfliteFfiInit);

  late MercantisDatabase db;
  late DocumentEngine engine;
  late EventEmitter emitter;
  late LedgerDerivationService ledger;
  late ChannelImportService service;
  late String channelId;
  const roles = {'System Manager'};
  final today = DateTime.now().toIso8601String().split('T').first;

  String csvFor(List<String> rows) => [
        'Order ID,Date,SKU,Product Name,Qty,Unit Price,Billing Name,Email',
        ...rows,
      ].join('\n');

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
    ledger = LedgerDerivationService(engine: engine, emitter: emitter);
    ledger.start();
    service = ChannelImportService(engine: engine);

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
          'valuation_method': 'Moving Average',
        }),
        roles);
    await engine.save(
        Document(id: 'SUPP-1', docType: 'Supplier', payload: {
          'supplier_name': 'Apex Supplies',
          'supplier_type': 'Company',
        }),
        roles);

    // The storefront: ships from WH, exclusive prices, auto-submits — a
    // posted order becomes an official invoice immediately.
    final channel = await engine.save(
        Document(id: '', docType: 'Sales Channel', payload: {
          'channel_name': 'Web shop',
          'channel_type': 'CSV',
          'warehouse': 'WH',
          'prices_include_tax': 0,
          'auto_submit': 1,
        }),
        roles);
    channelId = channel.id;
    // The storefront calls ITEM-A "WIDGET".
    await engine.save(
        Document(id: '', docType: 'Channel Product', payload: {
          'channel': channelId,
          'channel_sku': 'WIDGET',
          'item': 'ITEM-A',
        }),
        roles);
  });

  tearDown(() async {
    ledger.dispose();
    await db.close();
  });

  Future<void> until(Future<bool> Function() cond) async {
    for (var i = 0; i < 80; i++) {
      if (await cond()) return;
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    fail('derivation did not settle');
  }

  /// Stock on hand first: buy 10 @ €5 so channel sales have something to
  /// issue (and a cost to post).
  Future<void> buy10At5() async {
    final pi = Document(id: '', docType: 'Purchase Invoice', payload: {
      'supplier': 'SUPP-1',
      'posting_date': today,
      'update_stock': 1,
      'set_warehouse': 'WH',
    });
    pi.children['items'] = [
      ChildRow(
        id: '', parentId: '', parentDocType: 'Purchase Invoice',
        tableName: 'items', rowIndex: 0,
        payload: {'item': 'ITEM-A', 'qty': 10, 'rate': 5},
      ),
    ];
    final doc = await engine.submit(await engine.save(pi, roles), roles);
    await until(() async {
      final bin = await engine.fetch('Bin', 'BIN-ITEM-A-WH');
      return bin != null &&
          asNum(bin.payload['actual_qty']) == 10 &&
          (await engine.list('GL Entry',
                  filters: {'voucher_no': doc.id}, userRoles: roles))
              .isNotEmpty;
    });
  }

  test('parser groups rows into orders and keeps header fields', () {
    final parsed = ChannelOrderCsvImporter.parse(csvFor([
      '1001,$today,WIDGET,Widget,2,"12.00",Jane Doe,jane@example.com',
      '1001,$today,ITEM-A,Item A,1,20.00,Jane Doe,jane@example.com',
      '1002,$today,WIDGET,Widget,1,"1.234,56",John Smith,john@example.com',
      ',,MISSING-ORDER,x,1,5,,', // no order reference — skipped
    ]));
    expect(parsed.orders.length, 2);
    expect(parsed.skipped, 1);
    final first = parsed.orders.first;
    expect(first.externalId, '1001');
    expect(first.lines.length, 2);
    expect(first.orderDate, today);
    expect(first.customerEmail, 'jane@example.com');
    expect(first.grossTotal, 44); // 2×12 + 1×20
    expect(parsed.orders.last.lines.single.rate, 1234.56); // EU format
  });

  test('import stages orders once — re-importing the same file adds nothing',
      () async {
    final csv = csvFor([
      '1001,$today,WIDGET,Widget,2,12.00,Jane Doe,jane@example.com',
      '1001,$today,ITEM-A,Item A,1,20.00,Jane Doe,jane@example.com',
      '1002,$today,WIDGET,Widget,1,12.00,John Smith,john@example.com',
    ]);
    final first = await service.importCsv(channelId: channelId, csv: csv);
    expect(first.imported, 2);
    expect(first.duplicates, 0);

    final again = await service.importCsv(channelId: channelId, csv: csv);
    expect(again.imported, 0);
    expect(again.duplicates, 2);

    final orders = await engine.list('Channel Order',
        filters: {'channel': channelId}, userRoles: roles);
    expect(orders.length, 2);
    final order1001 = orders
        .firstWhere((o) => o.payload['external_order_id'] == '1001');
    expect(order1001.payload['status'], 'Imported');
    expect(asNum(order1001.payload['gross_total']), 44);
    final hydrated = await engine.fetch('Channel Order', order1001.id);
    expect(hydrated!.children['lines']!.length, 2);

    // Each run leaves a sync log.
    final logs = await engine.list('Channel Sync Log',
        filters: {'channel': channelId}, userRoles: roles);
    expect(logs.length, 2);
    expect(asNum(logs.first.payload['imported']) +
        asNum(logs.last.payload['imported']), 2);
  });

  test('posted orders are OFFICIAL invoices: stock issues and COGS posts',
      () async {
    await buy10At5();
    await service.importCsv(
        channelId: channelId,
        csv: csvFor([
          '1001,$today,WIDGET,Widget,2,12.00,Jane Doe,jane@example.com',
          '1001,$today,ITEM-A,Item A,1,20.00,Jane Doe,jane@example.com',
          '1002,$today,WIDGET,Widget,1,12.00,John Smith,john@example.com',
        ]));

    final result = await service.postImported(channelId: channelId);
    expect(result.posted, 2);
    expect(result.failed, 0);

    final orders = await engine.list('Channel Order',
        filters: {'channel': channelId}, userRoles: roles);
    expect(orders.every((o) => o.payload['status'] == 'Posted'), isTrue);

    final invoiceIds = [
      for (final o in orders) '${o.payload['sales_invoice']}',
    ];
    num invoiced = 0;
    for (final id in invoiceIds) {
      final invoice = await engine.fetch('Sales Invoice', id);
      expect(invoice!.docStatus, 1); // auto_submit — official, not a draft
      expect(invoice.payload['sales_channel'], channelId);
      expect(invoice.payload['update_stock'], isNotNull);
      invoiced += asNum(invoice.payload['grand_total']);
    }
    expect(invoiced, 56); // 44 + 12

    // 4 units issued at €5 average cost → COGS €20, 6 left in the bin.
    await until(() async {
      final bin = await engine.fetch('Bin', 'BIN-ITEM-A-WH');
      if (bin == null || asNum(bin.payload['actual_qty']) != 6) return false;
      num cogs = 0;
      for (final id in invoiceIds) {
        for (final gl in await engine.list('GL Entry',
            filters: {'voucher_no': id}, userRoles: roles)) {
          if (gl.payload['account'] == 'COGS') {
            cogs += asNum(gl.payload['debit']) - asNum(gl.payload['credit']);
          }
        }
      }
      return cogs == 20;
    });

    // Idempotent: a second posting run finds nothing staged.
    final rerun = await service.postImported(channelId: channelId);
    expect(rerun.posted, 0);
    expect(rerun.failed, 0);
  });

  test('the same buyer across orders becomes ONE customer', () async {
    await buy10At5();
    await service.importCsv(
        channelId: channelId,
        csv: csvFor([
          '2001,$today,WIDGET,Widget,1,12.00,Jane Doe,jane@example.com',
          '2002,$today,WIDGET,Widget,1,12.00,Jane D.,JANE@example.com',
        ]));
    await service.postImported(channelId: channelId);

    final orders = await engine.list('Channel Order',
        filters: {'channel': channelId}, userRoles: roles);
    final customers = <String>{};
    for (final o in orders) {
      final invoice = await engine.fetch(
          'Sales Invoice', '${o.payload['sales_invoice']}');
      customers.add('${invoice!.payload['customer']}');
    }
    expect(customers.length, 1); // email is the identity, case-insensitive
    final buyer = await engine.fetch('Customer', customers.single);
    // Whichever order posts first names the record; identity is the email.
    expect('${buyer!.payload['customer_name']}', startsWith('Jane'));
    expect(buyer.payload['email'], 'jane@example.com');
  });

  test('an unmapped SKU fails its order loudly; mapping it makes the retry '
      'post', () async {
    await buy10At5();
    await service.importCsv(
        channelId: channelId,
        csv: csvFor([
          '3001,$today,MYSTERY,Unknown thing,1,9.99,Jane Doe,jane@example.com',
          '3002,$today,WIDGET,Widget,1,12.00,John Smith,john@example.com',
        ]));

    final result = await service.postImported(channelId: channelId);
    expect(result.posted, 1);
    expect(result.failed, 1);

    final orders = await engine.list('Channel Order',
        filters: {'channel': channelId}, userRoles: roles);
    final failed = orders
        .firstWhere((o) => o.payload['external_order_id'] == '3001');
    expect(failed.payload['status'], 'Failed');
    expect('${failed.payload['error']}', contains('Unmapped SKU "MYSTERY"'));

    // Map the SKU; Failed orders are retryable.
    await engine.save(
        Document(id: '', docType: 'Channel Product', payload: {
          'channel': channelId,
          'channel_sku': 'MYSTERY',
          'item': 'ITEM-A',
        }),
        roles);
    final retry = await service.postImported(channelId: channelId);
    expect(retry.posted, 1);
    expect(retry.failed, 0);
    final recovered = await engine.fetch('Channel Order', failed.id);
    expect(recovered!.payload['status'], 'Posted');
    expect('${recovered.payload['error']}', isEmpty);
  });

  test('an order with no customer details needs the channel default',
      () async {
    await service.importCsv(
        channelId: channelId,
        csv: csvFor(['4001,$today,WIDGET,Widget,1,12.00,,']));
    final result = await service.postImported(channelId: channelId);
    expect(result.failed, 1);
    final order = (await engine.list('Channel Order',
            filters: {'channel': channelId}, userRoles: roles))
        .single;
    expect('${order.payload['error']}', contains('no customer'));

    // Give the channel a walk-in default and retry.
    await engine.save(
        Document(id: 'CUST-WEB', docType: 'Customer', payload: {
          'customer_name': 'Web shop guest',
          'customer_type': 'Individual',
        }),
        roles);
    final channel = await engine.fetch('Sales Channel', channelId);
    channel!.payload['default_customer'] = 'CUST-WEB';
    await engine.save(channel, roles);
    await buy10At5();
    final retry = await service.postImported(channelId: channelId);
    expect(retry.posted, 1);
    final posted = await engine.fetch('Channel Order', order.id);
    final invoice = await engine.fetch(
        'Sales Invoice', '${posted!.payload['sales_invoice']}');
    expect(invoice!.payload['customer'], 'CUST-WEB');
  });
}
