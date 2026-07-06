import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_hub_app/manifest/hub_manifest.dart';
import 'package:mercantis_hub_app/modules/channels/channel_import_service.dart';
import 'package:mercantis_hub_app/modules/channels/woocommerce_client.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// WooCommerce connector (Phase 5, second channel): the client normalises
/// the REST orders payload into the shared ParsedChannelOrder shape; polling
/// stages idempotently through the same pipeline as CSV import and advances
/// the channel's last-polled watermark.
void main() {
  final sampleOrders = jsonEncode([
    {
      'id': 741,
      'number': '741',
      'date_created': '2026-07-04T10:15:30',
      'billing': {
        'first_name': 'Jane',
        'last_name': 'Doe',
        'email': 'jane@example.com',
      },
      'line_items': [
        {'sku': 'WIDGET', 'name': 'Widget', 'quantity': 2, 'price': 12.0, 'total': '24.00', 'product_id': 11},
        {'sku': '', 'name': 'Mystery box', 'quantity': 1, 'price': 0, 'total': '9.90', 'product_id': 42},
      ],
    },
    {
      'id': 742,
      'number': '742',
      'date_created': '2026-07-05T09:00:00',
      'billing': {'first_name': '', 'last_name': '', 'email': ''},
      'line_items': [
        {'sku': 'WIDGET', 'name': 'Widget', 'quantity': 1, 'price': '12.00', 'total': '12.00', 'product_id': 11},
      ],
    },
  ]);

  group('WooCommerceChannelClient', () {
    test('builds the authed orders URL and normalises the payload', () async {
      Uri? requested;
      final client = WooCommerceChannelClient(
        storeUrl: 'https://shop.example.com/',
        consumerKey: 'ck_test',
        consumerSecret: 'cs_test',
        client: MockClient((req) async {
          requested = req.url;
          return http.Response(sampleOrders, 200,
              headers: {'content-type': 'application/json'});
        }),
      );

      final orders = await client.fetchOrders(after: '2026-07-01T00:00:00Z');

      expect(requested!.host, 'shop.example.com');
      expect(requested!.path, '/wp-json/wc/v3/orders');
      expect(requested!.queryParameters['consumer_key'], 'ck_test');
      expect(requested!.queryParameters['consumer_secret'], 'cs_test');
      expect(requested!.queryParameters['status'], 'processing,completed');
      expect(requested!.queryParameters['after'], '2026-07-01T00:00:00Z');

      expect(orders.length, 2);
      final first = orders.first;
      expect(first.externalId, '741');
      expect(first.orderDate, '2026-07-04');
      expect(first.customerName, 'Jane Doe');
      expect(first.customerEmail, 'jane@example.com');
      expect(first.lines.length, 2);
      expect(first.lines[0].sku, 'WIDGET');
      expect(first.lines[0].qty, 2);
      expect(first.lines[0].rate, 12);
      // No SKU in the store → stable product-id surrogate; price omitted →
      // line total spread over quantity.
      expect(first.lines[1].sku, 'WOO-42');
      expect(first.lines[1].rate, 9.9);
      // Blank billing details stay null (channel default customer applies).
      expect(orders.last.customerName, isNull);
      expect(orders.last.customerEmail, isNull);
    });

    test('a non-200 response fails loudly', () {
      final client = WooCommerceChannelClient(
        storeUrl: 'https://shop.example.com',
        consumerKey: 'k',
        consumerSecret: 's',
        client: MockClient((_) async => http.Response('denied', 401)),
      );
      expect(client.fetchOrders(), throwsStateError);
    });
  });

  group('pollWooCommerce (engine)', () {
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
            'channel_name': 'Woo shop',
            'channel_type': 'WooCommerce',
            'store_url': 'https://shop.example.com',
            'consumer_key': 'ck',
            'consumer_secret': 'cs',
          }),
          roles);
      channelId = channel.id;
    });

    tearDown(() async => db.close());

    test('poll stages orders once and advances the watermark', () async {
      final mock = MockClient((_) async => http.Response(sampleOrders, 200));

      final first =
          await service.pollWooCommerce(channelId: channelId, httpClient: mock);
      expect(first.imported, 2);
      expect(first.duplicates, 0);

      // Same orders again (overlapping window) — nothing new is staged.
      final again =
          await service.pollWooCommerce(channelId: channelId, httpClient: mock);
      expect(again.imported, 0);
      expect(again.duplicates, 2);

      final orders = await engine.list('Channel Order',
          filters: {'channel': channelId}, userRoles: roles);
      expect(orders.length, 2);
      final o741 =
          orders.firstWhere((o) => o.payload['external_order_id'] == '741');
      expect(asNum2(o741.payload['gross_total']), 33.9); // 24 + 9.90
      final hydrated = await engine.fetch('Channel Order', o741.id);
      expect(hydrated!.children['lines']!.length, 2);

      final channel = await engine.fetch('Sales Channel', channelId);
      expect('${channel!.payload['last_polled_at']}', isNotEmpty);

      final logs = await engine.list('Channel Sync Log',
          filters: {'channel': channelId}, userRoles: roles);
      expect(logs.every((l) => l.payload['run_type'] == 'WooCommerce Poll'),
          isTrue);
    });

    test('a channel without API config refuses to poll', () async {
      final bare = await engine.save(
          Document(id: '', docType: 'Sales Channel', payload: {
            'channel_name': 'Unconfigured',
            'channel_type': 'WooCommerce',
          }),
          roles);
      await expectLater(
        service.pollWooCommerce(
            channelId: bare.id,
            httpClient: MockClient((_) async => http.Response('[]', 200))),
        throwsStateError,
      );
    });

    test('a CSV channel cannot be polled', () async {
      final csvChannel = await engine.save(
          Document(id: '', docType: 'Sales Channel', payload: {
            'channel_name': 'CSV only',
            'channel_type': 'CSV',
          }),
          roles);
      await expectLater(
        service.pollWooCommerce(
            channelId: csvChannel.id,
            httpClient: MockClient((_) async => http.Response('[]', 200))),
        throwsStateError,
      );
    });

    test('a failed poll does not advance the watermark', () async {
      await expectLater(
        service.pollWooCommerce(
            channelId: channelId,
            httpClient: MockClient((_) async => http.Response('boom', 500))),
        throwsStateError,
      );
      final channel = await engine.fetch('Sales Channel', channelId);
      expect(channel!.payload['last_polled_at'], isNull);
    });
  });
}

num asNum2(dynamic v) => v is num ? v : num.tryParse('$v') ?? 0;
