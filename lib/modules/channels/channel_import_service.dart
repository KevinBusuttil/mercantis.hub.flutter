import 'package:mercantis_core/mercantis_core.dart';

import '../../ledger/ledger_values.dart';
import 'channel_order_csv_importer.dart';

/// The outcome of one CSV import run.
class ChannelImportResult {
  const ChannelImportResult({
    required this.imported,
    required this.duplicates,
    required this.skipped,
    required this.batchId,
  });

  final int imported;
  final int duplicates;
  final int skipped;
  final String batchId;
}

/// The outcome of one posting run over staged orders.
class ChannelPostResult {
  const ChannelPostResult({required this.posted, required this.failed});

  final int posted;
  final int failed;
}

/// Sales-channel order flow (Phase 5), CSV channel first:
///
///   import → `Channel Order` staging rows → post → official Sales Invoice.
///
/// Import is idempotent: a Channel Order's id is derived from
/// (channel, order reference), so re-importing the same export creates
/// nothing new. Posting maps channel SKUs to Items (`Channel Product` first,
/// then an Item with the SKU as its id), finds-or-creates the customer by
/// email (deterministically, so two orders from the same buyer share one
/// Customer), and raises a Sales Invoice with `update_stock` when the channel
/// ships from a warehouse — so stock and COGS post through the same ledger
/// spine as any other sale. Invoices stay drafts unless the channel opts into
/// auto-submit; the staging row records where it went (or why it failed).
class ChannelImportService {
  ChannelImportService({
    required this.engine,
    this.roles = const {'System Manager'},
  });

  final DocumentEngine engine;
  final Set<String> roles;

  /// Parses [csv] and stages one `Channel Order` per storefront order.
  Future<ChannelImportResult> importCsv({
    required String channelId,
    required String csv,
  }) async {
    final channel = await engine.fetch('Sales Channel', channelId);
    if (channel == null) {
      throw StateError('Sales Channel $channelId does not exist.');
    }
    final parsed = ChannelOrderCsvImporter.parse(csv);
    final batchId = 'CHIMP-${DateTime.now().millisecondsSinceEpoch}';

    var imported = 0;
    var duplicates = 0;
    for (final order in parsed.orders) {
      final id = 'CHO-${_fnv1a('$channelId|${order.externalId}')}';
      if (await engine.fetch('Channel Order', id) != null) {
        duplicates++;
        continue;
      }
      final doc = Document(id: id, docType: 'Channel Order', payload: {
        'channel': channelId,
        'external_order_id': order.externalId,
        if (order.orderDate != null) 'order_date': order.orderDate,
        if (order.customerName != null) 'customer_name': order.customerName,
        if (order.customerEmail != null) 'customer_email': order.customerEmail,
        'status': 'Imported',
        'gross_total': round2(order.grossTotal),
        'import_batch': batchId,
      });
      doc.children['lines'] = [
        for (var i = 0; i < order.lines.length; i++)
          ChildRow(
            id: '', parentId: '', parentDocType: 'Channel Order',
            tableName: 'lines', rowIndex: i,
            payload: {
              'sku': order.lines[i].sku,
              if (order.lines[i].description != null)
                'description': order.lines[i].description,
              'qty': order.lines[i].qty,
              'rate': order.lines[i].rate,
            },
          ),
      ];
      await engine.save(doc, roles);
      imported++;
    }

    await _log(channelId, 'CSV Import', {
      'imported': imported,
      'duplicates': duplicates,
      'skipped': parsed.skipped,
    });
    return ChannelImportResult(
      imported: imported,
      duplicates: duplicates,
      skipped: parsed.skipped,
      batchId: batchId,
    );
  }

  /// Posts every staged (Imported or previously Failed) order on [channelId].
  /// One bad order doesn't stop the run — it's stamped Failed with the reason
  /// and the rest post.
  Future<ChannelPostResult> postImported({
    required String channelId,
    String? postingDate,
  }) async {
    final orders = await engine.list('Channel Order',
        filters: {'channel': channelId}, userRoles: roles);
    var posted = 0;
    var failed = 0;
    final errors = <String>[];
    for (final order in orders) {
      final status = order.payload['status'];
      if (status != 'Imported' && status != 'Failed') continue;
      try {
        await postOrder(order.id, postingDate: postingDate);
        posted++;
      } catch (e) {
        failed++;
        errors.add('${order.payload['external_order_id']}: $e');
      }
    }
    await _log(channelId, 'Post Orders', {
      'posted': posted,
      'failed': failed,
      if (errors.isNotEmpty) 'notes': errors.take(5).join('\n'),
    });
    return ChannelPostResult(posted: posted, failed: failed);
  }

  /// Posts one staged order as a Sales Invoice. Throws (and stamps the order
  /// Failed) when a SKU is unmapped or no customer can be determined —
  /// nothing half-posts. Already-Posted and Ignored orders are left alone.
  Future<Document?> postOrder(String channelOrderId,
      {String? postingDate}) async {
    final order = await engine.fetch('Channel Order', channelOrderId);
    if (order == null) {
      throw StateError('Channel Order $channelOrderId does not exist.');
    }
    final status = order.payload['status'];
    if (status == 'Posted' || status == 'Ignored') return null;

    try {
      final channel =
          await engine.fetch('Sales Channel', '${order.payload['channel']}');
      if (channel == null) {
        throw StateError('Sales Channel ${order.payload['channel']} is gone.');
      }
      if (isTrue(channel.payload['disabled'])) {
        throw StateError('Sales Channel ${channel.id} is disabled.');
      }
      final invoice = await _buildInvoice(order, channel, postingDate);
      final saved = await engine.save(invoice, roles);
      final official = isTrue(channel.payload['auto_submit'])
          ? await engine.submit(saved, roles)
          : saved;

      order.payload['status'] = 'Posted';
      order.payload['sales_invoice'] = official.id;
      order.payload['error'] = '';
      await engine.save(order, roles);
      return official;
    } catch (e) {
      order.payload['status'] = 'Failed';
      final message = '$e';
      order.payload['error'] =
          message.length > 200 ? message.substring(0, 200) : message;
      await engine.save(order, roles);
      rethrow;
    }
  }

  Future<Document> _buildInvoice(
      Document order, Document channel, String? postingDate) async {
    final warehouse = asNonEmpty(channel.payload['warehouse']);
    final defaultTaxCode = asNonEmpty(channel.payload['tax_code']);
    final customer = await _resolveCustomer(order, channel);

    final invoice = Document(id: '', docType: 'Sales Invoice', payload: {
      'customer': customer,
      'posting_date': asNonEmpty(order.payload['order_date']) ??
          postingDate ??
          DateTime.now().toIso8601String().split('T').first,
      'sales_channel': channel.id,
      if (isTrue(channel.payload['prices_include_tax']))
        'prices_include_tax': 1,
      if (warehouse != null) ...{'update_stock': 1, 'set_warehouse': warehouse},
    });

    final lines = <ChildRow>[];
    for (final line in order.children['lines'] ?? const <ChildRow>[]) {
      final sku = '${line.payload['sku']}';
      final item = await _resolveItem(channel.id, sku);
      lines.add(ChildRow(
        id: '', parentId: '', parentDocType: 'Sales Invoice',
        tableName: 'items', rowIndex: lines.length,
        payload: {
          'item': item,
          'description': asNonEmpty(line.payload['description']) ??
              'Channel order ${order.payload['external_order_id']}',
          'qty': asNum(line.payload['qty']),
          'rate': asNum(line.payload['rate']),
          if (defaultTaxCode != null) 'tax_code': defaultTaxCode,
        },
      ));
    }
    if (lines.isEmpty) {
      throw StateError(
          'Order ${order.payload['external_order_id']} has no lines.');
    }
    invoice.children['items'] = lines;
    return invoice;
  }

  /// Channel Product mapping first; an Item whose id IS the SKU second;
  /// otherwise fail loudly — never guess what was sold.
  Future<String> _resolveItem(String channelId, String sku) async {
    final maps = await engine.list('Channel Product',
        filters: {'channel': channelId, 'channel_sku': sku},
        userRoles: roles);
    if (maps.isNotEmpty) {
      final item = asNonEmpty(maps.first.payload['item']);
      if (item != null) return item;
    }
    if (await engine.fetch('Item', sku) != null) return sku;
    throw StateError('Unmapped SKU "$sku" — map it under Channel Products.');
  }

  /// Finds or creates the buyer. Email is the identity when present (id is
  /// derived from it, so the same buyer across orders and imports is ONE
  /// Customer); otherwise the buyer name; otherwise the channel's default
  /// customer.
  Future<String> _resolveCustomer(Document order, Document channel) async {
    final email =
        asNonEmpty(order.payload['customer_email'])?.toLowerCase().trim();
    final name = asNonEmpty(order.payload['customer_name'])?.trim();
    final key = email ?? name;
    if (key == null) {
      final fallback = asNonEmpty(channel.payload['default_customer']);
      if (fallback != null) return fallback;
      throw StateError(
          'Order ${order.payload['external_order_id']} has no customer '
          'details and the channel has no default customer.');
    }
    final id = 'CUST-CH-${_fnv1a(key)}';
    if (await engine.fetch('Customer', id) == null) {
      await engine.save(
        Document(id: id, docType: 'Customer', payload: {
          'customer_name': name ?? email!,
          'customer_type': 'Individual',
          if (email != null) 'email': email,
          'customer_group': 'Online',
        }),
        roles,
      );
    }
    return id;
  }

  Future<void> _log(
      String channelId, String runType, Map<String, dynamic> counts) async {
    await engine.save(
      Document(id: '', docType: 'Channel Sync Log', payload: {
        'channel': channelId,
        'run_type': runType,
        'run_on': DateTime.now().toIso8601String(),
        ...counts,
      }),
      roles,
    );
  }

  /// FNV-1a 64-bit over [input], hex-encoded — same identity scheme as the
  /// bank statement importer.
  static String _fnv1a(String input) {
    var hash = 0xcbf29ce484222325;
    for (final unit in input.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(16, '0');
  }
}
