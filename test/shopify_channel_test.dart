import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_hub_app/manifest/hub_manifest.dart';
import 'package:mercantis_hub_app/modules/channels/channel_import_service.dart';
import 'package:mercantis_hub_app/modules/channels/shopify_client.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Shopify connector (Phase 5, third channel): the client normalises the
/// Admin REST orders payload into the shared ParsedChannelOrder shape and
/// polling stages idempotently through the same pipeline as CSV/Woo.
void main() {
  final sampleOrders = jsonEncode({
    'orders': [
      {
        'id': 5551,
        'name': '#1001',
        'created_at': '2026-07-06T10:15:30-04:00',
        'email': 'jane@example.com',
        'customer': {'first_name': 'Jane', 'last_name': 'Doe'},
        'line_items': [
          {'id': 1, 'variant_id': 991, 'sku': 'WIDGET', 'title': 'Widget', 'quantity': 2, 'price': '12.00'},
          {'id': 2, 'variant_id': 992, 'sku': '', 'title': 'Mystery box', 'quantity': 1, 'price': '9.90'},
        ],
      },
    ],
  });

  group('ShopifyChannelClient', () {
    test('builds the authed orders URL and normalises the payload', () async {
      http.Request? seen;
      final client = ShopifyChannelClient(
        storeUrl: 'https://acme.myshopify.com/',
        accessToken: 'shpat_test',
        client: MockClient((req) async {
          seen = req;
          return http.Response(sampleOrders, 200);
        }),
      );

      final orders = await client.fetchOrders(after: '2026-07-01T00:00:00Z');
      expect(seen!.url.path, '/admin/api/2024-01/orders.json');
      expect(seen!.headers['X-Shopify-Access-Token'], 'shpat_test');
      expect(seen!.url.queryParameters['financial_status'], 'paid');
      expect(seen!.url.queryParameters['created_at_min'],
          '2026-07-01T00:00:00Z');

      final order = orders.single;
      expect(order.externalId, '1001'); // '#' stripped from Shopify's name
      expect(order.orderDate, '2026-07-06');
      expect(order.customerName, 'Jane Doe');
      expect(order.customerEmail, 'jane@example.com');
      expect(order.lines[0].sku, 'WIDGET');
      expect(order.lines[0].rate, 12);
      // No store SKU → stable variant-id surrogate.
      expect(order.lines[1].sku, 'SHOP-992');
      expect(order.lines[1].rate, 9.9);
    });

    test('a non-200 response fails loudly', () {
      final client = ShopifyChannelClient(
        storeUrl: 'https://acme.myshopify.com',
        accessToken: 'bad',
        client: MockClient((_) async => http.Response('denied', 401)),
      );
      expect(client.fetchOrders(), throwsStateError);
    });
  });

  group('pollShopify (engine)', () {
    setUpAll(sqfliteFfiInit);
    late MercantisDatabase db;
    late DocumentEngine engine;
    late ChannelImportService service;
    late String channelId;
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
      service = ChannelImportService(engine: engine);
      final channel = await engine.save(
          Document(id: '', docType: 'Sales Channel', payload: {
            'channel_name': 'Shopify shop',
            'channel_type': 'Shopify',
            'store_url': 'https://acme.myshopify.com',
            'consumer_secret': 'shpat_test',
          }),
          roles);
      channelId = channel.id;
    });

    tearDown(() async => db.close());

    test('poll stages orders once and advances the watermark', () async {
      final mock = MockClient((_) async => http.Response(sampleOrders, 200));
      final first =
          await service.pollShopify(channelId: channelId, httpClient: mock);
      expect(first.imported, 1);
      final again =
          await service.pollShopify(channelId: channelId, httpClient: mock);
      expect(again.imported, 0);
      expect(again.duplicates, 1);

      final channel = await engine.fetch('Sales Channel', channelId);
      expect('${channel!.payload['last_polled_at']}', isNotEmpty);
      final logs = await engine.list('Channel Sync Log',
          filters: {'channel': channelId}, userRoles: roles);
      expect(logs.every((l) => l.payload['run_type'] == 'Shopify Poll'),
          isTrue);
    });

    test('a WooCommerce channel cannot be polled as Shopify', () async {
      final woo = await engine.save(
          Document(id: '', docType: 'Sales Channel', payload: {
            'channel_name': 'Woo', 'channel_type': 'WooCommerce',
          }),
          roles);
      await expectLater(
        service.pollShopify(
            channelId: woo.id,
            httpClient: MockClient((_) async => http.Response('{}', 200))),
        throwsStateError,
      );
    });
  });
}
