import 'package:flutter/material.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

const inventoryWorkspace = WorkspaceDescriptor(
  id: 'inventory',
  label: 'Inventory & Warehouse',
  shortLabel: 'Inventory',
  icon: Icons.inventory_2_outlined,
  selectedIcon: Icons.inventory_2,
  subtitle: 'Items, stock and warehouse operations',
  accentColor: MercantisBrandColors.accentInventory,
  order: 30,
  sections: [
    WorkspaceSection(
      label: 'Catalogue',
      items: [
        DocTypeWorkspaceItem(docType: 'Item', icon: Icons.inventory_outlined),
        DocTypeWorkspaceItem(docType: 'Item Group',
          icon: Icons.category_outlined),
      ],
    ),
    WorkspaceSection(
      label: 'Stock operations',
      items: [
        DocTypeWorkspaceItem(docType: 'Stock Entry', icon: Icons.swap_horiz),
        DocTypeWorkspaceItem(docType: 'Warehouse',
          icon: Icons.warehouse_outlined),
      ],
    ),
    WorkspaceSection(
      label: 'Workspace tools',
      items: [
        CustomWorkspaceItem(
          routeName: 'low-stock',
          label: 'Low stock report',
          icon: Icons.warning_amber_outlined,
          description: 'Items below reorder level',
        ),
        CustomWorkspaceItem(routeName: 'stock-count',
          label: 'Stock count', icon: Icons.fact_check_outlined,
          description: 'Count the shelf and post the differences'),
      ],
    ),
  ],
  quickActions: [
    QuickAction(id: 'inv_new_item', label: 'New Item',
      icon: Icons.add_box_outlined, docType: 'Item'),
    QuickAction(id: 'inv_new_ste', label: 'New Stock Entry',
      icon: Icons.swap_horiz, docType: 'Stock Entry'),
    QuickAction(id: 'inv_new_wh', label: 'New Warehouse',
      icon: Icons.warehouse_outlined, docType: 'Warehouse'),
  ],
  dashboardCards: [
    DashboardCardSpec.kpi(id: 'inv_bins', title: 'Stocked items'),
    DashboardCardSpec.kpi(id: 'inv_value', title: 'Stock value'),
    DashboardCardSpec.list(id: 'inv_recent', title: 'Recent movements', span: 2),
  ],
);
