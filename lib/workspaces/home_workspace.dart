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
    QuickAction(id: 'scan_receipt', label: 'Scan receipt',
      icon: Icons.document_scanner_outlined,
      routeName: '/w/home/scan-receipt',
      color: MercantisBrandColors.accentPurchase),
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
  // Cards fed by the real `home` dashboard (Core DashboardEngine), not mock.
  dashboardCards: [
    DashboardCardSpec.kpi(id: 'home_open_orders', title: 'Open Sales Orders'),
    DashboardCardSpec.kpi(id: 'home_receivables', title: 'Receivables'),
    DashboardCardSpec.kpi(id: 'home_payables', title: 'Payables'),
    DashboardCardSpec(
      id: 'home_approvals_card',
      title: 'Pending approvals',
      kind: DashboardCardKind.custom,
      span: 2,
    ),
    DashboardCardSpec.list(
      id: 'home_recent_sales',
      title: 'Recent invoices',
      span: 2,
    ),
  ],
);
