import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../sync/company_sync.dart';

/// Connect this device to a shared company folder (iCloud Drive / Dropbox /
/// OneDrive / a network share) and sync documents across everyone pointed at
/// the same folder. Serverless: the folder is the only "cloud".
class CompanySyncScreen extends ConsumerWidget {
  const CompanySyncScreen({super.key});

  Future<void> _pickFolder(WidgetRef ref) async {
    final path = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Choose the shared company folder',
    );
    if (path != null) {
      await ref.read(companySyncProvider.notifier).connect(path);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(companySyncProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Company sync')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (s) {
          final syncing = s.phase == SyncPhase.syncing;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Share this company across devices by pointing each one at the '
                'same folder in your iCloud Drive, Dropbox, or OneDrive. There '
                'is no server — the folder is the cloud.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              if (!s.connected)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Not connected',
                            style: theme.textTheme.titleMedium),
                        const SizedBox(height: 4),
                        Text(
                          'Create a folder in your cloud drive (or open one a '
                          'colleague shared with you), then connect to it.',
                          style: theme.textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: () => _pickFolder(ref),
                          icon: const Icon(Icons.create_new_folder_outlined),
                          label: const Text('Connect shared folder'),
                        ),
                      ],
                    ),
                  ),
                )
              else ...[
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.cloud_done_outlined),
                    title: const Text('Connected'),
                    subtitle: Text(s.folder!),
                    isThreeLine: true,
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: syncing
                        ? null
                        : () => ref.read(companySyncProvider.notifier).syncNow(),
                    icon: syncing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.sync),
                    label: Text(syncing ? 'Syncing…' : 'Sync now'),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: syncing ? null : () => _pickFolder(ref),
                      icon: const Icon(Icons.folder_open_outlined),
                      label: const Text('Change folder'),
                    ),
                    OutlinedButton.icon(
                      onPressed: syncing
                          ? null
                          : () => ref.read(companySyncProvider.notifier).disconnect(),
                      icon: const Icon(Icons.link_off),
                      label: const Text('Disconnect'),
                    ),
                  ],
                ),
              ],
              const Divider(height: 32),
              Text('Status', style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              _kv(theme, 'This device', '${s.deviceId.substring(0, 8)}…'),
              _kv(theme, 'Pending changes', '${s.pending}'),
              _kv(theme, 'Last synced',
                  s.lastSyncedAt == null ? '—' : _formatTime(s.lastSyncedAt!)),
              if (s.lastSyncedAt != null)
                _kv(theme, 'Last exchange',
                    '↑ ${s.lastPushed} pushed   ↓ ${s.lastPulled} pulled'),
              if (s.phase == SyncPhase.error && s.message != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('Sync failed: ${s.message}',
                      style: TextStyle(color: theme.colorScheme.error)),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _kv(ThemeData theme, String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            SizedBox(
                width: 150,
                child: Text(k, style: theme.textTheme.bodySmall)),
            Expanded(
                child: Text(v, style: theme.textTheme.bodyMedium)),
          ],
        ),
      );

  static String _formatTime(DateTime t) {
    final l = t.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${l.year}-${two(l.month)}-${two(l.day)} ${two(l.hour)}:${two(l.minute)}';
  }
}
