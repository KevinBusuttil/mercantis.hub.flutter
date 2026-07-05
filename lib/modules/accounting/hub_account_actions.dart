import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

import '../../ledger/ledger_values.dart';

/// Registers the "Ledger" command-bar action on saved Account records via the
/// core [documentActionRegistryProvider] seam — opening that account's ledger
/// (balance + transactions).
void registerHubAccountActions(WidgetRef ref) {
  ref.read(documentActionRegistryProvider).register(hubAccountActionsFor);
}

/// The actions offered on an Account. "Ledger" appears on a saved, non-group
/// account (group accounts summarise their children and carry no direct
/// postings). Pure/synchronous — exposed for tests; registered via
/// [registerHubAccountActions].
List<DocumentAction> hubAccountActionsFor(Document doc, DocType docType) {
  if (docType.id != 'Account') return const [];
  if (doc.id.isEmpty) return const [];
  if (isTrue(doc.payload['is_group'])) return const [];
  return const [
    DocumentAction(
      id: 'account-ledger',
      label: 'Ledger',
      icon: Icons.receipt_long_outlined,
      invoke: _openLedger,
    ),
  ];
}

Future<void> _openLedger(
    BuildContext context, WidgetRef ref, Document doc) async {
  context.go('/w/finance/account-ledger?account=${Uri.encodeComponent(doc.id)}');
}
