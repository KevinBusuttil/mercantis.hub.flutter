import 'dart:convert';

import 'package:http/http.dart' as http;

import 'channel_order_csv_importer.dart';

/// Shopify Admin REST client (Phase 5, third channel): polls the store's
/// orders endpoint and normalises them into the same [ParsedChannelOrder]
/// shape the CSV and WooCommerce channels produce — staging, SKU mapping,
/// customer dedup and posting are all shared.
///
/// Auth is a custom-app Admin API access token (Shopify admin → Settings →
/// Apps → Develop apps; scope `read_orders`), sent as
/// `X-Shopify-Access-Token`. Polling asks for paid orders created after the
/// last poll; staging is idempotent, so overlap is harmless.
class ShopifyChannelClient {
  ShopifyChannelClient({
    required this.storeUrl,
    required this.accessToken,
    http.Client? client,
    this.apiVersion = '2024-01',
  }) : _client = client ?? http.Client();

  /// e.g. `https://your-shop.myshopify.com`
  final String storeUrl;
  final String accessToken;
  final String apiVersion;
  final http.Client _client;

  Future<List<ParsedChannelOrder>> fetchOrders({
    String? after,
    int limit = 50,
  }) async {
    final base = Uri.parse(storeUrl.trim());
    final path = '${base.path.replaceAll(RegExp(r'/+$'), '')}'
        '/admin/api/$apiVersion/orders.json';
    final uri = base.replace(path: path, queryParameters: {
      'status': 'any',
      'financial_status': 'paid',
      'limit': '$limit',
      'order': 'created_at asc',
      if (after != null && after.isNotEmpty) 'created_at_min': after,
    });

    final res = await _client
        .get(uri, headers: {'X-Shopify-Access-Token': accessToken});
    if (res.statusCode != 200) {
      throw StateError('Shopify returned HTTP ${res.statusCode} — check the '
          'store URL and the Admin API access token (scope read_orders).');
    }
    final data = jsonDecode(res.body);
    final orders = data is Map<String, dynamic> ? data['orders'] : null;
    if (orders is! List) {
      throw StateError('Shopify returned an unexpected payload '
          '(no order list).');
    }
    return [
      for (final raw in orders)
        if (raw is Map<String, dynamic>) _order(raw),
    ].where((o) => o.lines.isNotEmpty).toList();
  }

  ParsedChannelOrder _order(Map<String, dynamic> o) {
    String? name, email;
    final customer = o['customer'];
    if (customer is Map) {
      name = '${customer['first_name'] ?? ''} ${customer['last_name'] ?? ''}'
          .trim();
      if (name.isEmpty) name = null;
    }
    final e = '${o['email'] ?? ''}'.trim();
    email = e.isEmpty ? null : e;
    final date = '${o['created_at'] ?? ''}';
    final lineItems = o['line_items'];
    return ParsedChannelOrder(
      // `name` is Shopify's human order number (#1001); `id` the numeric id.
      externalId: '${o['name'] ?? o['id']}'.replaceAll('#', ''),
      orderDate: date.isEmpty ? null : date.split('T').first,
      customerName: name,
      customerEmail: email,
      lines: [
        if (lineItems is List)
          for (final li in lineItems)
            if (li is Map<String, dynamic>) _line(li),
      ],
    );
  }

  ParsedChannelOrderLine _line(Map<String, dynamic> li) {
    final qty = _num(li['quantity']);
    final rate = _num(li['price']);
    final sku = '${li['sku'] ?? ''}'.trim();
    return ParsedChannelOrderLine(
      // No SKU maintained in the store → a stable variant-id surrogate the
      // owner maps once under Channel Products.
      sku: sku.isNotEmpty ? sku : 'SHOP-${li['variant_id'] ?? li['id']}',
      qty: qty == 0 ? 1 : qty,
      rate: rate,
      description:
          '${li['title'] ?? ''}'.trim().isEmpty ? null : '${li['title']}',
    );
  }

  static num _num(dynamic v) => v is num ? v : num.tryParse('$v'.trim()) ?? 0;
}
