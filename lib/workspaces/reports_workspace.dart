import 'package:flutter/material.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

const reportsWorkspace = WorkspaceDescriptor(
  id: 'reports',
  label: 'Reports & Insights',
  shortLabel: 'Reports',
  icon: Icons.insights_outlined,
  selectedIcon: Icons.insights,
  subtitle: 'Dashboards and operational KPIs',
  accentColor: MercantisBrandColors.accentReports,
  order: 70,
  sections: [
    WorkspaceSection(label: 'Build', items: [
      CustomWorkspaceItem(routeName: 'report-builder',
        label: 'Report builder', icon: Icons.tune),
    ]),
    WorkspaceSection(label: 'Coming soon', items: [
      CustomWorkspaceItem(routeName: 'sales-dashboard',
        label: 'Sales dashboard', icon: Icons.bar_chart),
      CustomWorkspaceItem(routeName: 'stock-dashboard',
        label: 'Stock dashboard', icon: Icons.show_chart),
      CustomWorkspaceItem(routeName: 'finance-dashboard',
        label: 'Finance dashboard', icon: Icons.pie_chart_outline),
    ]),
  ],
);
