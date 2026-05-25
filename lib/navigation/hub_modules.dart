import 'package:flutter/material.dart';
import 'hub_module.dart';

/// All Hub modules in display order.
///
/// Mirrors the Swift Hub navigation: CRM, Selling, Buying, Stock, Accounting,
/// Setup. Each module exposes its DocTypes through [HubMenuGroup]s rather
/// than jumping straight to a single arbitrary list.
abstract final class HubModules {
  static const List<HubModule> all = [
    crm,
    selling,
    buying,
    stock,
    accounting,
    setup,
  ];

  static HubModule? byId(String id) {
    for (final m in all) {
      if (m.id == id) return m;
    }
    return null;
  }

  static const HubModule crm = HubModule(
    id: 'crm',
    label: 'CRM',
    icon: Icons.people_outline,
    selectedIcon: Icons.people,
    subtitle: 'Leads, opportunities and customers',
    groups: [
      HubMenuGroup(label: 'Sales Pipeline', items: [
        HubDocTypeItem(docType: 'Lead'),
        HubDocTypeItem(docType: 'Opportunity'),
      ]),
      HubMenuGroup(label: 'Masters', items: [
        HubDocTypeItem(docType: 'Contact'),
        HubDocTypeItem(docType: 'Customer'),
      ]),
    ],
  );

  static const HubModule selling = HubModule(
    id: 'selling',
    label: 'Selling',
    icon: Icons.receipt_long_outlined,
    selectedIcon: Icons.receipt_long,
    subtitle: 'Quotations, orders and invoices',
    groups: [
      HubMenuGroup(label: 'Transactions', items: [
        HubDocTypeItem(docType: 'Quotation'),
        HubDocTypeItem(docType: 'Sales Order'),
        HubDocTypeItem(docType: 'Sales Invoice'),
      ]),
    ],
  );

  static const HubModule buying = HubModule(
    id: 'buying',
    label: 'Buying',
    icon: Icons.shopping_cart_outlined,
    selectedIcon: Icons.shopping_cart,
    subtitle: 'Suppliers and purchasing',
    groups: [
      HubMenuGroup(label: 'Suppliers', items: [
        HubDocTypeItem(docType: 'Supplier'),
      ]),
      HubMenuGroup(label: 'Transactions', items: [
        HubDocTypeItem(docType: 'Purchase Order'),
        HubDocTypeItem(docType: 'Purchase Invoice'),
      ]),
    ],
  );

  static const HubModule stock = HubModule(
    id: 'stock',
    label: 'Stock',
    icon: Icons.inventory_2_outlined,
    selectedIcon: Icons.inventory_2,
    subtitle: 'Items, warehouses and movements',
    groups: [
      HubMenuGroup(label: 'Catalogue', items: [
        HubDocTypeItem(docType: 'Item Group'),
        HubDocTypeItem(docType: 'Item'),
      ]),
      HubMenuGroup(label: 'Warehouses', items: [
        HubDocTypeItem(docType: 'Warehouse'),
      ]),
      HubMenuGroup(label: 'Movements', items: [
        HubDocTypeItem(docType: 'Stock Entry'),
      ]),
    ],
  );

  static const HubModule accounting = HubModule(
    id: 'accounting',
    label: 'Accounting',
    icon: Icons.account_balance_outlined,
    selectedIcon: Icons.account_balance,
    subtitle: 'Chart of accounts and vouchers',
    groups: [
      HubMenuGroup(label: 'Chart', items: [
        HubDocTypeItem(docType: 'Account'),
      ]),
      HubMenuGroup(label: 'Vouchers', items: [
        HubDocTypeItem(docType: 'Journal Entry'),
        HubDocTypeItem(docType: 'Payment Entry'),
      ]),
    ],
  );

  static const HubModule setup = HubModule(
    id: 'setup',
    label: 'Setup',
    icon: Icons.settings_outlined,
    selectedIcon: Icons.settings,
    subtitle: 'Companies, currencies and configuration',
    groups: [
      HubMenuGroup(label: 'Company', items: [
        HubDocTypeItem(docType: 'Company'),
        HubDocTypeItem(docType: 'Fiscal Year'),
      ]),
      HubMenuGroup(label: 'Accounting', items: [
        HubDocTypeItem(docType: 'Cost Center'),
        HubDocTypeItem(docType: 'Currency'),
      ]),
    ],
  );
}
