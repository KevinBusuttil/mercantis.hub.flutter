import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../capture/capture_providers.dart';
import '../modules/capture/capture_module.dart';

/// The Document Capture review queue (ADR-049): captures visible to this
/// operator (role-filtered), open ones first. Tap to review; FAB to scan.
class CapturesScreen extends ConsumerWidget {
  const CapturesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final captures = ref.watch(capturesProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Captures'),
        actions: [
          IconButton(
            tooltip: 'Smart capture (AI)',
            icon: const Icon(Icons.auto_awesome_outlined),
            onPressed: () => context.go('/w/purchasing/capture-ai-settings'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.go('/w/home/scan-receipt'),
        icon: const Icon(Icons.document_scanner_outlined),
        label: const Text('Scan'),
      ),
      body: captures.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load captures.\n$e')),
        data: (rows) {
          if (rows.isEmpty) return const _EmptyCaptures();
          final open = rows.where((r) => r.isOpen).toList();
          final done = rows.where((r) => !r.isOpen).toList();
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(capturesProvider),
            child: ListView(
              children: [
                if (open.isNotEmpty) const _SectionHeader('Needs your attention'),
                for (final r in open) _CaptureTile(row: r),
                if (done.isNotEmpty) const _SectionHeader('Processed'),
                for (final r in done) _CaptureTile(row: r),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(label,
            style: Theme.of(context)
                .textTheme
                .labelMedium
                ?.copyWith(color: Theme.of(context).colorScheme.outline)),
      );
}

class _CaptureTile extends StatelessWidget {
  const _CaptureTile({required this.row});
  final CaptureRow row;

  @override
  Widget build(BuildContext context) {
    final subtitle = [
      if (row.date.isNotEmpty) row.date,
      if (row.confidence > 0) '${row.confidence}% read',
    ].join(' · ');
    return ListTile(
      leading: const CircleAvatar(child: Icon(Icons.receipt_outlined)),
      title: Text(row.merchant.isEmpty ? '(no merchant)' : row.merchant),
      subtitle: subtitle.isEmpty ? null : Text(subtitle),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (row.amount.isNotEmpty)
            Text(row.amount,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          _StatusChip(status: row.status),
        ],
      ),
      onTap: () => context.go('/w/home/capture-review?id=${row.id}'),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (Color bg, Color fg) = switch (status) {
      CaptureModule.statusReady => (scheme.primaryContainer, scheme.onPrimaryContainer),
      CaptureModule.statusNeedsReview => (scheme.errorContainer, scheme.onErrorContainer),
      CaptureModule.statusDraftCreated => (scheme.secondaryContainer, scheme.onSecondaryContainer),
      _ => (scheme.surfaceContainerHighest, scheme.onSurfaceVariant),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      child: Text(status,
          style: Theme.of(context)
              .textTheme
              .labelSmall
              ?.copyWith(color: fg)),
    );
  }
}

class _EmptyCaptures extends StatelessWidget {
  const _EmptyCaptures();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.receipt_long_outlined,
                size: 64, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 16),
            Text('No receipts captured yet',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text('Snap a photo of a receipt or bill and it lands here.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => context.go('/w/home/scan-receipt'),
              icon: const Icon(Icons.document_scanner_outlined),
              label: const Text('Scan a receipt'),
            ),
          ],
        ),
      ),
    );
  }
}
