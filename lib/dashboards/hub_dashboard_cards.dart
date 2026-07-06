import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';
import '../reports/report_providers.dart';
import 'owner_kpis.dart';

/// Registers dashboard card builders into the Core registry, keyed by spec.id.
///
/// Home, Sales and Inventory workspace cards are all fed by their matching Core
/// [DashboardEngine] dashboards (`home` / `sales` / `inventory`) — no mock data.
void registerHubDashboardCards(WidgetRef ref) {
  final registry = ref.read(dashboardCardHostRegistryProvider);

  // ---- Home: real data via the `home` dashboard -------------------------
  registry.registerCard(
    'home_open_orders',
    (context, spec) => _DashboardMetricCard(
      dashboardId: 'home',
      widgetId: 'home_open_orders',
      title: spec.title,
      icon: Icons.shopping_cart_outlined,
      accent: MercantisBrandColors.accentSales,
    ),
  );
  registry.registerCard(
    'home_receivables',
    (context, spec) => _DashboardMetricCard(
      dashboardId: 'home',
      widgetId: 'home_receivables',
      title: spec.title,
      icon: Icons.south_west,
      accent: MercantisBrandColors.accentFinance,
    ),
  );
  registry.registerCard(
    'home_payables',
    (context, spec) => _DashboardMetricCard(
      dashboardId: 'home',
      widgetId: 'home_payables',
      title: spec.title,
      icon: Icons.north_east,
      accent: MercantisBrandColors.accentFinance,
    ),
  );
  registry.registerCard(
    'home_recent_sales',
    (context, spec) => _DashboardListCard(
      dashboardId: 'home',
      widgetId: 'home_recent_sales',
      title: spec.title,
      icon: Icons.history,
      accent: MercantisBrandColors.accentSales,
      titleKeys: const ['id', 'customer'],
      trailingKey: 'grand_total',
      subtitle: 'Sales Invoice',
      rowDocType: 'Sales Invoice',
      idKey: 'id',
      seeAllRoute: '/list/Sales Invoice',
      emptyLabel: 'No invoices yet',
    ),
  );

  // ---- Owner KPI cards (Phase 1A): the daily questions -------------------
  registry.registerCard(
    'home_cash_position',
    (context, spec) => _OwnerKpiCard(
      provider: cashPositionKpiProvider,
      title: spec.title,
      icon: Icons.account_balance_outlined,
      accent: MercantisBrandColors.accentFinance,
      route: '/w/finance',
    ),
  );
  registry.registerCard(
    'home_overdue',
    (context, spec) => _OwnerKpiCard(
      provider: overdueKpiProvider,
      title: spec.title,
      icon: Icons.schedule_outlined,
      accent: MercantisBrandColors.accentFinance,
      route: '/list/Sales Invoice',
    ),
  );
  registry.registerCard(
    'home_bills_due',
    (context, spec) => _OwnerKpiCard(
      provider: billsDueKpiProvider,
      title: spec.title,
      icon: Icons.receipt_long_outlined,
      accent: MercantisBrandColors.accentPurchase,
      route: '/list/Purchase Invoice',
    ),
  );
  registry.registerCard(
    'home_sales_month',
    (context, spec) => _OwnerKpiCard(
      provider: salesMonthKpiProvider,
      title: spec.title,
      icon: Icons.trending_up,
      accent: MercantisBrandColors.accentSales,
      route: '/list/Sales Invoice',
    ),
  );
  registry.registerCard(
    'home_vat_estimate',
    (context, spec) => _OwnerKpiCard(
      provider: vatEstimateKpiProvider,
      title: spec.title,
      icon: Icons.account_balance_wallet_outlined,
      accent: MercantisBrandColors.accentFinance,
      route: '/list/Tax Filing',
    ),
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

  // ---- Sales workspace: real data via the `sales` dashboard -------------
  registry.registerCard(
    'sales_orders',
    (context, spec) => _DashboardMetricCard(
      dashboardId: 'sales',
      widgetId: 'sales_orders',
      title: spec.title,
      icon: Icons.shopping_cart_outlined,
      accent: MercantisBrandColors.accentSales,
    ),
  );
  registry.registerCard(
    'sales_invoiced',
    (context, spec) => _DashboardMetricCard(
      dashboardId: 'sales',
      widgetId: 'sales_invoiced',
      title: spec.title,
      icon: Icons.receipt_long_outlined,
      accent: MercantisBrandColors.accentSales,
    ),
  );
  registry.registerCard(
    'sales_recent',
    (context, spec) => _DashboardListCard(
      dashboardId: 'sales',
      widgetId: 'sales_recent',
      title: spec.title,
      icon: Icons.history,
      accent: MercantisBrandColors.accentSales,
      titleKeys: const ['id', 'customer'],
      trailingKey: 'grand_total',
      subtitle: 'Sales Order',
      rowDocType: 'Sales Order',
      idKey: 'id',
      seeAllRoute: '/list/Sales Order',
      emptyLabel: 'No orders yet',
    ),
  );

  // ---- Inventory workspace: real data via the `inventory` dashboard -----
  registry.registerCard(
    'inv_bins',
    (context, spec) => _DashboardMetricCard(
      dashboardId: 'inventory',
      widgetId: 'inv_bins',
      title: spec.title,
      icon: Icons.inventory_2_outlined,
      accent: MercantisBrandColors.accentInventory,
    ),
  );
  registry.registerCard(
    'inv_value',
    (context, spec) => _DashboardMetricCard(
      dashboardId: 'inventory',
      widgetId: 'inv_value',
      title: spec.title,
      icon: Icons.savings_outlined,
      accent: MercantisBrandColors.accentInventory,
    ),
  );
  registry.registerCard(
    'inv_recent',
    (context, spec) => _DashboardListCard(
      dashboardId: 'inventory',
      widgetId: 'inv_recent',
      title: spec.title,
      icon: Icons.swap_horiz,
      accent: MercantisBrandColors.accentInventory,
      titleKeys: const ['item', 'warehouse'],
      trailingKey: 'qty_change',
      subtitle: 'Stock movement',
      seeAllRoute: '/list/Stock Ledger Entry',
      emptyLabel: 'No movements yet',
    ),
  );
}

DashboardWidgetResult? _widget(DashboardResult result, String id) {
  for (final w in result.widgets) {
    if (w.id == id) return w;
  }
  return null;
}

/// A KPI card whose value is one `count`/`sum` tile of a real dashboard.
/// A KPI tile fed by one of the owner-question providers (cash, overdue,
/// bills due, month sales, VAT estimate). Tapping opens [route].
class _OwnerKpiCard extends ConsumerWidget {
  const _OwnerKpiCard({
    required this.provider,
    required this.title,
    required this.icon,
    required this.accent,
    required this.route,
  });

  final AutoDisposeFutureProvider<OwnerKpi> provider;
  final String title;
  final IconData icon;
  final Color accent;
  final String route;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(provider);
    final value = async.when(
      loading: () => '…',
      error: (_, __) => '—',
      data: (kpi) => '€${kpi.amount.toDouble().toStringAsFixed(2)}',
    );
    final caption = async.valueOrNull?.caption;
    return KpiCard(
      title: caption == null ? title : '$title · $caption',
      value: value,
      icon: icon,
      accentColor: accent,
      onTap: () => context.go(route),
    );
  }
}

class _DashboardMetricCard extends ConsumerWidget {
  const _DashboardMetricCard({
    required this.dashboardId,
    required this.widgetId,
    required this.title,
    required this.icon,
    required this.accent,
  });

  final String dashboardId;
  final String widgetId;
  final String title;
  final IconData icon;
  final Color accent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(dashboardResultProvider(dashboardId));
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

/// A list card whose rows are a real dashboard `list` tile. Each row's title is
/// the joined [titleKeys]; [trailingKey] (if any) is shown bold on the right;
/// tapping routes to `/form/[rowDocType]/<idKey>` when both are supplied.
class _DashboardListCard extends ConsumerWidget {
  const _DashboardListCard({
    required this.dashboardId,
    required this.widgetId,
    required this.title,
    required this.icon,
    required this.accent,
    required this.titleKeys,
    required this.seeAllRoute,
    this.trailingKey,
    this.subtitle,
    this.rowDocType,
    this.idKey,
    this.emptyLabel,
  });

  final String dashboardId;
  final String widgetId;
  final String title;
  final IconData icon;
  final Color accent;
  final List<String> titleKeys;
  final String seeAllRoute;
  final String? trailingKey;
  final String? subtitle;
  final String? rowDocType;
  final String? idKey;
  final String? emptyLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = ref.watch(dashboardResultProvider(dashboardId)).maybeWhen(
          data: (result) =>
              _widget(result, widgetId)?.rows ?? const <Map<String, String?>>[],
          orElse: () => const <Map<String, String?>>[],
        );
    return ListCard(
      title: title,
      icon: icon,
      accentColor: accent,
      emptyLabel: emptyLabel ?? 'Nothing here yet',
      onSeeAll: () => context.go(seeAllRoute),
      rows: [
        for (final row in rows)
          ListCardRow(
            title: titleKeys
                .map((k) => row[k] ?? '')
                .where((v) => v.isNotEmpty)
                .join('  ·  '),
            subtitle: subtitle,
            trailing: (trailingKey == null || row[trailingKey] == null)
                ? null
                : Text(row[trailingKey]!,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
            onTap: (rowDocType == null ||
                    idKey == null ||
                    row[idKey] == null ||
                    row[idKey]!.isEmpty)
                ? null
                : () => context.go('/form/$rowDocType/${row[idKey]}'),
          ),
      ],
    );
  }
}
