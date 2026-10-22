import 'package:flutter/material.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

import '../features/hub_feature.dart';
import '../navigation/hub_surface.dart';

/// Home / Today: the owner's daily questions as cards, and the handful of
/// tasks they do most, in the order they do them. Profile features add their
/// own entry points (open the till, move stock); nothing irrelevant shows.
WorkspaceDescriptor homeWorkspace(HubSurface s) => WorkspaceDescriptor(
      id: 'home',
      label: s.say('Today', 'Home'),
      icon: Icons.today_outlined,
      selectedIcon: Icons.today,
      subtitle: s.say('What needs your attention', 'Your day at a glance'),
      accentColor: MercantisBrandColors.accentHome,
      order: 0,
      quickActions: [
        if (s.has(HubFeature.pos))
          const QuickAction(id: 'open_till', label: 'Open till',
            icon: Icons.point_of_sale,
            routeName: '/w/sales_fulfilment/pos-till',
            color: MercantisBrandColors.accentSales),
        const QuickAction(id: 'new_invoice', label: 'New invoice',
          icon: Icons.receipt_long_outlined, docType: 'Sales Invoice',
          color: MercantisBrandColors.accentFinance),
        const QuickAction(id: 'new_quote', label: 'New quote',
          icon: Icons.note_add_outlined, docType: 'Quotation',
          color: MercantisBrandColors.accentSales),
        // Guided: pick the customer, see what they owe, allocate — rather
        // than a blank Payment Entry form.
        const QuickAction(id: 'collect_payment', label: 'Receive payment',
          icon: Icons.south_east, routeName: '/w/finance/receive-payment',
          color: MercantisBrandColors.accentFinance),
        const QuickAction(id: 'record_expense', label: 'Record expense',
          icon: Icons.local_cafe_outlined, docType: 'Expense',
          color: MercantisBrandColors.accentPurchase),
        const QuickAction(id: 'scan_receipt', label: 'Scan receipt',
          icon: Icons.document_scanner_outlined,
          routeName: '/w/home/scan-receipt',
          color: MercantisBrandColors.accentPurchase),
        if (s.has(HubFeature.stock)) ...[
          QuickAction(id: 'move_stock',
            label: s.say('Move or adjust stock', 'New Stock Entry'),
            icon: Icons.swap_horiz, docType: 'Stock Entry',
            color: MercantisBrandColors.accentInventory),
          QuickAction(id: 'receive_goods',
            label: s.say('Receive goods', 'New Purchase Receipt'),
            icon: Icons.move_to_inbox_outlined, docType: 'Purchase Receipt',
            color: MercantisBrandColors.accentInventory),
          QuickAction(id: 'new_order',
            label: s.say('New sales order', 'New Sales Order'),
            icon: Icons.shopping_cart_outlined, docType: 'Sales Order',
            color: MercantisBrandColors.accentSales),
        ],
        const QuickAction(id: 'setup_checklist', label: 'Setup checklist',
          icon: Icons.checklist_outlined,
          routeName: '/w/home/setup-checklist',
          color: MercantisBrandColors.accentSetup),
        const QuickAction(id: 'notifications', label: 'Notifications',
          icon: Icons.notifications_outlined,
          routeName: '/w/home/notifications',
          color: MercantisBrandColors.accentHome),
        const QuickAction(id: 'recents', label: 'Recents',
          icon: Icons.history,
          routeName: '/w/home/recents',
          color: MercantisBrandColors.accentHome),
      ],
      // Cards fed by the real `home` dashboard and owner KPIs, not mock.
      dashboardCards: [
        const DashboardCardSpec.kpi(id: 'home_cash_position',
            title: 'Cash position'),
        const DashboardCardSpec.kpi(id: 'home_overdue', title: 'Overdue'),
        const DashboardCardSpec.kpi(id: 'home_bills_due', title: 'Bills due'),
        const DashboardCardSpec.kpi(id: 'home_sales_month',
            title: 'Sales this month'),
        const DashboardCardSpec.kpi(id: 'home_vat_estimate',
            title: 'VAT estimate'),
        if (s.has(HubFeature.stock))
          const DashboardCardSpec.kpi(id: 'home_open_orders',
              title: 'Open sales orders'),
        if (s.accountant) ...[
          const DashboardCardSpec.kpi(id: 'home_receivables',
              title: 'Receivables'),
          const DashboardCardSpec.kpi(id: 'home_payables', title: 'Payables'),
        ],
        // Approvals route between people — a Team concept; a single Solo
        // operator has nobody to approve for.
        if (s.teamConnected)
          const DashboardCardSpec(
            id: 'home_approvals_card',
            title: 'Pending approvals',
            kind: DashboardCardKind.custom,
            span: 2,
          ),
        DashboardCardSpec.list(
          id: 'home_recent_sales',
          title: s.say('Recent invoices', 'Recent invoices'),
          span: 2,
        ),
      ],
    );
