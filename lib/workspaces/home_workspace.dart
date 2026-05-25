import 'package:flutter/material.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

const homeWorkspace = WorkspaceDescriptor(
  id: 'home',
  label: 'Home',
  icon: Icons.home_outlined,
  selectedIcon: Icons.home,
  subtitle: 'Your day at a glance',
  accentColor: MercantisBrandColors.accentHome,
  order: 0,
  quickActions: [
    QuickAction(id: 'new_quote', label: 'New quote',
      icon: Icons.note_add_outlined, docType: 'Quotation',
      color: MercantisBrandColors.accentSales),
    QuickAction(id: 'new_order', label: 'New Sales Order',
      icon: Icons.shopping_cart_outlined, docType: 'Sales Order',
      color: MercantisBrandColors.accentSales),
    QuickAction(id: 'new_invoice', label: 'New invoice',
      icon: Icons.receipt_long_outlined, docType: 'Sales Invoice',
      color: MercantisBrandColors.accentFinance),
    QuickAction(id: 'collect_payment', label: 'Collect payment',
      icon: Icons.payments_outlined, docType: 'Payment Entry',
      color: MercantisBrandColors.accentFinance),
  ],
  dashboardCards: [
    DashboardCardSpec.kpi(id: 'home_sales_today', title: 'Sales today'),
    DashboardCardSpec.kpi(id: 'home_open_orders', title: 'Open orders'),
    DashboardCardSpec.kpi(id: 'home_overdue', title: 'Overdue'),
    DashboardCardSpec.kpi(id: 'home_low_stock', title: 'Low stock'),
    DashboardCardSpec(
      id: 'home_approvals_card',
      title: 'Pending approvals',
      kind: DashboardCardKind.custom,
      span: 2,
    ),
    DashboardCardSpec.list(
      id: 'sales_recent_documents',
      title: 'Recent documents',
      span: 2,
    ),
  ],
);
