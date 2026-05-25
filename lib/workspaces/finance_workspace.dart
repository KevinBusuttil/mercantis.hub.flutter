import 'package:flutter/material.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

const financeWorkspace = WorkspaceDescriptor(
  id: 'finance',
  label: 'Finance & Collections',
  icon: Icons.account_balance_outlined,
  selectedIcon: Icons.account_balance,
  subtitle: 'Ledger, payments, tax',
  accentColor: MercantisBrandColors.accentFinance,
  order: 50,
  sections: [
    WorkspaceSection(
      label: 'Ledger',
      items: [
        DocTypeWorkspaceItem(docType: 'Account',
          icon: Icons.account_tree_outlined),
        DocTypeWorkspaceItem(docType: 'Journal Entry',
          icon: Icons.menu_book_outlined),
      ],
    ),
    WorkspaceSection(
      label: 'Receivables & Payables',
      items: [
        DocTypeWorkspaceItem(docType: 'Sales Invoice',
          icon: Icons.receipt_long_outlined),
        DocTypeWorkspaceItem(docType: 'Purchase Invoice',
          icon: Icons.receipt_outlined),
        DocTypeWorkspaceItem(docType: 'Payment Entry',
          icon: Icons.payments_outlined),
      ],
    ),
  ],
  quickActions: [
    QuickAction(id: 'f_new_je', label: 'Journal Entry',
      icon: Icons.menu_book_outlined, docType: 'Journal Entry'),
    QuickAction(id: 'f_new_pay', label: 'Payment Entry',
      icon: Icons.payments_outlined, docType: 'Payment Entry'),
  ],
);
