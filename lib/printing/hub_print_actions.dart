import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

import 'hub_print_formats.dart';

/// Wires a "Print preview" command-bar action (HU2) onto every saved document:
/// it renders the record through the core [PrintService] using the Hub's
/// default [PrintFormat] and shows the plain-text output in a dialog — the
/// preview half of the print designer (which will let the format be edited).
/// Registered via the core [documentActionRegistryProvider].
void registerHubPrintActions(WidgetRef ref) {
  ref.read(documentActionRegistryProvider).register(hubPrintActionsFor);
}

/// Pure/synchronous — exposed for tests. Offered on any saved document.
List<DocumentAction> hubPrintActionsFor(Document doc, DocType docType) {
  if (doc.id.isEmpty) return const [];
  return const [
    DocumentAction(
      id: 'print-preview',
      label: 'Print preview',
      icon: Icons.preview_outlined,
      invoke: _printPreview,
    ),
  ];
}

Future<void> _printPreview(
    BuildContext context, WidgetRef ref, Document doc) async {
  final messenger = ScaffoldMessenger.of(context);
  final engine = await ref.read(documentEngineProvider.future);
  final registry = await ref.read(metadataRegistryProvider.future);
  final meta = await registry.get(doc.docType);
  final fetched = await engine.fetch(doc.docType, doc.id);
  if (meta == null || fetched == null) {
    messenger.showSnackBar(const SnackBar(content: Text('Nothing to preview')));
    return;
  }
  final format = hubDefaultPrintFormat(meta);
  final service = ref.read(printServiceProvider)..registerFormat(format);
  final result = await service.render(
    formatId: format.id,
    document: fetched,
    kind: PrintOutputKind.plainText,
  );
  final text = utf8.decode(result.bytes);
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('Print preview'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: SelectableText(text,
              style: const TextStyle(fontFamily: 'monospace')),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close')),
      ],
    ),
  );
}
