import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

import '../membership/membership_service.dart';

const _systemRoles = {'System Manager'};

/// The members list plus Draft sign-ups waiting for activation.
class MembersData {
  const MembersData({required this.lines, required this.drafts});

  final List<MemberRollLine> lines;
  final List<Document> drafts;
}

final membersProvider =
    FutureProvider.autoDispose<MembersData>((ref) async {
  final engine = await ref.watch(documentEngineProvider.future);
  final lines = await MembershipService(engine).memberRoll();
  final drafts = [
    for (final m
        in await engine.list('Membership', userRoles: _systemRoles))
      if ('${m.payload['status']}' == 'Draft') m,
  ];
  return MembersData(lines: lines, drafts: drafts);
});

/// V7: the members list — who's on what plan, when they bill next, what
/// they owe (worst first) — with activate / pause / resume / cancel a
/// tap away.
class MembersScreen extends ConsumerStatefulWidget {
  const MembersScreen({super.key});

  @override
  ConsumerState<MembersScreen> createState() => _MembersScreenState();
}

class _MembersScreenState extends ConsumerState<MembersScreen> {
  Future<MembershipService> get _service async =>
      MembershipService(await ref.read(documentEngineProvider.future));

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      if (mounted) {
        final text = '$e';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(text.startsWith('Bad state: ')
                ? text.substring('Bad state: '.length)
                : text)));
      }
    } finally {
      ref.invalidate(membersProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(membersProvider);
    final theme = Theme.of(context);
    return ResponsiveScaffold(
      title: 'Members',
      leading: Navigator.of(context).canPop() ? const BackButton() : null,
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (data) {
          if (data.lines.isEmpty && data.drafts.isEmpty) {
            return const EmptyState(
              title: 'No members yet',
              message: 'Create Membership Plans, sign members up, and '
                  'their fees bill themselves every period.',
              icon: Icons.card_membership_outlined,
            );
          }
          return ListView(
            padding: const EdgeInsets.all(MercantisSpacing.lg),
            children: [
              if (data.drafts.isNotEmpty) ...[
                Text('Waiting to start',
                    style: theme.textTheme.titleSmall),
                const SizedBox(height: MercantisSpacing.sm),
                for (final draft in data.drafts)
                  Padding(
                    padding: const EdgeInsets.only(
                        bottom: MercantisSpacing.sm),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                              '${draft.id} · ${draft.payload['member']} '
                              '· ${draft.payload['plan']}',
                              style: theme.textTheme.bodyMedium),
                        ),
                        FilledButton.tonal(
                          onPressed: () => _run(() async =>
                              (await _service).activate(draft.id)),
                          child: const Text('Activate'),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: MercantisSpacing.md),
              ],
              for (final line in data.lines) _memberRow(line, theme),
            ],
          );
        },
      ),
    );
  }

  Widget _memberRow(MemberRollLine line, ThemeData theme) {
    final paused =
        '${line.membership.payload['status']}' == 'Paused';
    return Padding(
      padding: const EdgeInsets.only(bottom: MercantisSpacing.sm),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${line.member} · ${line.planName}',
                    style: theme.textTheme.titleSmall),
                Text(
                    paused
                        ? 'Paused — no billing'
                        : '${line.fee.toStringAsFixed(2)} '
                            '${line.frequency.toLowerCase()}'
                            '${line.nextInvoiceDate != null ? ' · next ${line.nextInvoiceDate}' : ''}',
                    style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(line.arrears.toStringAsFixed(2),
                  style: theme.textTheme.titleMedium!.copyWith(
                      color: line.arrears > 0
                          ? theme.colorScheme.error
                          : null)),
              Text('owed', style: theme.textTheme.labelSmall),
            ],
          ),
          const SizedBox(width: MercantisSpacing.sm),
          if (paused)
            FilledButton.tonal(
              onPressed: () => _run(() async =>
                  (await _service).resume(line.membership.id)),
              child: const Text('Resume'),
            )
          else
            OutlinedButton(
              onPressed: () => _run(() async =>
                  (await _service).pause(line.membership.id)),
              child: const Text('Pause'),
            ),
          const SizedBox(width: MercantisSpacing.xs),
          TextButton(
            onPressed: () => _run(
                () async => (await _service).cancel(line.membership.id)),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
}
