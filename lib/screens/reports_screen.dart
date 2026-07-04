import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

import '../reports/report_providers.dart';

/// One aggregating financial statement: a title + the provider that computes it.
class _Statement {
  const _Statement(this.title, this.subtitle, this.provider);
  final String title;
  final String subtitle;
  final FutureProvider<ReportResult> provider;
}

final _statements = <_Statement>[
  _Statement('Trial Balance', 'GL Entry — debits vs credits per account', trialBalanceProvider),
  _Statement('AR Aging', 'Open Sales Invoices by age', arAgingProvider),
  _Statement('AP Aging', 'Open Purchase Invoices by age', apAgingProvider),
];

/// Lists every report the current user may run — the aggregating financial
/// statements (Trial Balance, AR/AP aging) plus the flat [ReportEngine]
/// registers — and opens each in a viewer.
class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncEngine = ref.watch(reportEngineProvider);
    final roles = ref.watch(currentUserProvider).roles;
    return ResponsiveScaffold(
      title: 'Reports',
      padBody: false,
      body: ListView(
        padding: const EdgeInsets.all(MercantisSpacing.lg),
        children: [
          AtlasSectionCard(
            name: 'Financial statements',
            child: Column(
              children: [
                for (final s in _statements)
                  ListTile(
                    leading: const Icon(Icons.account_balance_outlined),
                    title: Text(s.title),
                    subtitle: Text(s.subtitle),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => AggregatingReportViewerScreen(
                            title: s.title, provider: s.provider),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: MercantisSpacing.lg),
          AtlasSectionCard(
            name: 'Registers',
            child: asyncEngine.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(MercantisSpacing.xl),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.all(MercantisSpacing.xl),
                child: Text('Failed to load reports: $e'),
              ),
              data: (engine) {
                final reports = engine.availableReports(roles);
                if (reports.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(MercantisSpacing.xl),
                    child: Text('No reports available'),
                  );
                }
                return Column(
                  children: [
                    for (final r in reports)
                      ListTile(
                        leading: const Icon(Icons.bar_chart_outlined),
                        title: Text(r.name),
                        subtitle: Text(r.docType),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => ReportViewerScreen(reportId: r.id),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Runs one flat [ReportEngine] report and renders its result.
class ReportViewerScreen extends ConsumerWidget {
  const ReportViewerScreen({super.key, required this.reportId});

  final String reportId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(reportResultProvider(reportId));
    return _ReportScaffold(title: async.valueOrNull?.name ?? 'Report', result: async);
  }
}

/// Runs one app-side aggregating report (Trial Balance, AR/AP aging).
class AggregatingReportViewerScreen extends ConsumerWidget {
  const AggregatingReportViewerScreen({super.key, required this.title, required this.provider});

  final String title;
  final FutureProvider<ReportResult> provider;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _ReportScaffold(title: title, result: ref.watch(provider));
  }
}

/// Shared loading/error/empty/table chrome for both report viewers.
class _ReportScaffold extends StatelessWidget {
  const _ReportScaffold({required this.title, required this.result});

  final String title;
  final AsyncValue<ReportResult> result;

  @override
  Widget build(BuildContext context) {
    return ResponsiveScaffold(
      title: title,
      padBody: false,
      body: result.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(MercantisSpacing.xl),
            child: Text('Failed to run report:\n$e', textAlign: TextAlign.center),
          ),
        ),
        data: (data) {
          if (data.isEmpty) {
            return const Center(child: Text('No data for this report yet'));
          }
          return _ReportTable(result: data);
        },
      ),
    );
  }
}

/// Renders a [ReportResult] as a scrollable table.
class _ReportTable extends StatelessWidget {
  const _ReportTable({required this.result});

  final ReportResult result;

  @override
  Widget build(BuildContext context) {
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
  }
}

