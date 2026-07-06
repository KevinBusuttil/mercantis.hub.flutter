import 'dart:convert';

import 'package:http/http.dart' as http;

import 'channel_order_csv_importer.dart';

/// WooCommerce REST client (Phase 5, second channel): polls the store's
/// orders endpoint and normalises them into the same [ParsedChannelOrder]
/// shape the CSV channel produces — so staging, SKU mapping, customer
/// dedup and posting are shared, and the connector stays a thin fetch+map.
///
/// Auth is WooCommerce's query-string key pair (read permission suffices);
/// polling asks for paid-ish orders (`processing` + `completed`) created
/// after the last poll. Staging is idempotent, so overlap is harmless.
class WooCommerceChannelClient {
  WooCommerceChannelClient({
    required this.storeUrl,
    required this.consumerKey,
    required this.consumerSecret,
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String storeUrl;
  final String consumerKey;
  final String consumerSecret;
  final http.Client _client;

  /// Fetches orders created after [after] (ISO 8601; null = everything the
  /// page holds), oldest first.
  Future<List<ParsedChannelOrder>> fetchOrders({
    String? after,
    int perPage = 50,
  }) async {
    final base = Uri.parse(storeUrl.trim());
    final path = '${base.path.replaceAll(RegExp(r'/+$'), '')}'
        '/wp-json/wc/v3/orders';
    final uri = base.replace(path: path, queryParameters: {
      'consumer_key': consumerKey,
      'consumer_secret': consumerSecret,
      'status': 'processing,completed',
      'per_page': '$perPage',
      'orderby': 'date',
      'order': 'asc',
      if (after != null && after.isNotEmpty) 'after': after,
    });

    final res = await _client.get(uri);
    if (res.statusCode != 200) {
      throw StateError('WooCommerce returned HTTP ${res.statusCode} — check '
          'the store URL and API keys.');
    }
    final data = jsonDecode(res.body);
    if (data is! List) {
      throw StateError('WooCommerce returned an unexpected payload '
          '(not an order list).');
    }
    return [
      for (final raw in data)
        if (raw is Map<String, dynamic>) _order(raw),
    ].where((o) => o.lines.isNotEmpty).toList();
  }

  ParsedChannelOrder _order(Map<String, dynamic> o) {
    final billing = o['billing'];
    String? name, email;
    if (billing is Map) {
      name = '${billing['first_name'] ?? ''} ${billing['last_name'] ?? ''}'
          .trim();
      if (name.isEmpty) name = null;
      final e = '${billing['email'] ?? ''}'.trim();
      email = e.isEmpty ? null : e;
    }
    final date = '${o['date_created'] ?? ''}';
    final lineItems = o['line_items'];
    return ParsedChannelOrder(
      externalId: '${o['number'] ?? o['id']}',
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
    // Unit price straight from Woo; some payloads omit it, so fall back to
    // the line total spread over the quantity.
    var rate = _num(li['price']);
    if (rate == 0 && qty > 0) rate = _num(li['total']) / qty;
    final sku = '${li['sku'] ?? ''}'.trim();
    return ParsedChannelOrderLine(
      // No SKU maintained in the store → a stable product-id surrogate the
      // owner maps once under Channel Products.
      sku: sku.isNotEmpty ? sku : 'WOO-${li['product_id']}',
      qty: qty == 0 ? 1 : qty,
      rate: rate,
      description: '${li['name'] ?? ''}'.trim().isEmpty ? null : '${li['name']}',
    );
  }

  static num _num(dynamic v) =>
      v is num ? v : num.tryParse('$v'.trim()) ?? 0;
}
