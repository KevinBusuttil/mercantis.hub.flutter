import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

import '../hospitality/tab_service.dart';
import '../ledger/ledger_values.dart';

const _systemRoles = {'System Manager'};

/// The kitchen rail in one load: open tickets oldest first (the kitchen
/// cooks in order), with table names resolved for the header.
class KitchenData {
  const KitchenData({required this.tickets, required this.tableNames});

  final List<Document> tickets;

  /// POS Table id → display name.
  final Map<String, String> tableNames;
}

final kitchenDataProvider =
    FutureProvider.autoDispose<KitchenData>((ref) async {
  final engine = await ref.watch(documentEngineProvider.future);
  final headers =
      await engine.list('Kitchen Ticket', userRoles: _systemRoles);
  final tickets = <Document>[];
  for (final h in headers) {
    if ('${h.payload['status']}' != 'Open') continue;
    // list() doesn't hydrate lines; the rail is nothing without them.
    tickets.add(await engine.fetch('Kitchen Ticket', h.id) ?? h);
  }
  tickets.sort((a, b) =>
      '${a.payload['sent_at']}'.compareTo('${b.payload['sent_at']}'));

  final names = <String, String>{
    for (final t in await engine.list('POS Table', userRoles: _systemRoles))
      t.id: '${t.payload['table_name']}',
  };
  return KitchenData(tickets: tickets, tableNames: names);
});

/// V2-3: the kitchen display. Each card is one round sent from a tab —
/// oldest first with its waiting time, lines with modifiers and notes at
/// cooking size, and a bump when it's plated. Rounds never mutate once
/// sent; a follow-up order is the next ticket on the rail.
class KitchenScreen extends ConsumerStatefulWidget {
  const KitchenScreen({super.key});

  @override
  ConsumerState<KitchenScreen> createState() => _KitchenScreenState();
}

class _KitchenScreenState extends ConsumerState<KitchenScreen> {
  Future<void> _bump(Document ticket) async {
    try {
      final engine = await ref.read(documentEngineProvider.future);
      await TabService(engine).bumpTicket(ticket.id);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      ref.invalidate(kitchenDataProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(kitchenDataProvider);
    return ResponsiveScaffold(
      title: 'Kitchen',
      leading: Navigator.of(context).canPop() ? const BackButton() : null,
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: 'Refresh',
          onPressed: () => ref.invalidate(kitchenDataProvider),
        ),
      ],
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (data) {
          if (data.tickets.isEmpty) {
            return const EmptyState(
              title: 'Rail is clear',
              message: 'Tickets appear here the moment a server sends a '
                  'round to the kitchen.',
              icon: Icons.restaurant_outlined,
            );
          }
          return ListView(
            padding: const EdgeInsets.all(MercantisSpacing.lg),
            children: [
              Wrap(
                spacing: MercantisSpacing.md,
                runSpacing: MercantisSpacing.md,
                children: [
                  for (final t in data.tickets) _ticketCard(t, data),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _ticketCard(Document ticket, KitchenData data) {
    final theme = Theme.of(context);
    final table = asNonEmpty(ticket.payload['table']);
    final where = table == null
        ? 'Bar'
        : data.tableNames[table] ?? table;
    final sentAt =
        DateTime.tryParse('${ticket.payload['sent_at']}');
    final waited = sentAt == null
        ? null
        : DateTime.now().difference(sentAt).inMinutes;
    // The rail's triage colours: fresh, waiting, late.
    final urgency = waited == null || waited < 10
        ? theme.colorScheme.surfaceContainerHighest
        : waited < 20
            ? theme.colorScheme.tertiaryContainer
            : theme.colorScheme.errorContainer;
    return Container(
      width: 240,
      padding: const EdgeInsets.all(MercantisSpacing.md),
      decoration: BoxDecoration(
        color: urgency,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('$where · ${ticket.id}',
                    style: theme.textTheme.titleSmall,
                    overflow: TextOverflow.ellipsis),
              ),
              if (waited != null)
                Text('$waited min', style: theme.textTheme.labelMedium),
            ],
          ),
          if (asNonEmpty(ticket.payload['server']) != null)
            Text('${ticket.payload['server']}',
                style: theme.textTheme.labelSmall),
          const SizedBox(height: MercantisSpacing.sm),
          for (final l in ticket.children['items'] ?? const <ChildRow>[])
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      '${asNum(l.payload['qty'])} × ${l.payload['item']}',
                      style: theme.textTheme.titleMedium),
                  if (asNonEmpty(l.payload['modifiers']) != null)
                    Text('${l.payload['modifiers']}',
                        style: theme.textTheme.bodySmall),
                  if (asNonEmpty(l.payload['notes']) != null)
                    Text('“${l.payload['notes']}”',
                        style: theme.textTheme.bodySmall!
                            .copyWith(fontStyle: FontStyle.italic)),
                ],
              ),
            ),
          const SizedBox(height: MercantisSpacing.sm),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => _bump(ticket),
              child: const Text('Done'),
            ),
          ),
        ],
      ),
    );
  }
}
