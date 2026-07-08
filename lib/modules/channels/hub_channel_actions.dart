import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

import 'channel_import_service.dart';

/// Sales-channel actions (Phase 5): import a storefront CSV into staged
/// Channel Orders, and post staged orders as official Sales Invoices.
void registerHubChannelActions(WidgetRef ref) {
  ref.read(documentActionRegistryProvider).register(hubChannelActionsFor);
}

/// Pure and synchronous — exposed for tests.
List<DocumentAction> hubChannelActionsFor(Document doc, DocType docType) {
  switch (docType.id) {
    case 'Sales Channel':
      if (doc.id.isEmpty) return const [];
      return [
        const DocumentAction(
          id: 'channel-import-csv',
          label: 'Import orders (CSV)',
          icon: Icons.upload_file_outlined,
          invoke: _importCsv,
        ),
        if (doc.payload['channel_type'] == 'WooCommerce')
          const DocumentAction(
            id: 'channel-poll-woo',
            label: 'Fetch orders (WooCommerce)',
            icon: Icons.cloud_download_outlined,
            invoke: _pollWoo,
          ),
        if (doc.payload['channel_type'] == 'Shopify')
          const DocumentAction(
            id: 'channel-poll-shopify',
            label: 'Fetch orders (Shopify)',
            icon: Icons.cloud_download_outlined,
            invoke: _pollShopify,
          ),
        const DocumentAction(
          id: 'channel-post-orders',
          label: 'Post imported orders',
          icon: Icons.receipt_long_outlined,
          invoke: _postImported,
        ),
      ];
    case 'Channel Order':
      final status = doc.payload['status'];
      if (doc.id.isEmpty || (status != 'Imported' && status != 'Failed')) {
        return const [];
      }
      return const [
        DocumentAction(
          id: 'channel-order-post',
          label: 'Post to invoice',
          icon: Icons.receipt_long_outlined,
          invoke: _postOrder,
        ),
        DocumentAction(
          id: 'channel-order-ignore',
          label: 'Ignore order',
          icon: Icons.visibility_off_outlined,
          invoke: _ignoreOrder,
        ),
      ];
    default:
      return const [];
  }
}

const _systemRoles = {'System Manager'};

Future<void> _importCsv(
    BuildContext context, WidgetRef ref, Document doc) async {
  final messenger = ScaffoldMessenger.of(context);
  final controller = TextEditingController();
  final csv = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Import orders into ${doc.payload['channel_name']}'),
      content: SizedBox(
        width: 560,
        child: TextField(
          controller: controller,
          maxLines: 12,
          decoration: const InputDecoration(
            hintText: 'Paste the storefront\'s order-lines CSV export here — '
                'columns for order reference, SKU, quantity and price '
                '(date, customer name and email are picked up when present).',
            border: OutlineInputBorder(),
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
        FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('Import')),
      ],
    ),
  );
  if (csv == null || csv.trim().isEmpty) return;
  final engine = await ref.read(documentEngineProvider.future);
  try {
    final result = await ChannelImportService(engine: engine)
        .importCsv(channelId: doc.id, csv: csv);
    messenger.showSnackBar(SnackBar(
        content: Text('${result.imported} order(s) staged, '
            '${result.duplicates} already imported, '
            '${result.skipped} unreadable row(s).')));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('$e')));
  }
}

Future<void> _pollWoo(
    BuildContext context, WidgetRef ref, Document doc) async {
  final messenger = ScaffoldMessenger.of(context);
  final engine = await ref.read(documentEngineProvider.future);
  try {
    final result = await ChannelImportService(engine: engine)
        .pollWooCommerce(channelId: doc.id);
    messenger.showSnackBar(SnackBar(
        content: Text('${result.imported} order(s) staged, '
            '${result.duplicates} already imported.')));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('$e')));
  }
}

Future<void> _pollShopify(
    BuildContext context, WidgetRef ref, Document doc) async {
  final messenger = ScaffoldMessenger.of(context);
  final engine = await ref.read(documentEngineProvider.future);
  try {
    final result = await ChannelImportService(engine: engine)
        .pollShopify(channelId: doc.id);
    messenger.showSnackBar(SnackBar(
        content: Text('${result.imported} order(s) staged, '
            '${result.duplicates} already imported.')));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('$e')));
  }
}

Future<void> _postImported(
    BuildContext context, WidgetRef ref, Document doc) async {
  final messenger = ScaffoldMessenger.of(context);
  final engine = await ref.read(documentEngineProvider.future);
  final result = await ChannelImportService(engine: engine)
      .postImported(channelId: doc.id);
  messenger.showSnackBar(SnackBar(
      content: Text(result.posted == 0 && result.failed == 0
          ? 'Nothing staged — import a CSV first.'
          : '${result.posted} invoice(s) created'
              '${result.failed > 0 ? ', ${result.failed} order(s) failed '
                  '(see the order\'s Last Error)' : ''}.')));
}

Future<void> _postOrder(
    BuildContext context, WidgetRef ref, Document doc) async {
  final messenger = ScaffoldMessenger.of(context);
  final engine = await ref.read(documentEngineProvider.future);
  try {
    final invoice =
        await ChannelImportService(engine: engine).postOrder(doc.id);
    if (invoice != null && context.mounted) {
      context.go('/form/Sales Invoice/${invoice.id}');
    }
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('$e')));
  }
}

Future<void> _ignoreOrder(
    BuildContext context, WidgetRef ref, Document doc) async {
  final engine = await ref.read(documentEngineProvider.future);
  doc.payload['status'] = 'Ignored';
  await engine.save(doc, _systemRoles);
  if (context.mounted) context.go('/list/Channel Order');
}
