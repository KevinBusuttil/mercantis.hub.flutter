import 'package:flutter/material.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

const financeWorkspace = WorkspaceDescriptor(
  id: 'finance',
  label: 'Finance & Collections',
  shortLabel: 'Finance',
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
        // Cost Center is a hierarchical (tree) master like Account, used to tag
        // GL postings; surface it so its tree is reachable.
        DocTypeWorkspaceItem(docType: 'Cost Center',
          icon: Icons.donut_small_outlined),
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
    WorkspaceSection(
      label: 'Banking',
      description: 'Statements in, matches accepted, books agreeing',
      items: [
        DocTypeWorkspaceItem(docType: 'Bank Account',
          icon: Icons.account_balance_outlined),
        CustomWorkspaceItem(routeName: 'bank-reconcile',
          label: 'Bank reconciliation', icon: Icons.rule_outlined,
          description: 'Import statements, match payments, explain the rest'),
        DocTypeWorkspaceItem(docType: 'Bank Statement Line',
          icon: Icons.receipt_long_outlined),
      ],
    ),
    WorkspaceSection(
      label: 'Guided payments',
      items: [
        CustomWorkspaceItem(routeName: 'receive-payment',
          label: 'Receive Payment', icon: Icons.south_east),
        CustomWorkspaceItem(routeName: 'pay-supplier',
          label: 'Pay Supplier', icon: Icons.north_east),
      ],
    ),
    WorkspaceSection(
      label: 'Compliance',
      items: [
        DocTypeWorkspaceItem(docType: 'Tax Filing',
          icon: Icons.fact_check_outlined),
        CustomWorkspaceItem(routeName: 'accountant-export',
          label: 'Accountant export', icon: Icons.download_outlined),
      ],
    ),
  ],
  quickActions: [
    QuickAction(id: 'f_receive_pay', label: 'Receive Payment',
      icon: Icons.south_east, routeName: '/w/finance/receive-payment'),
    QuickAction(id: 'f_pay_supplier', label: 'Pay Supplier',
      icon: Icons.north_east, routeName: '/w/finance/pay-supplier'),
    QuickAction(id: 'f_new_je', label: 'Journal Entry',
      icon: Icons.menu_book_outlined, docType: 'Journal Entry'),
    QuickAction(id: 'f_new_pay', label: 'Payment Entry',
      icon: Icons.payments_outlined, docType: 'Payment Entry'),
  ],
);
