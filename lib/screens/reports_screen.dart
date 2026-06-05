import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

import '../reports/report_providers.dart';

/// Lists every report the current user may run (from the real [ReportEngine]
/// catalogue) and opens each in a [ReportViewerScreen]. Replaces the mock
/// reports surface.
class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncEngine = ref.watch(reportEngineProvider);
    final roles = ref.watch(currentUserProvider).roles;
    return Scaffold(
      appBar: AppBar(title: const Text('Reports')),
      body: asyncEngine.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Failed to load reports: $e')),
        data: (engine) {
          final reports = engine.availableReports(roles);
          if (reports.isEmpty) {
            return const Center(child: Text('No reports available'));
          }
          return ListView.separated(
            itemCount: reports.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final r = reports[i];
              return ListTile(
                leading: const Icon(Icons.bar_chart_outlined),
                title: Text(r.name),
                subtitle: Text(r.docType),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ReportViewerScreen(reportId: r.id),
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

/// Runs one report and renders its [ReportResult] as a scrollable table.
class ReportViewerScreen extends ConsumerWidget {
  const ReportViewerScreen({super.key, required this.reportId});

  final String reportId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(reportResultProvider(reportId));
    return Scaffold(
      appBar: AppBar(title: Text(async.valueOrNull?.name ?? 'Report')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Failed to run report:\n$e', textAlign: TextAlign.center),
          ),
        ),
        data: (result) {
          if (result.isEmpty) {
            return const Center(child: Text('No data for this report yet'));
          }
          return SingleChildScrollView(
            scrollDirection: Axis.vertical,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: [
                  for (final c in result.columns) DataColumn(label: Text(c.label)),
                ],
                rows: [
                  for (final row in result.rows)
                    DataRow(
                      cells: [
                        for (final cell in row) DataCell(Text(cell ?? '—')),
                      ],
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
