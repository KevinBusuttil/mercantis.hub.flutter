import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

import 'hub_document_lineage.dart';

/// Wires the conversion-lineage inspector (HU4) into the document command bar: a
/// "Related" action on any document that takes part in a conversion chain, which
/// opens a sheet of its upstream sources and downstream results — each tappable
/// to jump to that document. Contributed via the core
/// [documentActionRegistryProvider] seam.
void registerHubLineageActions(WidgetRef ref) {
  ref.read(documentActionRegistryProvider).register(hubLineageActionsFor);
}

/// The lineage action for [doc]. Pure/synchronous — exposed for tests. Offered
/// on a saved document whose DocType participates in a conversion chain.
List<DocumentAction> hubLineageActionsFor(Document doc, DocType docType) {
  if (doc.id.isEmpty || !HubDocumentLineage.participates(docType.id)) {
    return const [];
  }
  return const [
    DocumentAction(
      id: 'related-docs',
      label: 'Related',
      icon: Icons.account_tree_outlined,
      invoke: _showRelated,
    ),
  ];
}

Future<void> _showRelated(
    BuildContext context, WidgetRef ref, Document doc) async {
  final messenger = ScaffoldMessenger.of(context);
  final engine = await ref.read(documentEngineProvider.future);
  final roles = ref.read(currentUserProvider).roles;
  final refs = [
    ...HubDocumentLineage.upstream(doc, doc.docType),
    ...await HubDocumentLineage.downstream(engine, doc, doc.docType, roles: roles),
  ];
  if (!context.mounted) return;
  if (refs.isEmpty) {
    messenger.showSnackBar(
        const SnackBar(content: Text('No related documents')));
    return;
  }
  final router = GoRouter.of(context);
  await showModalBottomSheet<void>(
    context: context,
    builder: (sheet) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          const ListTile(
            title: Text('Related documents',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          for (final r in refs)
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: Text('${r.docType} · ${r.id}'),
              subtitle: Text(r.relation),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.of(sheet).pop();
                router.go('/form/${r.docType}/${r.id}');
              },
            ),
        ],
      ),
    ),
  );
}
