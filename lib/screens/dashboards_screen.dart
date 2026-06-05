import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

import '../reports/report_providers.dart';

/// Lists the dashboards the current user may open, each resolved on real data
/// by the Core [DashboardEngine]. Replaces the mock dashboard surface.
class DashboardsScreen extends ConsumerWidget {
  const DashboardsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncEngine = ref.watch(dashboardEngineProvider);
    final roles = ref.watch(currentUserProvider).roles;
    return Scaffold(
      appBar: AppBar(title: const Text('Dashboards')),
      body: asyncEngine.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Failed to load dashboards: $e')),
        data: (engine) {
          final dashboards = engine.availableDashboards(roles);
          if (dashboards.isEmpty) {
            return const Center(child: Text('No dashboards available'));
          }
          return ListView.separated(
            itemCount: dashboards.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final d = dashboards[i];
              return ListTile(
                leading: const Icon(Icons.dashboard_outlined),
                title: Text(d.name),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => DashboardScreen(dashboardId: d.id),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// Resolves and renders one dashboard's tiles from real data.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key, required this.dashboardId});

  final String dashboardId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(dashboardResultProvider(dashboardId));
    return Scaffold(
      appBar: AppBar(title: Text(async.valueOrNull?.name ?? 'Dashboard')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Failed to load dashboard:\n$e', textAlign: TextAlign.center),
          ),
        ),
        data: (result) => ListView(
          padding: const EdgeInsets.all(12),
          children: [for (final w in result.widgets) _tile(context, w)],
        ),
      ),
    );
  }

  Widget _tile(BuildContext context, DashboardWidgetResult w) {
    if (w.isError) {
      return _card(context, w.label, Text(w.error!,
          style: TextStyle(color: Theme.of(context).colorScheme.error)));
    }
    switch (w.type) {
      case 'count':
        return _metric(context, w.label, '${w.count ?? 0}');
      case 'sum':
        return _metric(context, w.label, w.display ?? '${w.total ?? 0}');
      case 'shortcut':
        return Card(
          child: ListTile(
            leading: const Icon(Icons.open_in_new),
            title: Text(w.label),
            onTap: w.route == null ? null : () => context.go(w.route!),
          ),
        );
      case 'list':
        final rows = w.rows ?? const [];
        return _card(
          context,
          w.label,
          rows.isEmpty
              ? const Text('No data')
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final row in rows)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text(row.values
                            .where((v) => v != null)
                            .join('  ·  ')),
                      ),
                  ],
                ),
        );
      case 'chart':
        final chart = w.chart;
        return _card(
          context,
          w.label,
          chart == null || chart.isEmpty
              ? const Text('No data')
              : SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: [
                      for (final c in chart.columns) DataColumn(label: Text(c.label)),
                    ],
                    rows: [
                      for (final r in chart.rows.take(5))
                        DataRow(cells: [
                          for (final cell in r) DataCell(Text(cell ?? '—')),
                        ]),
                    ],
                  ),
                ),
        );
      default:
        return _card(context, w.label, Text('Unsupported tile "${w.type}"'));
    }
  }

  Widget _metric(BuildContext context, String label, String value) {
    return _card(
      context,
      label,
      Text(value, style: Theme.of(context).textTheme.headlineSmall),
    );
  }

  Widget _card(BuildContext context, String label, Widget child) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }
}
