import 'package:flutter/material.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

import '../features/hub_feature.dart';
import '../navigation/hub_surface.dart';

/// The Sales workspace. Its core — customers, quotes, invoices, payments
/// received — is essential; every other section (till, tables, rentals,
/// online channels, memberships, pipeline, deliveries) appears only when its
/// optional feature is on.
WorkspaceDescriptor salesFulfilmentWorkspace(HubSurface s) {
  final stock = s.has(HubFeature.stock);
  final pos = s.has(HubFeature.pos);
  final schedule =
      s.has(HubFeature.appointments) || s.has(HubFeature.fieldService);
  final pipeline = s.has(HubFeature.salesPipeline);
  return WorkspaceDescriptor(
    id: 'sales_fulfilment',
    label: s.say('Sales', 'Sales & Fulfilment'),
    shortLabel: 'Sales',
    icon: Icons.sell_outlined,
    selectedIcon: Icons.sell,
    subtitle: s.say('Customers, quotes, invoices and payments',
        'Quotes, orders, deliveries and collections'),
    accentColor: MercantisBrandColors.accentSales,
    order: 10,
    sections: [
      WorkspaceSection(
        label: s.say('Customers', 'Customer base'),
        items: [
          DocTypeWorkspaceItem(docType: 'Customer',
            icon: Icons.person_outline,
            label: s.plainLanguage ? 'Customers' : null),
          const CustomWorkspaceItem(
            routeName: 'customer-account',
            label: 'Statements & balances',
            icon: Icons.account_box_outlined,
            description: 'What each customer owes, with a statement to send',
          ),
          if (s.accountant)
            const DocTypeWorkspaceItem(docType: 'Contact',
              icon: Icons.contact_phone_outlined),
        ],
      ),
      WorkspaceSection(
        label: s.say('Quotes & orders', 'Pipeline & orders'),
        description: s.say(null, 'Track demand from quote to delivery'),
        items: [
          DocTypeWorkspaceItem(docType: 'Quotation',
            icon: Icons.note_outlined,
            label: s.plainLanguage ? 'Quotes' : null),
          if (stock || s.accountant)
            DocTypeWorkspaceItem(docType: 'Sales Order',
              icon: Icons.shopping_cart_outlined,
              label: s.plainLanguage ? 'Sales orders' : null),
          if (stock)
            DocTypeWorkspaceItem(docType: 'Delivery Note',
              icon: Icons.local_shipping_outlined,
              label: s.plainLanguage ? 'Deliveries' : null),
        ],
      ),
      WorkspaceSection(
        label: s.say('Invoices & payments', 'Billing & Collections'),
        items: [
          DocTypeWorkspaceItem(docType: 'Sales Invoice',
            icon: Icons.receipt_long_outlined,
            label: s.plainLanguage ? 'Invoices' : null),
          DocTypeWorkspaceItem(
            docType: 'Payment Entry',
            icon: Icons.payments_outlined,
            label: s.say('Payments received', 'Customer payments'),
            listFilter: const {'payment_type': 'Receive'},
          ),
          DocTypeWorkspaceItem(docType: 'Recurring Invoice',
            icon: Icons.event_repeat_outlined,
            label: s.plainLanguage ? 'Repeat invoices' : null),
        ],
      ),
      if (pipeline || schedule)
        WorkspaceSection(
          label: s.say('Leads & bookings', 'Pipeline'),
          items: [
            if (pipeline) ...const [
              DocTypeWorkspaceItem(docType: 'Lead', icon: Icons.flag_outlined),
              DocTypeWorkspaceItem(docType: 'Opportunity',
                icon: Icons.bolt_outlined),
            ],
            if (schedule)
              const CustomWorkspaceItem(routeName: 'schedule',
                label: 'Schedule', icon: Icons.calendar_month_outlined,
                description: 'Bookings by resource — day and week boards'),
          ],
        ),
      if (pos)
        WorkspaceSection(
          label: s.say('Till', 'Point of Sale'),
          description: 'Over-the-counter sales on this device',
          items: [
            const CustomWorkspaceItem(routeName: 'pos-till',
              label: 'Open till', icon: Icons.point_of_sale,
              description: 'Cart, live VAT and checkout'),
            DocTypeWorkspaceItem(docType: 'POS Invoice',
              icon: Icons.point_of_sale_outlined,
              label: s.plainLanguage ? 'Till receipts' : null),
            DocTypeWorkspaceItem(docType: 'POS Session',
              icon: Icons.schedule_outlined,
              label: s.plainLanguage ? 'Till sessions & Z-reports' : null),
            DocTypeWorkspaceItem(docType: 'POS Profile',
              icon: Icons.storefront_outlined,
              label: s.plainLanguage ? 'Till settings' : null),
          ],
        ),
      if (s.has(HubFeature.hospitality))
        const WorkspaceSection(
          label: 'Tables & kitchen',
          items: [
            CustomWorkspaceItem(routeName: 'tables',
              label: 'Tables', icon: Icons.table_bar_outlined,
              description: 'Floor map, tabs and settlement'),
            CustomWorkspaceItem(routeName: 'kitchen',
              label: 'Kitchen', icon: Icons.restaurant_outlined,
              description: 'Open tickets on the rail, oldest first'),
            CustomWorkspaceItem(routeName: 'hospitality-audit',
              label: 'Void & comp audit', icon: Icons.fact_check_outlined,
              description: 'Voids, comps and cancelled receipts with '
                  'reasons and value'),
          ],
        ),
      if (s.has(HubFeature.rentals))
        const WorkspaceSection(
          label: 'Rentals',
          description: 'Hire out units — availability held on the '
              'calendar, deposits as liabilities, days billed at return',
          items: [
            CustomWorkspaceItem(routeName: 'rentals',
              label: 'Hire desk', icon: Icons.handshake_outlined,
              description: 'The fleet, who has what out, hand over and '
                  'return'),
            DocTypeWorkspaceItem(docType: 'Rental Agreement',
              icon: Icons.assignment_outlined),
            DocTypeWorkspaceItem(docType: 'Rental Unit',
              icon: Icons.construction_outlined),
          ],
        ),
      if (s.has(HubFeature.onlineChannels))
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
      if (s.has(HubFeature.memberships))
        const WorkspaceSection(
          label: 'Memberships',
          description: 'Plans whose fees bill themselves; pause without '
              'back-billing',
          items: [
            CustomWorkspaceItem(routeName: 'members',
              label: 'Members', icon: Icons.card_membership_outlined,
              description: 'Who\'s on what plan, next billing, arrears'),
            DocTypeWorkspaceItem(docType: 'Membership',
              icon: Icons.badge_outlined),
            DocTypeWorkspaceItem(docType: 'Membership Plan',
              icon: Icons.workspace_premium_outlined),
          ],
        ),
    ],
    quickActions: [
      if (pos)
        const QuickAction(id: 'sf_pos_till', label: 'Open till',
          icon: Icons.point_of_sale, routeName: '/w/sales_fulfilment/pos-till'),
      QuickAction(id: 'sf_new_invoice',
        label: s.say('New invoice', 'New Sales Invoice'),
        icon: Icons.receipt_long_outlined, docType: 'Sales Invoice'),
      QuickAction(id: 'sf_new_quote',
        label: s.say('New quote', 'New Quotation'),
        icon: Icons.note_add_outlined, docType: 'Quotation'),
      QuickAction(id: 'sf_collect',
        label: s.say('Receive payment', 'Collect payment'),
        icon: Icons.payments_outlined,
        routeName: '/w/finance/receive-payment'),
      QuickAction(id: 'sf_new_customer',
        label: s.say('New customer', 'New Customer'),
        icon: Icons.person_add_alt, docType: 'Customer'),
      if (stock || s.accountant)
        QuickAction(id: 'sf_new_order',
          label: s.say('New sales order', 'New Sales Order'),
          icon: Icons.shopping_cart_outlined, docType: 'Sales Order'),
      if (stock)
        QuickAction(id: 'sf_new_dn',
          label: s.say('New delivery', 'New Delivery Note'),
          icon: Icons.local_shipping_outlined, docType: 'Delivery Note'),
    ],
    dashboardCards: [
      if (stock)
        DashboardCardSpec.kpi(id: 'sales_orders',
            title: s.say('Sales orders', 'Sales Orders')),
      const DashboardCardSpec.kpi(id: 'sales_invoiced', title: 'Invoiced'),
      if (stock)
        DashboardCardSpec.list(id: 'sales_recent',
            title: s.say('Recent orders', 'Recent orders'), span: 2),
    ],
  );
}
