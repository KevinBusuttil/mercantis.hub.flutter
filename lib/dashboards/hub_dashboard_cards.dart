import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';
import '../mock/mock_data.dart';

/// Registers dashboard card builders into the Core registry, keyed by spec.id.
void registerHubDashboardCards(WidgetRef ref) {
  final registry = ref.read(dashboardCardHostRegistryProvider);

  // Sales KPIs
  for (final kpi in MockData.salesKpis) {
    registry.registerCard(kpi.id, (context, spec) => _buildKpi(kpi));
  }

  // Inventory KPIs
  for (final kpi in MockData.inventoryKpis) {
    registry.registerCard(kpi.id, (context, spec) => _buildKpi(kpi));
  }

  // Home KPIs (composite — reuse sales kpis for headline numbers)
  registry.registerCard('home_sales_today',
      (context, _) => _buildKpi(MockData.salesKpis[0]));
  registry.registerCard('home_open_orders',
      (context, _) => _buildKpi(MockData.salesKpis[1]));
  registry.registerCard('home_overdue',
      (context, _) => _buildKpi(MockData.salesKpis[2]));
  registry.registerCard('home_low_stock',
      (context, _) => _buildKpi(MockData.inventoryKpis[1]));

  // Recent documents list card (sales)
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

  // Approvals card
  registry.registerCard('home_approvals_card', (context, spec) {
    return DashboardCard(
      title: 'Pending approvals',
      subtitle: 'Tap to review',
      icon: Icons.fact_check_outlined,
      accentColor: MercantisBrandColors.accentApprovals,
      onTap: () => context.go('/w/approvals'),
      child: SizedBox(
        height: 220,
        child: ApprovalInboxList(limit: 4, dense: true),
      ),
    );
  });

  // Low-stock list card
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
