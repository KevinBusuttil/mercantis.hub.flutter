import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

import 'team_account_client.dart';
import 'team_session.dart';

/// Customer portal links (Team): a "Portal link" action on a Customer that
/// mints a token-scoped, expiring link to their quotes and invoices on
/// portal.atlas.neuradix.app (served by the Team backend).
void registerHubPortalActions(WidgetRef ref) {
  ref.read(documentActionRegistryProvider).register(hubPortalActionsFor);
}

/// Pure and synchronous — exposed for tests. Portal links show on every
/// saved Customer; payment links on every SUBMITTED Sales Invoice.
/// Invoking either without a Team session explains instead of failing
/// (both are Team capabilities).
List<DocumentAction> hubPortalActionsFor(Document doc, DocType docType) {
  switch (docType.id) {
    case 'Customer':
      if (doc.id.isEmpty) return const [];
      return const [
        DocumentAction(
          id: 'customer-portal-link',
          label: 'Portal link',
          icon: Icons.link_outlined,
          invoke: _createPortalLink,
        ),
      ];
    case 'Sales Invoice':
      if (doc.id.isEmpty || doc.docStatus != 1) return const [];
      return const [
        DocumentAction(
          id: 'invoice-pay-link',
          label: 'Payment link',
          icon: Icons.payments_outlined,
          invoke: _createPayLink,
        ),
      ];
    default:
      return const [];
  }
}

Future<void> _createPayLink(
    BuildContext context, WidgetRef ref, Document doc) async {
  final messenger = ScaffoldMessenger.of(context);
  final session = ref.read(teamSessionProvider);
  if (session == null) {
    messenger.showSnackBar(const SnackBar(
        content: Text('Payment links need Atlas Team — connect under '
            'Setup → Atlas Team first.')));
    return;
  }
  try {
    final client = TeamAccountClient(baseUrl: session.baseUrl);
    final link = await client.createPayLink(
      companyId: session.companyId,
      authToken: session.userToken,
      invoiceId: doc.id,
    );
    final url = '${session.baseUrl}${link.urlPath}';
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Payment link'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Anyone with this link can view and pay ${doc.id}. It '
                'always shows the live outstanding amount, and expires '
                '${link.expiresAt.split('T').first}. Card payments post '
                'back automatically as official Payment Entries.'),
            const SizedBox(height: 12),
            SelectableText(url,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: url));
              Navigator.pop(c);
            },
            child: const Text('Copy & close'),
          ),
        ],
      ),
    );
  } catch (e) {
    messenger.showSnackBar(SnackBar(
        content: Text(e is CloudHttpException ? e.message : '$e')));
  }
}

Future<void> _createPortalLink(
    BuildContext context, WidgetRef ref, Document doc) async {
  final messenger = ScaffoldMessenger.of(context);
  final session = ref.read(teamSessionProvider);
  if (session == null) {
    messenger.showSnackBar(const SnackBar(
        content: Text('Portal links need Atlas Team — connect under '
            'Setup → Atlas Team first.')));
    return;
  }
  try {
    final client = TeamAccountClient(baseUrl: session.baseUrl);
    final link = await client.createPortalLink(
      companyId: session.companyId,
      authToken: session.userToken,
      kind: 'customer',
      party: doc.id,
      label: 'Portal for ${doc.payload['customer_name'] ?? doc.id}',
    );
    final url = '${session.baseUrl}${link.urlPath}';
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Customer portal link'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Share this with ${doc.payload['customer_name'] ?? doc.id}. '
                'It shows their quotations and invoices only, and expires '
                '${link.expiresAt.split('T').first}.'),
            const SizedBox(height: 12),
            SelectableText(url,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: url));
              Navigator.pop(c);
            },
            child: const Text('Copy & close'),
          ),
        ],
      ),
    );
  } catch (e) {
    messenger.showSnackBar(SnackBar(
        content: Text(e is CloudHttpException ? e.message : '$e')));
  }
}
