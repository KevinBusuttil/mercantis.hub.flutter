import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

import '../features/hub_feature.dart';
import '../navigation/hub_surface.dart';
import '../reports/money_format.dart';
import '../reports/report_providers.dart';
import '../reports/report_summary.dart';
import 'deposits_screen.dart';
import 'field_service_kpis_screen.dart';

/// One aggregating statement: the Owner and Accountant titles, what it
/// answers, the provider that computes it and when it applies.
class _Statement {
  const _Statement(this.title, this.engineTitle, this.subtitle, this.provider,
      {this.requires, this.icon = Icons.insights_outlined});
  final String title;
  final String engineTitle;
  final String subtitle;
  final FutureProvider<ReportResult> provider;
  final Requirement? requires;
  final IconData icon;
}

final _statements = <_Statement>[
  _Statement('Profit & loss', 'Profit & Loss', 'What you earned, spent and kept',
      profitAndLossProvider, icon: Icons.trending_up),
  _Statement('Cash flow', 'Cash Flow Overview',
      'Money in and out of your bank and cash', cashFlowProvider,
      icon: Icons.swap_vert),
  _Statement('Who owes you', 'AR Aging', 'Unpaid invoices by how late they are',
      arAgingProvider, icon: Icons.call_received),
  _Statement('What you owe', 'AP Aging', 'Unpaid supplier bills by age',
      apAgingProvider, icon: Icons.call_made),
  _Statement('Balance sheet', 'Balance Sheet', 'What the business owns and owes',
      balanceSheetProvider, icon: Icons.account_balance_outlined),
  _Statement('Gross margin', 'Gross Margin by Item',
      'What each product earns after its cost', grossMarginProvider,
      requires: const NeedsFeature(HubFeature.stock), icon: Icons.percent),
  _Statement('Stock value', 'Stock Valuation',
      'What your stock on hand is worth', stockValuationProvider,
      requires: const NeedsFeature(HubFeature.stock),
      icon: Icons.inventory_2_outlined),
  _Statement('Project profitability', 'Project Profitability',
      'Invoiced against costs per project', projectProfitabilityProvider,
      requires: const NeedsAnyFeature(
          [HubFeature.projects, HubFeature.construction]),
      icon: Icons.work_outline),
  _Statement('Trial balance', 'Trial Balance',
      'Debits and credits per account', trialBalanceProvider,
      requires: const NeedsAccountant(), icon: Icons.balance),
  _Statement('Stock ↔ GL reconciliation', 'Stock ↔ GL Reconciliation',
      'Stock ledger against the inventory account',
      stockGlReconciliationProvider,
      requires: const NeedsAccountant(), icon: Icons.rule),
];

/// The reports this business can use: the statements every business needs,
/// those its features add (stock, projects, field service, deposits), and —
/// in the Accountant view — the trial balance, reconciliations and raw
/// registers. Hiding a report hides the link only; nothing is recomputed.
class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final surface = ref.watch(hubSurfaceProvider);
    final asyncEngine = ref.watch(reportEngineProvider);
    final roles = ref.watch(currentUserProvider).roles;
    final stockGl = surface.has(HubFeature.stock);
    final shown = [
      for (final s in _statements)
        if (surface.allows(s.requires) &&
            (s.provider != stockGlReconciliationProvider || stockGl))
          s,
    ];
    void open(Widget screen) => Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => screen));
    return ResponsiveScaffold(
      title: 'Reports',
      padBody: false,
      body: ListView(
        padding: const EdgeInsets.all(MercantisSpacing.lg),
        children: [
          AtlasSectionCard(
            name: surface.say('How the business is doing', 'Financial statements'),
            child: Column(
              children: [
                for (final s in shown)
                  ListTile(
                    minTileHeight: 56,
                    leading: Icon(s.icon),
                    title: Text(surface.say(s.title, s.engineTitle)),
                    subtitle: Text(s.subtitle),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => open(AggregatingReportViewerScreen(
                        title: surface.say(s.title, s.engineTitle),
                        provider: s.provider)),
                  ),
                if (surface.has(HubFeature.fieldService))
                  ListTile(
                    minTileHeight: 56,
                    leading: const Icon(Icons.home_repair_service_outlined),
                    title: const Text('Field service KPIs'),
                    subtitle: const Text(
                        'Jobs done, revenue per technician, backlog'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => open(const FieldServiceKpisScreen()),
                  ),
                if (surface.has(HubFeature.appointments) || surface.accountant)
                  ListTile(
                    minTileHeight: 56,
                    leading: const Icon(Icons.savings_outlined),
                    title: const Text('Customer deposits'),
                    subtitle: const Text(
                        'Prepayments held, applied and outstanding'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => open(const DepositsScreen()),
                  ),
              ],
            ),
          ),
          if (surface.accountant) ...[
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
                          onTap: () =>
                              open(ReportViewerScreen(reportId: r.id)),
                        ),
                    ],
                  );
                },
              ),
            ),
          ] else ...[
            const SizedBox(height: MercantisSpacing.md),
            Text(
              'Trial balance, reconciliations and raw registers are in the '
              'Accountant view (Settings › Business type & features).',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
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

/// Shared loading/error/empty chrome for both report viewers. A statement
/// with a summary form opens on it — headline figures, what needs attention,
/// the main groups with drill-down — and keeps the full table one tap away
/// (open by default in the Accountant view). Other reports show the table.
class _ReportScaffold extends ConsumerWidget {
  const _ReportScaffold({required this.title, required this.result});

  final String title;
  final AsyncValue<ReportResult> result;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accountant = ref.watch(hubSurfaceProvider).accountant;
    return ResponsiveScaffold(
      title: title,
      padBody: false,
      body: result.when(
        loading: () => Center(
          child: Semantics(
            label: 'Working out the report',
            child: const CircularProgressIndicator(),
          ),
        ),
        error: (e, _) => EmptyState(
          icon: Icons.error_outline,
          title: 'This report could not run',
          message: 'Nothing was changed. Pull back and try again; if it keeps '
              'failing, the details below help support.\n\n$e',
        ),
        data: (data) {
          if (data.isEmpty) {
            return const EmptyState(
              icon: Icons.insights_outlined,
              title: 'Nothing to report yet',
              message: 'Figures appear here once invoices, bills or payments '
                  'are posted.',
            );
          }
          final summary = summariseReport(data);
          if (summary == null) return _ReportTable(result: data);
          return ReportSummaryView(
            summary: summary,
            table: _ReportTable(result: data, embedded: true),
            tableInitiallyOpen: accountant,
          );
        },
      ),
    );
  }
}

/// The phone-first reading of a statement (see [ReportSummary]).
class ReportSummaryView extends StatelessWidget {
  const ReportSummaryView({
    super.key,
    required this.summary,
    required this.table,
    this.tableInitiallyOpen = false,
  });

  final ReportSummary summary;
  final Widget table;
  final bool tableInitiallyOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return LayoutBuilder(builder: (context, c) {
      final columns = columnsForTextScale(
          context, c.maxWidth >= 900 ? 4 : (c.maxWidth >= 560 ? 3 : 2));
      return ListView(
        padding: const EdgeInsets.all(MercantisSpacing.lg),
        children: [
          LayoutBuilder(builder: (context, inner) {
            const gap = MercantisSpacing.md;
            final w = (inner.maxWidth - gap * (columns - 1)) / columns;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final f in summary.figures)
                  SizedBox(width: w, child: _FigureTile(figure: f)),
              ],
            );
          }),
          const SizedBox(height: MercantisSpacing.lg),
          if (summary.exceptions.isNotEmpty)
            _Notice(
              icon: Icons.priority_high,
              color: cs.errorContainer,
              onColor: cs.onErrorContainer,
              title: 'Needs attention',
              lines: summary.exceptions,
            )
          else if (summary.allClear != null)
            _Notice(
              icon: Icons.check_circle_outline,
              color: cs.secondaryContainer,
              onColor: cs.onSecondaryContainer,
              title: summary.allClear!,
              lines: const [],
            ),
          for (final g in summary.groups)
            if (g.lines.isNotEmpty) ...[
              const SizedBox(height: MercantisSpacing.lg),
              AtlasSectionCard(
                name: g.title,
                child: Column(
                  children: [
                    for (final l in g.lines)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        minTileHeight: 56,
                        title: Text(l.label,
                            maxLines: 2, overflow: TextOverflow.ellipsis),
                        subtitle: l.detail == null ? null : Text(l.detail!),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(l.value,
                                style: theme.textTheme.titleSmall?.copyWith(
                                    fontFeatures: const [
                                      FontFeature.tabularFigures()
                                    ])),
                            if (l.location != null)
                              const Icon(Icons.chevron_right),
                          ],
                        ),
                        onTap: l.location == null
                            ? null
                            : () => context.push(l.location!),
                      ),
                    if (g.more > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: MercantisSpacing.sm),
                        child: Text(
                          '${g.more} more in the detailed table below',
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          const SizedBox(height: MercantisSpacing.lg),
          Card(
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            child: ExpansionTile(
              initiallyExpanded: tableInitiallyOpen,
              leading: const Icon(Icons.table_rows_outlined),
              title: const Text('Detailed table'),
              subtitle: const Text('Every line, as your accountant sees it'),
              childrenPadding: EdgeInsets.zero,
              children: [table],
            ),
          ),
        ],
      );
    });
  }
}

class _FigureTile extends StatelessWidget {
  const _FigureTile({required this.figure});

  final SummaryFigure figure;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final color = switch (figure.tone) {
      SummaryTone.bad => cs.error,
      SummaryTone.good => const Color(0xFF1B7F4B),
      SummaryTone.neutral => cs.onSurface,
    };
    final spoken = switch (figure.tone) {
      SummaryTone.bad => ', needs attention',
      _ => '',
    };
    return Semantics(
      label: '${figure.label}: ${figure.value}$spoken',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.all(MercantisSpacing.md),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: MercantisRadius.rLg,
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(figure.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium
                    ?.copyWith(color: cs.onSurfaceVariant)),
            const SizedBox(height: MercantisSpacing.xs),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Text(figure.value,
                  maxLines: 1,
                  style: theme.textTheme.titleLarge?.copyWith(
                      color: color, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.icon,
    required this.color,
    required this.onColor,
    required this.title,
    required this.lines,
  });

  final IconData icon;
  final Color color;
  final Color onColor;
  final String title;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(MercantisSpacing.md),
      decoration: BoxDecoration(color: color, borderRadius: MercantisRadius.rMd),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: onColor),
          const SizedBox(width: MercantisSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: theme.textTheme.titleSmall?.copyWith(color: onColor)),
                for (final l in lines)
                  Padding(
                    padding: const EdgeInsets.only(top: MercantisSpacing.xs),
                    child: Text(l,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: onColor)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Renders a [ReportResult] as a scrollable table. [embedded] tables sit
/// inside the summary's list and scroll only sideways.
class _ReportTable extends StatelessWidget {
  const _ReportTable({required this.result, this.embedded = false});

  final ReportResult result;
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final table = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: [
          for (final c in result.columns)
            DataColumn(
              label: Text(c.label),
              numeric: c.type == 'currency',
            ),
        ],
        rows: [
          for (final row in result.rows)
            DataRow(
              cells: [
                for (final (i, cell) in row.indexed)
                  DataCell(Text(_cell(cell, result.columns[i]))),
              ],
            ),
        ],
      ),
    );
    if (embedded) return table;
    return SingleChildScrollView(child: table);
  }

  static String _cell(String? cell, ReportColumn column) {
    if (cell == null || cell.isEmpty) return '—';
    if (column.type != 'currency') return cell;
    final n = parseAmount(cell);
    return n == null ? cell : formatMoney(n);
  }
}
