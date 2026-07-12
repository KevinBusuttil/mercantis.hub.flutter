import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

import '../booking/booking_service.dart';

const _systemRoles = {'System Manager'};

/// The commission report plus the names to print it with.
class CommissionsData {
  const CommissionsData({
    required this.from,
    required this.lines,
    required this.names,
  });

  /// Inclusive posting-date lower bound (first of the current month).
  final String from;
  final List<CommissionLine> lines;

  /// Schedulable Resource id → display name.
  final Map<String, String> names;
}

final commissionsDataProvider =
    FutureProvider.autoDispose<CommissionsData>((ref) async {
  final engine = await ref.watch(documentEngineProvider.future);
  final now = DateTime.now();
  final from = DateTime(now.year, now.month, 1)
      .toIso8601String()
      .split('T')
      .first;
  final lines =
      await BookingService(engine).computeCommissions(from: from);
  final names = <String, String>{
    for (final r in await engine.list('Schedulable Resource',
        userRoles: _systemRoles))
      r.id: '${r.payload['resource_name']}',
  };
  return CommissionsData(from: from, lines: lines, names: names);
});

/// P4-2: what each staff member earned this month on the work they
/// invoiced — count of completed bookings, the invoiced net base, and
/// the commission their rules produce.
class CommissionsScreen extends ConsumerWidget {
  const CommissionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(commissionsDataProvider);
    final theme = Theme.of(context);
    return ResponsiveScaffold(
      title: 'Commissions',
      leading: Navigator.of(context).canPop() ? const BackButton() : null,
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (data) {
          if (data.lines.isEmpty) {
            return const EmptyState(
              title: 'No commission yet',
              message: 'Commission appears once staff with a Commission '
                  'Rule complete bookings that invoice this month.',
              icon: Icons.percent_outlined,
            );
          }
          return ListView(
            padding: const EdgeInsets.all(MercantisSpacing.lg),
            children: [
              Text('Since ${data.from}',
                  style: theme.textTheme.labelMedium),
              const SizedBox(height: MercantisSpacing.sm),
              for (final line in data.lines)
                Padding(
                  padding:
                      const EdgeInsets.only(bottom: MercantisSpacing.sm),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(data.names[line.resource] ?? line.resource,
                                style: theme.textTheme.titleSmall),
                            Text(
                                '${line.appointments} completed · '
                                'invoiced ${line.base.toStringAsFixed(2)}',
                                style: theme.textTheme.bodySmall),
                          ],
                        ),
                      ),
                      Text(line.commission.toStringAsFixed(2),
                          style: theme.textTheme.titleMedium),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
