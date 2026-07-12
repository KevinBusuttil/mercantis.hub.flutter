import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_hub_app/ledger/hub_interceptors.dart';
import 'package:mercantis_hub_app/ledger/ledger_values.dart' hide isTrue;
import 'package:mercantis_hub_app/manifest/hub_manifest.dart';
import 'package:mercantis_hub_app/pricing/price_resolver.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// S8 (Phase 1): Price List stops being a dead doctype. The resolver walks
/// document list → customer list → company list → standard rate; within a
/// list the deepest earned quantity break wins inside its validity window.
/// The interceptor fills blank line rates on save and never touches a rate
/// somebody entered.
void main() {
  setUpAll(sqfliteFfiInit);

  late MercantisDatabase db;
  late DocumentEngine engine;
  late PriceResolver resolver;
  const roles = {'System Manager'};

  Future<Document> save(String docType, String id, Map<String, dynamic> payload,
      {Map<String, List<Map<String, dynamic>>>? children}) async {
    final doc = Document(id: id, docType: docType, payload: payload);
    children?.forEach((table, rows) {
      doc.children[table] = [
        for (var i = 0; i < rows.length; i++)
          ChildRow(
            id: '', parentId: '', parentDocType: docType,
            tableName: table, rowIndex: i, payload: rows[i],
          ),
      ];
    });
    return engine.save(doc, roles);
  }

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
        PriceResolutionInterceptor(),
        DiscountInterceptor(),
        LineItemTotalsInterceptor(),
        TaxCalculationInterceptor(),
      ],
    );
    resolver = PriceResolver(engine);

    await save('Currency', 'EUR', {'currency_name': 'Euro'});
    await save('Item', 'WIDGET', {
      'item_code': 'WIDGET', 'item_name': 'Widget',
      'item_type': 'Service', 'stock_uom': 'Nos', 'standard_rate': 100,
    });
    await save('Customer', 'CUST-1',
        {'customer_name': 'C', 'customer_type': 'Company'});

    // Trade list: 90 at any qty, 80 from 10 up; expired promo row at 50.
    await save('Price List', 'TRADE', {
      'price_list_name': 'Trade', 'currency': 'EUR',
      'selling': 1, 'enabled': 1,
    }, children: {
      'items': [
        {'item': 'WIDGET', 'rate': 90},
        {'item': 'WIDGET', 'rate': 80, 'min_qty': 10},
        {
          'item': 'WIDGET', 'rate': 50,
          'valid_from': '2020-01-01', 'valid_upto': '2020-12-31',
        },
      ],
    });
  });

  tearDown(() async => db.close());

  group('PriceResolver', () {
    test('explicit list, quantity breaks, and expired windows', () async {
      final single = await resolver.resolve(item: 'WIDGET', priceList: 'TRADE');
      expect(single!.rate, 90);
      expect(single.priceList, 'TRADE');

      final bulk = await resolver.resolve(
          item: 'WIDGET', qty: 10, priceList: 'TRADE');
      expect(bulk!.rate, 80); // deepest earned break

      // The 50 promo expired in 2020 — never offered today.
      final today = await resolver.resolve(
          item: 'WIDGET', qty: 100, priceList: 'TRADE');
      expect(today!.rate, 80);
    });

    test('customer default is used when the document names no list',
        () async {
      final before = await resolver.resolve(item: 'WIDGET', customer: 'CUST-1');
      expect(before!.priceList, isNull);
      expect(before.rate, 100); // standard rate — customer has no list yet

      final customer = await engine.fetch('Customer', 'CUST-1');
      customer!.payload['default_price_list'] = 'TRADE';
      await engine.save(customer, roles);

      final after = await resolver.resolve(item: 'WIDGET', customer: 'CUST-1');
      expect(after!.rate, 90);
      expect(after.priceList, 'TRADE');
    });

    test('disabled and wrong-currency lists are skipped entirely', () async {
      final list = await engine.fetch('Price List', 'TRADE');
      list!.payload['enabled'] = 0;
      await engine.save(list, roles);
      final disabled =
          await resolver.resolve(item: 'WIDGET', priceList: 'TRADE');
      expect(disabled!.rate, 100); // fell through to standard

      list.payload['enabled'] = 1;
      await engine.save(list, roles);
      final gbp = await resolver.resolve(
          item: 'WIDGET', priceList: 'TRADE', currency: 'GBP');
      expect(gbp!.rate, 100); // EUR list can't price a GBP document
    });

    test('sellingRates maps the whole list for the POS till', () async {
      final rates = await resolver.sellingRates(priceList: 'TRADE');
      expect(rates, {'WIDGET': 90}); // qty-1 view: breaks don't apply
    });
  });

  group('PriceResolutionInterceptor', () {
    test('fills blank rates on save and stamps the list used', () async {
      final customer = await engine.fetch('Customer', 'CUST-1');
      customer!.payload['default_price_list'] = 'TRADE';
      await engine.save(customer, roles);

      final invoice = await save('Sales Invoice', '', {
        'customer': 'CUST-1',
        'posting_date': '2026-07-11',
      }, children: {
        'items': [
          {'item': 'WIDGET', 'qty': 10}, // no rate — resolve me
          {'item': 'WIDGET', 'qty': 1, 'rate': 42}, // entered — keep
        ],
      });

      final saved = await engine.fetch('Sales Invoice', invoice.id);
      final lines = saved!.children['items']!;
      expect(asNum(lines[0].payload['rate']), 80); // qty break applied
      expect(asNum(lines[0].payload['amount']), 800); // totals ran after
      expect(asNum(lines[1].payload['rate']), 42); // untouched
      expect(saved.payload['price_list'], 'TRADE'); // provenance stamped
      expect(asNum(saved.payload['grand_total']), 842);
    });

    test('without any list the standard rate still prices the line',
        () async {
      final invoice = await save('Sales Invoice', '', {
        'customer': 'CUST-1',
        'posting_date': '2026-07-11',
      }, children: {
        'items': [
          {'item': 'WIDGET', 'qty': 2},
        ],
      });
      final saved = await engine.fetch('Sales Invoice', invoice.id);
      expect(asNum(saved!.children['items']![0].payload['rate']), 100);
      expect(saved.payload['price_list'], isNull); // no list involved
    });
  });

  group('DiscountInterceptor', () {
    test('line percent derives rate from the captured base, idempotently',
        () async {
      final invoice = await save('Sales Invoice', '', {
        'customer': 'CUST-1',
        'posting_date': '2026-07-11',
      }, children: {
        'items': [
          {'item': 'WIDGET', 'qty': 2, 'rate': 100, 'discount_percent': 10},
        ],
      });
      var saved = await engine.fetch('Sales Invoice', invoice.id);
      var line = saved!.children['items']![0];
      expect(asNum(line.payload['price_list_rate']), 100); // base captured
      expect(asNum(line.payload['rate']), 90);
      expect(asNum(line.payload['amount']), 180);
      expect(asNum(saved.payload['grand_total']), 180);

      // Re-saving must not compound the discount.
      await engine.save(saved, roles);
      saved = await engine.fetch('Sales Invoice', invoice.id);
      expect(asNum(saved!.children['items']![0].payload['rate']), 90);

      // Zeroing the discount restores the base exactly.
      saved.children['items']![0].payload['discount_percent'] = 0;
      await engine.save(saved, roles);
      saved = await engine.fetch('Sales Invoice', invoice.id);
      expect(asNum(saved!.children['items']![0].payload['rate']), 100);
    });

    test('document percent compounds with line percents', () async {
      final invoice = await save('Sales Invoice', '', {
        'customer': 'CUST-1',
        'posting_date': '2026-07-11',
        'discount_percent': 50,
      }, children: {
        'items': [
          {'item': 'WIDGET', 'qty': 1, 'rate': 100, 'discount_percent': 10},
          {'item': 'WIDGET', 'qty': 1, 'rate': 200},
        ],
      });
      final saved = await engine.fetch('Sales Invoice', invoice.id);
      final lines = saved!.children['items']!;
      expect(asNum(lines[0].payload['rate']), 45); // 100 x .9 x .5
      expect(asNum(lines[1].payload['rate']), 100); // 200 x .5
      expect(asNum(saved.payload['total']), 145);
    });

    test('document amount-off scales lines so totals stay consistent',
        () async {
      final invoice = await save('Sales Invoice', '', {
        'customer': 'CUST-1',
        'posting_date': '2026-07-11',
        'discount_amount': 30,
      }, children: {
        'items': [
          {'item': 'WIDGET', 'qty': 1, 'rate': 100},
          {'item': 'WIDGET', 'qty': 1, 'rate': 200},
        ],
      });
      final saved = await engine.fetch('Sales Invoice', invoice.id);
      final lines = saved!.children['items']!;
      // 300 net − 30 → scale 0.9 on every line.
      expect(asNum(lines[0].payload['rate']), closeTo(90, 1e-9));
      expect(asNum(lines[1].payload['rate']), closeTo(180, 1e-9));
      expect(asNum(saved.payload['total']), closeTo(270, 1e-9));
      // The invariant the Team backend enforces: total == sum of amounts.
      num sum = 0;
      for (final l in lines) {
        sum += asNum(l.payload['amount']);
      }
      expect(asNum(saved.payload['total']), closeTo(sum, 1e-9));
    });

    test('discount applies before VAT: the taxable base shrinks', () async {
      await save('Tax Code', 'VAT18', {
        'tax_code_name': 'VAT 18', 'tax_type': 'VAT', 'rate': 18, 'enabled': 1,
      });
      final invoice = await save('Sales Invoice', '', {
        'customer': 'CUST-1',
        'posting_date': '2026-07-11',
        'discount_percent': 10,
      }, children: {
        'items': [
          {'item': 'WIDGET', 'qty': 1, 'rate': 100, 'tax_code': 'VAT18'},
        ],
      });
      final saved = await engine.fetch('Sales Invoice', invoice.id);
      expect(asNum(saved!.payload['total']), 90);
      expect(asNum(saved.payload['tax_total']), closeTo(16.2, 1e-9));
      expect(asNum(saved.payload['grand_total']), closeTo(106.2, 1e-9));
    });
  });
}
