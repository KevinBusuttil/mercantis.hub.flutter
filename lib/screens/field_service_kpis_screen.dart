import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

import '../field_service/field_service_kpis.dart';

final fieldServiceKpisProvider =
    FutureProvider.autoDispose.family<FieldServiceKpis, int>(
        (ref, windowDays) async {
  final engine = await ref.watch(documentEngineProvider.future);
  return loadFieldServiceKpis(engine, windowDays: windowDays);
});

/// V1-6: how the field operation is doing — completed work, revenue,
/// money left unbilled, the request backlog, and contract health.
class FieldServiceKpisScreen extends ConsumerStatefulWidget {
  const FieldServiceKpisScreen({super.key});

  @override
  ConsumerState<FieldServiceKpisScreen> createState() =>
      _FieldServiceKpisScreenState();
}

class _FieldServiceKpisScreenState
    extends ConsumerState<FieldServiceKpisScreen> {
  int _windowDays = 30;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final async = ref.watch(fieldServiceKpisProvider(_windowDays));
    return ResponsiveScaffold(
      title: 'Field service KPIs',
      leading: Navigator.of(context).canPop() ? const BackButton() : null,
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (k) => ListView(
          padding: const EdgeInsets.all(MercantisSpacing.lg),
          children: [
            Row(
              children: [
                Text('${k.from} → ${k.to}',
                    style: theme.textTheme.bodySmall),
                const Spacer(),
                SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 7, label: Text('7d')),
                    ButtonSegment(value: 30, label: Text('30d')),
                    ButtonSegment(value: 90, label: Text('90d')),
                  ],
                  selected: {_windowDays},
                  onSelectionChanged: (s) =>
                      setState(() => _windowDays = s.first),
                ),
              ],
            ),
            const SizedBox(height: MercantisSpacing.md),
            AtlasSectionCard(
              name: 'Work done',
              child: Padding(
                padding: const EdgeInsets.all(MercantisSpacing.md),
                child: Column(
                  children: [
                    AtlasTotalRow(
                        label: 'Jobs completed',
                        value: '${k.jobsCompleted}'),
                    AtlasTotalRow(
                        label: 'Invoiced revenue',
                        value: k.revenue.toStringAsFixed(2),
                        emphasize: true),
                    if (k.unbilledCompleted > 0)
                      AtlasTotalRow(
                          label: 'Completed but NOT billed',
                          value: '${k.unbilledCompleted}'),
                    if (k.jobsCancelled > 0)
                      AtlasTotalRow(
                          label: 'Cancelled', value: '${k.jobsCancelled}'),
                    if (k.avgRequestToVisitDays >= 0)
                      AtlasTotalRow(
                          label: 'Request → visit (avg days)',
                          value:
                              k.avgRequestToVisitDays.toStringAsFixed(1)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: MercantisSpacing.md),
            AtlasSectionCard(
              name: 'Pipeline & contracts',
              child: Padding(
                padding: const EdgeInsets.all(MercantisSpacing.md),
                child: Column(
                  children: [
                    AtlasTotalRow(
                        label: 'Open requests',
                        value: '${k.openRequests}'),
                    if (k.openRequests > 0)
                      AtlasTotalRow(
                          label: 'Oldest open request (days)',
                          value: '${k.oldestOpenRequestDays}'),
                    AtlasTotalRow(
                        label: 'Active contracts',
                        value: '${k.activeContracts}'),
                    if (k.overdueContracts > 0)
                      AtlasTotalRow(
                          label: 'Contracts overdue a visit',
                          value: '${k.overdueContracts}'),
                  ],
                ),
              ),
            ),
            if (k.perTechnician.isNotEmpty) ...[
              const SizedBox(height: MercantisSpacing.md),
              AtlasSectionCard(
                name: 'By technician',
                child: Column(
                  children: [
                    for (final t in k.perTechnician)
                      ListTile(
                        dense: true,
                        leading: const Icon(Icons.engineering_outlined),
                        title: Text(t.technician),
                        subtitle:
                            Text('${t.jobsCompleted} job(s) completed'),
                        trailing: Text(
                          t.revenue.toStringAsFixed(2),
                          style: theme.textTheme.titleSmall,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
