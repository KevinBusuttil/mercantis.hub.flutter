import 'package:flutter/material.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

import '../navigation/hub_surface.dart';

/// Stock — shown when the Stock feature is on (Trade, Retail, Manufacturing,
/// Mixed profiles, or Settings › Features).
WorkspaceDescriptor inventoryWorkspace(HubSurface s) => WorkspaceDescriptor(
      id: 'inventory',
      label: s.say('Stock', 'Inventory & Warehouse'),
      shortLabel: 'Stock',
      icon: Icons.inventory_2_outlined,
      selectedIcon: Icons.inventory_2,
      subtitle: s.say('What you have, where, and what it is worth',
          'Items, stock and warehouse operations'),
      accentColor: MercantisBrandColors.accentInventory,
      order: 30,
      sections: [
        WorkspaceSection(
          label: s.say('Products', 'Catalogue'),
          items: [
            DocTypeWorkspaceItem(docType: 'Item',
              icon: Icons.inventory_outlined,
              label: s.plainLanguage ? 'Products & services' : null),
            const DocTypeWorkspaceItem(docType: 'Item Group',
              icon: Icons.category_outlined),
          ],
        ),
        WorkspaceSection(
          label: s.say('Stock tasks', 'Stock operations'),
          items: [
            DocTypeWorkspaceItem(docType: 'Stock Entry',
              icon: Icons.swap_horiz,
              label: s.plainLanguage ? 'Stock movements' : null),
            const CustomWorkspaceItem(routeName: 'stock-count',
              label: 'Stock count', icon: Icons.fact_check_outlined,
              description: 'Count the shelf and post the differences'),
            const CustomWorkspaceItem(
              routeName: 'low-stock',
              label: 'Low stock',
              icon: Icons.warning_amber_outlined,
              description: 'Items below reorder level',
            ),
            DocTypeWorkspaceItem(docType: 'Warehouse',
              icon: Icons.warehouse_outlined,
              label: s.plainLanguage ? 'Locations / warehouses' : null),
          ],
        ),
      ],
      quickActions: [
        QuickAction(id: 'inv_new_ste',
          label: s.say('Move or adjust stock', 'New Stock Entry'),
          icon: Icons.swap_horiz, docType: 'Stock Entry'),
        const QuickAction(id: 'inv_count', label: 'Count stock',
          icon: Icons.fact_check_outlined,
          routeName: '/w/inventory/stock-count'),
        QuickAction(id: 'inv_new_item',
          label: s.say('New product or service', 'New Item'),
          icon: Icons.add_box_outlined, docType: 'Item'),
        if (s.accountant)
          const QuickAction(id: 'inv_new_wh', label: 'New Warehouse',
            icon: Icons.warehouse_outlined, docType: 'Warehouse'),
      ],
      dashboardCards: const [
        DashboardCardSpec.kpi(id: 'inv_bins', title: 'Stocked items'),
        DashboardCardSpec.kpi(id: 'inv_value', title: 'Stock value'),
        DashboardCardSpec.list(id: 'inv_recent', title: 'Recent movements',
            span: 2),
      ],
    );
