import 'package:flutter/material.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

const salesFulfilmentWorkspace = WorkspaceDescriptor(
  id: 'sales_fulfilment',
  label: 'Sales & Fulfilment',
  icon: Icons.point_of_sale_outlined,
  selectedIcon: Icons.point_of_sale,
  subtitle: 'Quotes, orders, deliveries and collections',
  accentColor: MercantisBrandColors.accentSales,
  order: 10,
  sections: [
    WorkspaceSection(
      label: 'Pipeline',
      description: 'Track demand from first contact to confirmed order',
      items: [
        DocTypeWorkspaceItem(docType: 'Lead', icon: Icons.flag_outlined),
        DocTypeWorkspaceItem(docType: 'Opportunity', icon: Icons.bolt_outlined),
        DocTypeWorkspaceItem(docType: 'Quotation', icon: Icons.note_outlined),
      ],
    ),
    WorkspaceSection(
      label: 'Orders & Delivery',
      description: 'Confirm orders, fulfil and dispatch',
      items: [
        DocTypeWorkspaceItem(docType: 'Sales Order',
          icon: Icons.shopping_cart_outlined),
        DocTypeWorkspaceItem(docType: 'Delivery Note',
          icon: Icons.local_shipping_outlined),
      ],
    ),
    WorkspaceSection(
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
      ],
    ),
    WorkspaceSection(
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
    QuickAction(id: 'sf_new_quote', label: 'New Quotation',
      icon: Icons.note_add_outlined, docType: 'Quotation'),
    QuickAction(id: 'sf_new_order', label: 'New Sales Order',
      icon: Icons.shopping_cart_outlined, docType: 'Sales Order'),
    QuickAction(id: 'sf_new_dn', label: 'New Delivery Note',
      icon: Icons.local_shipping_outlined, docType: 'Delivery Note'),
    QuickAction(id: 'sf_new_invoice', label: 'New Sales Invoice',
      icon: Icons.receipt_long_outlined, docType: 'Sales Invoice'),
    QuickAction(id: 'sf_collect', label: 'Collect payment',
      icon: Icons.payments_outlined, docType: 'Payment Entry'),
  ],
  dashboardCards: [
    DashboardCardSpec.kpi(id: 'sales_today',     title: 'Sales today'),
    DashboardCardSpec.kpi(id: 'open_orders',     title: 'Open orders'),
    DashboardCardSpec.kpi(id: 'overdue_receivables', title: 'Overdue'),
    DashboardCardSpec.kpi(id: 'avg_lead_time',   title: 'Lead time'),
    DashboardCardSpec.list(id: 'sales_recent_documents', title: 'Recent', span: 2),
  ],
);
