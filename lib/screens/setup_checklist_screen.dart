import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

import '../onboarding/setup_checklist.dart';
import '../settings/hub_settings.dart';

/// Live-computed on every visit so the list always reflects the store.
final setupChecklistProvider =
    FutureProvider.autoDispose<SetupChecklist>((ref) async {
  final engine = await ref.watch(documentEngineProvider.future);
  final settings = ref.watch(hubSettingsProvider);
  return buildSetupChecklist(engine, settings);
});

/// The guided setup checklist: what's done, what's left, and whether it is
/// safe to start invoicing. Each row deep-links to where the step is
/// completed.
class SetupChecklistScreen extends ConsumerWidget {
  const SetupChecklistScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final checklist = ref.watch(setupChecklistProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Setup checklist')),
      body: checklist.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load checklist: $e')),
        data: (list) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(setupChecklistProvider),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _ReadyBanner(list: list),
              const SizedBox(height: 12),
              _Progress(list: list),
              const SizedBox(height: 12),
              for (final item in list.items) _ItemTile(item: item),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReadyBanner extends StatelessWidget {
  const _ReadyBanner({required this.list});
  final SetupChecklist list;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ready = list.readyToInvoice;
    final missing = list.missingForInvoicing;
    final color = ready ? Colors.green : theme.colorScheme.tertiary;
    return Card(
      color: color.withValues(alpha: 0.12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(ready ? Icons.verified_outlined : Icons.flag_outlined,
                color: color, size: 32),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ready
                        ? 'You can safely send your first invoice'
                        : '${missing.length} step${missing.length == 1 ? '' : 's'} '
                            'before you can invoice',
                    style: theme.textTheme.titleMedium,
                  ),
                  if (!ready)
                    Text(
                      missing.map((i) => i.label).join(' · '),
                      style: theme.textTheme.bodySmall,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.list});
  final SetupChecklist list;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: list.totalCount == 0
                  ? 0
                  : list.doneCount / list.totalCount,
              minHeight: 8,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Text('${list.doneCount} of ${list.totalCount} done',
            style: theme.textTheme.bodySmall),
      ],
    );
  }
}

class _ItemTile extends StatelessWidget {
  const _ItemTile({required this.item});
  final SetupChecklistItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (icon, color) = switch (item.status) {
      SetupItemStatus.done => (Icons.check_circle, Colors.green),
      SetupItemStatus.todo => (
          Icons.radio_button_unchecked,
          theme.colorScheme.outline
        ),
      SetupItemStatus.notApplicable => (
          Icons.remove_circle_outline,
          theme.disabledColor
        ),
    };
    final enabled = item.isApplicable;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        enabled: enabled,
        leading: Icon(icon, color: color),
        title: Text(item.label),
        subtitle: Text(
          enabled ? item.description : '${item.description} (module hidden)',
        ),
        trailing: enabled ? const Icon(Icons.chevron_right) : null,
        onTap: enabled ? () => context.go(item.route) : null,
      ),
    );
  }
}
