import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

import 'ubl_invoice.dart';

/// S13: an "E-invoice (UBL)" command-bar action on every SUBMITTED Sales
/// Invoice — builds the EN 16931 / PEPPOL BIS 3.0 XML and shows it for
/// copy-out (an Access Point provider takes it from there). Drafts never
/// offer it: an e-invoice is a fiscal document.
void registerHubEInvoiceActions(WidgetRef ref) {
  ref.read(documentActionRegistryProvider).register(hubEInvoiceActionsFor);
}

/// Pure/synchronous — exposed for tests.
List<DocumentAction> hubEInvoiceActionsFor(Document doc, DocType docType) {
  if (docType.id != 'Sales Invoice') return const [];
  if (doc.id.isEmpty || doc.docStatus != 1) return const [];
  return const [
    DocumentAction(
      id: 'einvoice-ubl',
      label: 'E-invoice (UBL)',
      icon: Icons.code,
      invoke: _showUbl,
    ),
  ];
}

Future<void> _showUbl(
    BuildContext context, WidgetRef ref, Document doc) async {
  final messenger = ScaffoldMessenger.of(context);
  final engine = await ref.read(documentEngineProvider.future);
  final String xml;
  try {
    xml = await UblExportService(engine).buildFor(doc.id);
  } catch (e) {
    final text = '$e';
    messenger.showSnackBar(SnackBar(
        content: Text(text.startsWith('Bad state: ')
            ? text.substring('Bad state: '.length)
            : text)));
    return;
  }
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('E-invoice — EN 16931 / UBL 2.1'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: SelectableText(xml,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: xml));
            messenger.showSnackBar(
                const SnackBar(content: Text('XML copied to clipboard.')));
          },
          child: const Text('Copy XML'),
        ),
        TextButton(
            onPressed: () => Navigator.of(c).pop(),
            child: const Text('Close')),
      ],
    ),
  );
}
