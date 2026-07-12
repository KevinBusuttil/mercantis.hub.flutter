import 'package:flutter/material.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

/// The Sales workspace. The Point-of-Sale section and quick action appear
/// only when the POS module is enabled (Retail preset / Settings toggle).
WorkspaceDescriptor salesFulfilmentWorkspace({bool posEnabled = true}) =>
    WorkspaceDescriptor(
      id: 'sales_fulfilment',
      label: 'Sales & Fulfilment',
      shortLabel: 'Sales',
      icon: Icons.point_of_sale_outlined,
      selectedIcon: Icons.point_of_sale,
      subtitle: 'Quotes, orders, deliveries and collections',
      accentColor: MercantisBrandColors.accentSales,
      order: 10,
      sections: [
        const WorkspaceSection(
          label: 'Pipeline',
          description: 'Track demand from first contact to confirmed order',
          items: [
            CustomWorkspaceItem(routeName: 'schedule',
              label: 'Schedule', icon: Icons.calendar_month_outlined,
              description: 'Bookings by resource — day and week boards'),

            DocTypeWorkspaceItem(docType: 'Lead', icon: Icons.flag_outlined),
            DocTypeWorkspaceItem(docType: 'Opportunity', icon: Icons.bolt_outlined),
            DocTypeWorkspaceItem(docType: 'Quotation', icon: Icons.note_outlined),
          ],
        ),
        const WorkspaceSection(
          label: 'Orders & Delivery',
          description: 'Confirm orders, fulfil and dispatch',
          items: [
            DocTypeWorkspaceItem(docType: 'Sales Order',
              icon: Icons.shopping_cart_outlined),
            DocTypeWorkspaceItem(docType: 'Delivery Note',
              icon: Icons.local_shipping_outlined),
          ],
        ),
        const WorkspaceSection(
          label: 'Billing & Collections',
          description: 'Invoice and collect',
          items: [
            DocTypeWorkspaceItem(docType: 'Sales Invoice',
              icon: Icons.receipt_long_outlined),
            DocTypeWorkspaceItem(
              docType: 'Payment Entry',
              icon: Icons.payments_outlined,
              label: 'Customer payments',
              listFilter: {'payment_type': 'Receive'},
            ),
            DocTypeWorkspaceItem(docType: 'Recurring Invoice',
              icon: Icons.event_repeat_outlined),
          ],
        ),
        if (posEnabled)
          const WorkspaceSection(
            label: 'Point of Sale',
            description: 'Over-the-counter cash sales',
            items: [
              CustomWorkspaceItem(routeName: 'pos-till',
                label: 'Open Till', icon: Icons.point_of_sale,
                description: 'Cart, live VAT and cash checkout'),
              DocTypeWorkspaceItem(docType: 'POS Invoice',
                icon: Icons.point_of_sale_outlined),
              DocTypeWorkspaceItem(docType: 'POS Profile',
                icon: Icons.storefront_outlined),
              DocTypeWorkspaceItem(docType: 'POS Session',
                icon: Icons.schedule_outlined),
            ],
          ),
        const WorkspaceSection(
          label: 'Online channels',
          description: 'Storefront orders staged for review, then posted as '
              'official invoices with stock and COGS',
          items: [
            DocTypeWorkspaceItem(docType: 'Sales Channel',
              icon: Icons.storefront_outlined),
            DocTypeWorkspaceItem(docType: 'Channel Order',
              icon: Icons.shopping_bag_outlined),
            DocTypeWorkspaceItem(docType: 'Channel Product',
              icon: Icons.qr_code_2_outlined, label: 'SKU mappings'),
            DocTypeWorkspaceItem(docType: 'Channel Sync Log',
              icon: Icons.sync_outlined),
          ],
        ),
        const WorkspaceSection(
          label: 'Customer base',
          items: [
            DocTypeWorkspaceItem(docType: 'Customer', icon: Icons.person_outline),
            DocTypeWorkspaceItem(docType: 'Contact', icon: Icons.contact_phone_outlined),
            CustomWorkspaceItem(
              routeName: 'customer-account',
              label: 'Customer accounts',
              icon: Icons.account_box_outlined,
              description: 'Statements, balances and activity',
            ),
          ],
        ),
      ],
      quickActions: [
        const QuickAction(id: 'sf_new_quote', label: 'New Quotation',
          icon: Icons.note_add_outlined, docType: 'Quotation'),
        const QuickAction(id: 'sf_new_order', label: 'New Sales Order',
          icon: Icons.shopping_cart_outlined, docType: 'Sales Order'),
        const QuickAction(id: 'sf_new_dn', label: 'New Delivery Note',
          icon: Icons.local_shipping_outlined, docType: 'Delivery Note'),
        const QuickAction(id: 'sf_new_invoice', label: 'New Sales Invoice',
          icon: Icons.receipt_long_outlined, docType: 'Sales Invoice'),
        const QuickAction(id: 'sf_collect', label: 'Collect payment',
          icon: Icons.payments_outlined, docType: 'Payment Entry'),
        if (posEnabled)
          const QuickAction(id: 'sf_pos_till', label: 'Open Till',
            icon: Icons.point_of_sale, routeName: '/w/sales_fulfilment/pos-till'),
      ],
      dashboardCards: const [
        DashboardCardSpec.kpi(id: 'sales_orders', title: 'Sales Orders'),
        DashboardCardSpec.kpi(id: 'sales_invoiced', title: 'Invoiced'),
        DashboardCardSpec.list(id: 'sales_recent', title: 'Recent orders', span: 2),
      ],
    );
