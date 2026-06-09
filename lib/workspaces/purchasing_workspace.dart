import 'package:flutter/material.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

const purchasingWorkspace = WorkspaceDescriptor(
  id: 'purchasing',
  label: 'Purchasing & Receiving',
  icon: Icons.shopping_basket_outlined,
  selectedIcon: Icons.shopping_basket,
  subtitle: 'Orders, receipts and supplier billing',
  accentColor: MercantisBrandColors.accentPurchase,
  order: 20,
  sections: [
    WorkspaceSection(
      label: 'Orders & Receipts',
      items: [
        DocTypeWorkspaceItem(docType: 'Supplier Quotation',
          icon: Icons.request_quote_outlined),
        DocTypeWorkspaceItem(docType: 'Purchase Order',
          icon: Icons.shopping_basket_outlined),
        DocTypeWorkspaceItem(docType: 'Purchase Receipt',
          icon: Icons.move_to_inbox_outlined),
      ],
    ),
    WorkspaceSection(
      label: 'Billing & Payments',
      items: [
        DocTypeWorkspaceItem(docType: 'Purchase Invoice',
          icon: Icons.receipt_outlined),
        DocTypeWorkspaceItem(
          docType: 'Payment Entry',
          icon: Icons.payments_outlined,
          label: 'Supplier payments',
          listFilter: {'payment_type': 'Pay'},
        ),
      ],
    ),
    WorkspaceSection(
      label: 'Supplier base',
      items: [
        DocTypeWorkspaceItem(docType: 'Supplier', icon: Icons.business_outlined),
      ],
    ),
  ],
  quickActions: [
    QuickAction(id: 'p_new_sq', label: 'New Supplier Quotation',
      icon: Icons.request_quote_outlined, docType: 'Supplier Quotation'),
    QuickAction(id: 'p_new_po', label: 'New Purchase Order',
      icon: Icons.shopping_basket_outlined, docType: 'Purchase Order'),
    QuickAction(id: 'p_new_receipt', label: 'New Purchase Receipt',
      icon: Icons.move_to_inbox_outlined, docType: 'Purchase Receipt'),
    QuickAction(id: 'p_new_pinv', label: 'New Purchase Invoice',
      icon: Icons.receipt_outlined, docType: 'Purchase Invoice'),
    QuickAction(id: 'p_pay', label: 'Pay supplier',
      icon: Icons.payments_outlined, docType: 'Payment Entry'),
  ],
);
