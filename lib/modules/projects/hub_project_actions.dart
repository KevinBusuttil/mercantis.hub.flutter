import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

import '../../ledger/ledger_values.dart';
import 'project_billing.dart';

/// Project actions (Phase 6): turn an accepted quotation into a Project, and
/// turn a Project's unbilled billable time + expenses into a draft invoice.
void registerHubProjectActions(WidgetRef ref) {
  ref.read(documentActionRegistryProvider).register(hubProjectActionsFor);
}

/// Pure and synchronous — exposed for tests.
List<DocumentAction> hubProjectActionsFor(Document doc, DocType docType) {
  switch (docType.id) {
    case 'Quotation':
      if (doc.id.isEmpty || doc.docStatus != 1) return const [];
      return const [
        DocumentAction(
          id: 'quotation-to-project',
          label: 'Create Project',
          icon: Icons.work_outline,
          invoke: _quotationToProject,
        ),
      ];
    case 'Project':
      if (doc.id.isEmpty) return const [];
      return const [
        DocumentAction(
          id: 'project-bill',
          label: 'Bill project',
          icon: Icons.receipt_long_outlined,
          invoke: _billProject,
        ),
      ];
    default:
      return const [];
  }
}

const _systemRoles = {'System Manager'};

Future<void> _quotationToProject(
    BuildContext context, WidgetRef ref, Document doc) async {
  final engine = await ref.read(documentEngineProvider.future);
  final customer = asNonEmpty(doc.payload['customer']);
  final draft = Document(id: '', docType: 'Project', payload: {
    'project_name':
        'Work for ${customer ?? 'customer'} (${doc.id})',
    if (customer != null) 'customer': customer,
    'status': 'Open',
    'start_date': DateTime.now().toIso8601String().split('T').first,
    'quotation': doc.id,
  });
  final saved = await engine.save(draft, _systemRoles);
  if (context.mounted) context.go('/form/Project/${saved.id}');
}

Future<void> _billProject(
    BuildContext context, WidgetRef ref, Document doc) async {
  final messenger = ScaffoldMessenger.of(context);
  final engine = await ref.read(documentEngineProvider.future);
  try {
    final invoice = await ProjectBilling(engine: engine).createInvoice(
      doc.id,
      postingDate: DateTime.now().toIso8601String().split('T').first,
    );
    if (invoice == null) {
      messenger.showSnackBar(const SnackBar(
          content: Text('Nothing unbilled — log billable time or expenses '
              'against this project first.')));
      return;
    }
    if (context.mounted) context.go('/form/Sales Invoice/${invoice.id}');
  } catch (e) {
    messenger.showSnackBar(SnackBar(
        content: Text(e is StateError ? e.message : '$e')));
  }
}
