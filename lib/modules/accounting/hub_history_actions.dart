import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

/// A "History" command-bar action on every saved document (Phase 8):
/// opens that record's audit trail — every save with who/when and the
/// field-level diffs the engine has always captured.
void registerHubHistoryActions(WidgetRef ref) {
  ref.read(documentActionRegistryProvider).register(hubHistoryActionsFor);
}

/// Pure and synchronous — exposed for tests.
List<DocumentAction> hubHistoryActionsFor(Document doc, DocType docType) {
  if (doc.id.isEmpty) return const [];
  return const [
    DocumentAction(
      id: 'document-history',
      label: 'History',
      icon: Icons.history,
      invoke: _openHistory,
    ),
  ];
}

Future<void> _openHistory(
    BuildContext context, WidgetRef ref, Document doc) async {
  context.go('/w/finance/audit-trail'
      '?docType=${Uri.encodeQueryComponent(doc.docType)}'
      '&id=${Uri.encodeQueryComponent(doc.id)}');
}
