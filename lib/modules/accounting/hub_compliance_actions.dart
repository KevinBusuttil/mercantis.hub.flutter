import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

import '../../ledger/ledger_values.dart';
import 'tax_return_builder.dart';

/// Wires the compliance suite (H2) into the document command bar (HU1): a
/// "Prepare return" action on a `Tax Filing` that folds the period's
/// `Tax Transaction`s into the filing's output/input/net tax, taxable bases and
/// numbered return boxes via [TaxReturnService], then reopens the filing so the
/// computed figures show. Contributed through the core
/// [documentActionRegistryProvider] seam (alongside the H3 conversion actions).
void registerHubComplianceActions(WidgetRef ref) {
  ref.read(documentActionRegistryProvider).register(hubComplianceActionsFor);
}

/// The compliance actions for [doc]. Pure and synchronous — exposed for tests;
/// registered via [registerHubComplianceActions]. Offered only on a saved
/// `Tax Filing` (it needs an id to compute against).
List<DocumentAction> hubComplianceActionsFor(Document doc, DocType docType) {
  if (docType.id != 'Tax Filing' || doc.id.isEmpty) return const [];
  return const [
    DocumentAction(
      id: 'tax-filing-prepare',
      label: 'Prepare return',
      icon: Icons.calculate_outlined,
      invoke: _prepareTaxReturn,
    ),
  ];
}

Future<void> _prepareTaxReturn(
    BuildContext context, WidgetRef ref, Document doc) async {
  // Capture router + messenger before the async gap so navigation never touches
  // a BuildContext across it.
  final router = GoRouter.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final engine = await ref.read(documentEngineProvider.future);
  final roles = ref.read(currentUserProvider).roles;
  try {
    final prepared =
        await TaxReturnService(engine: engine, roles: roles).prepare(doc.id);
    messenger.showSnackBar(SnackBar(
      content: Text('Tax return prepared — net tax due '
          '${asNum(prepared.payload['net_tax']).toStringAsFixed(2)}'),
    ));
    router.go('/form/${prepared.docType}/${prepared.id}');
  } catch (e) {
    messenger.showSnackBar(SnackBar(
      content: Text(e is DocumentEngineError ? e.humanMessage : '$e'),
    ));
  }
}
