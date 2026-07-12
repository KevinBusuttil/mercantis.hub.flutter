import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

import '../sync/conflict_providers.dart';

/// Sync conflicts (Phase 0.10): documents where a remote edit and a local
/// edit collided under a version-checked policy. Each row shows both sides
/// and resolves whole-document — keep mine (re-push the local version) or
/// take theirs (apply the remote candidate, abandoning un-pushed local
/// edits). No silent winner: nothing changes until the user chooses.
class ConflictsScreen extends ConsumerWidget {
  const ConflictsScreen({super.key});

  Future<void> _resolve(
    BuildContext context,
    WidgetRef ref,
    SyncConflict conflict, {
    required bool keepMine,
  }) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(keepMine ? 'Keep your version?' : 'Take their version?'),
        content: Text(keepMine
            ? 'Your copy of ${conflict.docType} ${conflict.documentId} '
                'stays and will be sent to the team; their change is '
                'discarded.'
            : 'Their copy of ${conflict.docType} ${conflict.documentId} '
                'replaces yours on this device. Local changes that have '
                'not been sent yet are discarded.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text(keepMine ? 'Keep mine' : 'Take theirs')),
        ],
      ),
    );
    if (sure != true) return;
    try {
      final service = await ref.read(conflictServiceProvider.future);
      if (keepMine) {
        await service.keepMine(conflict.docType, conflict.documentId);
      } else {
        await service.takeTheirs(conflict.docType, conflict.documentId);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      ref.invalidate(syncConflictsProvider);
      ref.invalidate(conflictCountProvider);
    }
  }

  String _when(DateTime? time) {
    if (time == null) return 'unknown time';
    final local = time.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(syncConflictsProvider);
    return ResponsiveScaffold(
      title: 'Sync conflicts',
      leading: Navigator.of(context).canPop() ? const BackButton() : null,
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (conflicts) => conflicts.isEmpty
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.check_circle_outline, size: 40),
                    const SizedBox(height: MercantisSpacing.sm),
                    Text('No conflicts', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                        'Edits from your team merge automatically; anything '
                        'needing a decision shows up here.',
                        style: theme.textTheme.bodySmall),
                  ],
                ),
              )
            : ListView.separated(
                padding: const EdgeInsets.all(MercantisSpacing.lg),
                itemCount: conflicts.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(height: MercantisSpacing.sm),
                itemBuilder: (context, index) {
                  final c = conflicts[index];
                  return AtlasSectionCard(
                    name: '${c.docType} · ${c.documentId}',
                    child: Padding(
                      padding: const EdgeInsets.all(MercantisSpacing.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              'Yours: edited ${_when(c.localModifiedAt)} '
                              'on this device'),
                          Text('Theirs: edited ${_when(c.remoteModifiedAt)} '
                              'by ${c.remote.userId} '
                              '(device ${c.remote.deviceId})'),
                          const SizedBox(height: MercantisSpacing.sm),
                          Row(
                            children: [
                              FilledButton.tonal(
                                onPressed: () => _resolve(context, ref, c,
                                    keepMine: true),
                                child: const Text('Keep mine'),
                              ),
                              const SizedBox(width: MercantisSpacing.sm),
                              OutlinedButton(
                                onPressed: () => _resolve(context, ref, c,
                                    keepMine: false),
                                child: const Text('Take theirs'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
