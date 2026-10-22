import 'package:flutter/material.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

import '../features/hub_feature.dart';
import '../navigation/hub_surface.dart';

/// Buying: supplier bills, expenses and paying suppliers are essential;
/// purchase receipts follow stock, supplier quotations follow stock or the
/// Accountant view.
WorkspaceDescriptor purchasingWorkspace(HubSurface s) {
  final stock = s.has(HubFeature.stock);
  return WorkspaceDescriptor(
    id: 'purchasing',
    label: s.say('Buying', 'Purchasing & Receiving'),
    shortLabel: 'Buying',
    icon: Icons.shopping_basket_outlined,
    selectedIcon: Icons.shopping_basket,
    subtitle: s.say('Bills, expenses and suppliers',
        'Orders, receipts and supplier billing'),
    accentColor: MercantisBrandColors.accentPurchase,
    order: 20,
    sections: [
      WorkspaceSection(
        label: s.say('Bills & expenses', 'Billing & Payments'),
        items: [
          DocTypeWorkspaceItem(docType: 'Purchase Invoice',
            icon: Icons.receipt_outlined,
            label: s.plainLanguage ? 'Supplier bills' : null),
          DocTypeWorkspaceItem(docType: 'Expense',
            icon: Icons.local_cafe_outlined,
            label: s.plainLanguage ? 'Expenses' : null),
          DocTypeWorkspaceItem(
            docType: 'Payment Entry',
            icon: Icons.payments_outlined,
            label: s.say('Payments to suppliers', 'Supplier payments'),
            listFilter: const {'payment_type': 'Pay'},
          ),
          const CustomWorkspaceItem(routeName: 'captures',
            label: 'Receipt captures', icon: Icons.document_scanner_outlined,
            description: 'Scanned receipts waiting to become expenses or '
                'bills'),
        ],
      ),
      WorkspaceSection(
        label: s.say('Suppliers', 'Supplier base'),
        items: [
          DocTypeWorkspaceItem(docType: 'Supplier',
            icon: Icons.business_outlined,
            label: s.plainLanguage ? 'Suppliers' : null),
        ],
      ),
      WorkspaceSection(
        label: s.say('Orders & goods received', 'Orders & Receipts'),
        items: [
          if (stock || s.accountant)
            const DocTypeWorkspaceItem(docType: 'Supplier Quotation',
              icon: Icons.request_quote_outlined),
          DocTypeWorkspaceItem(docType: 'Purchase Order',
            icon: Icons.shopping_basket_outlined,
            label: s.plainLanguage ? 'Purchase orders' : null),
          if (stock)
            DocTypeWorkspaceItem(docType: 'Purchase Receipt',
              icon: Icons.move_to_inbox_outlined,
              label: s.plainLanguage ? 'Goods received' : null),
        ],
      ),
    ],
    quickActions: [
      QuickAction(id: 'p_new_expense',
        label: s.say('Record expense', 'New Expense'),
        icon: Icons.local_cafe_outlined, docType: 'Expense'),
      QuickAction(id: 'p_new_pinv',
        label: s.say('New supplier bill', 'New Purchase Invoice'),
        icon: Icons.receipt_outlined, docType: 'Purchase Invoice'),
      const QuickAction(id: 'p_pay', label: 'Pay supplier',
        icon: Icons.north_east, routeName: '/w/finance/pay-supplier'),
      const QuickAction(id: 'p_captures', label: 'Receipt captures',
        icon: Icons.document_scanner_outlined,
        routeName: '/w/purchasing/captures'),
      if (stock)
        QuickAction(id: 'p_new_receipt',
          label: s.say('Receive goods', 'New Purchase Receipt'),
          icon: Icons.move_to_inbox_outlined, docType: 'Purchase Receipt'),
      QuickAction(id: 'p_new_po',
        label: s.say('New purchase order', 'New Purchase Order'),
        icon: Icons.shopping_basket_outlined, docType: 'Purchase Order'),
      if (stock || s.accountant)
        const QuickAction(id: 'p_new_sq', label: 'New Supplier Quotation',
          icon: Icons.request_quote_outlined, docType: 'Supplier Quotation'),
    ],
  );
}
