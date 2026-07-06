import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

/// The audit trail (Phase 8): who changed what, when — read from the
/// change history the engine has always written. Optionally scoped to one
/// document (`?docType=…&id=…`); unscoped it shows the most recent changes
/// across the whole book, newest first.
final _auditEntriesProvider = FutureProvider.autoDispose
    .family<List<AuditLogEntry>, ({String? docType, String? documentId})>(
        (ref, scope) async {
  final db = await ref.watch(mercantisDatabaseProvider.future);
  return AuditLogReader(db.db).entries(
    docType: scope.docType,
    documentId: scope.documentId,
    limit: 200,
  );
});

class AuditTrailScreen extends ConsumerWidget {
  const AuditTrailScreen({super.key, this.docType, this.documentId});

  final String? docType;
  final String? documentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref
        .watch(_auditEntriesProvider((docType: docType, documentId: documentId)));
    final theme = Theme.of(context);
    final scoped = documentId != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(scoped ? 'History — $documentId' : 'Audit trail'),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load history: $e')),
        data: (entries) {
          if (entries.isEmpty) {
            return const Center(child: Text('No recorded changes yet.'));
          }
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: entries.length,
            itemBuilder: (context, i) {
              final e = entries[i];
              final when = e.timestamp.toLocal().toString().split('.').first;
              return Card(
                child: ExpansionTile(
                  leading: Icon(switch (e.action) {
                    'created' => Icons.add_circle_outline,
                    'updated' => Icons.edit_outlined,
                    _ => Icons.history,
                  }),
                  title: Text(scoped
                      ? '${e.action} · $when'
                      : '${e.docType} ${e.documentId} · ${e.action}'),
                  subtitle: Text(
                      '$when · by ${e.userId.isEmpty ? 'unknown' : e.userId}'
                      '${e.deviceId.isEmpty ? '' : ' on ${e.deviceId}'}'),
                  onExpansionChanged: null,
                  children: [
                    if (e.diffs.isEmpty)
                      const ListTile(
                          dense: true,
                          title: Text('No field changes recorded '
                              '(creation or lifecycle action).'))
                    else
                      for (final d in e.diffs)
                        ListTile(
                          dense: true,
                          title: Text(d.fieldKey),
                          subtitle: Text(
                              '${d.oldValue ?? '—'}  →  ${d.newValue ?? '—'}',
                              style: theme.textTheme.bodySmall),
                        ),
                    if (!scoped)
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () => context
                              .go('/form/${e.docType}/${e.documentId}'),
                          child: const Text('Open document'),
                        ),
                      ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
