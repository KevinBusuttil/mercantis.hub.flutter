import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';
import '../mock/mock_data.dart';
import '../reports/report_providers.dart';

/// Registers dashboard card builders into the Core registry, keyed by spec.id.
///
/// The Home workspace cards are fed by the real `home` dashboard (Core
/// [DashboardEngine]); the Sales and Inventory workspace cards are still mock
/// pending their own de-mock.
void registerHubDashboardCards(WidgetRef ref) {
  final registry = ref.read(dashboardCardHostRegistryProvider);

  // ---- Home: real data via the `home` dashboard -------------------------
  registry.registerCard(
    'home_open_orders',
    (context, spec) => _HomeMetricCard(
      widgetId: 'home_open_orders',
      title: spec.title,
      icon: Icons.shopping_cart_outlined,
      accent: MercantisBrandColors.accentSales,
    ),
  );
  registry.registerCard(
    'home_receivables',
    (context, spec) => _HomeMetricCard(
      widgetId: 'home_receivables',
      title: spec.title,
      icon: Icons.south_west,
      accent: MercantisBrandColors.accentFinance,
    ),
  );
  registry.registerCard(
    'home_payables',
    (context, spec) => _HomeMetricCard(
      widgetId: 'home_payables',
      title: spec.title,
      icon: Icons.north_east,
      accent: MercantisBrandColors.accentFinance,
    ),
  );
  registry.registerCard(
    'home_recent_sales',
    (context, spec) => _HomeRecentInvoicesCard(title: spec.title),
  );

  // Approvals card (already real — backed by the approval inbox source).
  registry.registerCard('home_approvals_card', (context, spec) {
    return DashboardCard(
      title: 'Pending approvals',
      subtitle: 'Tap to review',
      icon: Icons.fact_check_outlined,
      accentColor: MercantisBrandColors.accentApprovals,
      onTap: () => context.go('/w/approvals'),
      child: const SizedBox(
        height: 220,
        child: ApprovalInboxList(limit: 4, dense: true),
      ),
    );
  });

  // ---- Sales workspace KPIs (still mock) --------------------------------
  for (final kpi in MockData.salesKpis) {
    registry.registerCard(kpi.id, (context, spec) => _buildKpi(kpi));
  }

  // ---- Inventory workspace KPIs (still mock) ----------------------------
  for (final kpi in MockData.inventoryKpis) {
    registry.registerCard(kpi.id, (context, spec) => _buildKpi(kpi));
  }

  // Recent documents list card (sales workspace — still mock).
  registry.registerCard('sales_recent_documents', (context, spec) {
    return ListCard(
      title: 'Recent documents',
      icon: Icons.history,
      accentColor: MercantisBrandColors.accentSales,
      onSeeAll: () => context.go('/list/Sales Order'),
      rows: [
        for (final r in MockData.salesRecent)
          ListCardRow(
            title: '${r.title} · ${r.subtitle}',
            subtitle: '${r.docType} · ${r.timestamp}',
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (r.amount != null) ...[
                  Text(r.amount!,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    )),
                  const SizedBox(width: 8),
                ],
                if (r.statusLabel != null)
                  StatusChip(
                    label: r.statusLabel!,
                    tone: r.statusTone ?? StatusTone.neutral,
                    dense: true,
                  ),
              ],
            ),
            onTap: () => context.go('/form/${r.docType}/${r.id}'),
          ),
      ],
    );
  });

  // Low-stock list card (inventory workspace — still mock).
  registry.registerCard('inventory_low_stock_list', (context, spec) {
    final lows = MockData.inventoryItems.where((i) => i.belowReorder).toList();
    return ListCard(
      title: 'Low stock items',
      icon: Icons.warning_amber_outlined,
      accentColor: MercantisBrandColors.statusOverdue,
      onSeeAll: () => context.go('/list/Item'),
      rows: [
        for (final it in lows)
          ListCardRow(
            title: '${it.code} · ${it.name}',
            subtitle: '${it.warehouse} · reorder ${it.reorderLevel.toStringAsFixed(0)}',
            trailing: Text('${it.qty.toStringAsFixed(0)} ${it.uom}',
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: MercantisBrandColors.statusOverdue,
              )),
          ),
      ],
    );
  });
}

Widget _buildKpi(HubKpi kpi) {
  return KpiCard(
    title: kpi.title,
    value: kpi.value,
    subtitle: kpi.subtitle,
    trend: kpi.trend,
    trendLabel: kpi.trendLabel,
    icon: kpi.icon,
    accentColor: kpi.accent,
  );
}

DashboardWidgetResult? _widget(DashboardResult result, String id) {
  for (final w in result.widgets) {
    if (w.id == id) return w;
  }
  return null;
}

/// A KPI card whose value is one tile of the real `home` dashboard.
class _HomeMetricCard extends ConsumerWidget {
  const _HomeMetricCard({
    required this.widgetId,
    required this.title,
    required this.icon,
    required this.accent,
  });

  final String widgetId;
  final String title;
  final IconData icon;
  final Color accent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(dashboardResultProvider('home'));
    final value = async.when(
      loading: () => '…',
      error: (_, __) => '—',
      data: (result) {
        final w = _widget(result, widgetId);
        if (w == null || w.isError) return '—';
        return w.type == 'sum'
            ? (w.display ?? '${w.total ?? 0}')
            : '${w.count ?? 0}';
      },
    );
    return KpiCard(title: title, value: value, icon: icon, accentColor: accent);
  }
}

/// The Recent-invoices list card, fed by the `home` dashboard's list tile.
class _HomeRecentInvoicesCard extends ConsumerWidget {
  const _HomeRecentInvoicesCard({required this.title});

  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(dashboardResultProvider('home'));
    final rows = async.maybeWhen(
      data: (result) =>
          _widget(result, 'home_recent_sales')?.rows ?? const <Map<String, String?>>[],
      orElse: () => const <Map<String, String?>>[],
    );
    return ListCard(
      title: title,
      icon: Icons.history,
      accentColor: MercantisBrandColors.accentSales,
      emptyLabel: 'No invoices yet',
      onSeeAll: () => context.go('/list/Sales Invoice'),
      rows: [
        for (final row in rows)
          ListCardRow(
            title: [row['id'], row['customer']]
                .where((v) => v != null && v.isNotEmpty)
                .join('  ·  '),
            subtitle: 'Sales Invoice',
            trailing: row['grand_total'] == null
                ? null
                : Text(row['grand_total']!,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
            onTap: (row['id'] == null || row['id']!.isEmpty)
                ? null
                : () => context.go('/form/Sales Invoice/${row['id']}'),
          ),
      ],
    );
  }
}
