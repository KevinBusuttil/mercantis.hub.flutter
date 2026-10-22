import 'package:flutter/material.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

import '../features/hub_feature.dart';
import '../navigation/hub_surface.dart';

/// Money (Owner) / Finance & Accounting (Accountant). The owner sees the
/// money tasks — get paid, pay, bank, tax, reports; the Accountant view adds
/// the ledger (accounts, cost centres, journals, audit trail, raw bank lines
/// and every payment entry). Fixed assets and property follow their optional
/// features. The workspace id stays `finance` so existing links keep working.
WorkspaceDescriptor financeWorkspace(HubSurface s) => WorkspaceDescriptor(
      id: 'finance',
      label: s.say('Money', 'Finance & Accounting'),
      shortLabel: s.say('Money', 'Finance'),
      icon: Icons.account_balance_wallet_outlined,
      selectedIcon: Icons.account_balance_wallet,
      subtitle: s.say('Get paid, pay, bank and VAT',
          'Payments, banking, tax and the ledger'),
      accentColor: MercantisBrandColors.accentFinance,
      order: 50,
      sections: [
        WorkspaceSection(
          label: 'Get paid',
          items: [
            const CustomWorkspaceItem(routeName: 'receive-payment',
              label: 'Receive payment', icon: Icons.south_east,
              description: 'Record money in and match it to invoices'),
            DocTypeWorkspaceItem(
              docType: 'Payment Entry',
              icon: Icons.payments_outlined,
              label: s.say('Payments received', 'Customer payments'),
              listFilter: const {'payment_type': 'Receive'},
            ),
            const CustomWorkspaceItem(routeName: 'customer-account',
              label: 'Who owes you', icon: Icons.account_box_outlined,
              description: 'Balances, statements and reminders'),
          ],
        ),
        WorkspaceSection(
          label: 'Pay',
          items: [
            const CustomWorkspaceItem(routeName: 'pay-supplier',
              label: 'Pay supplier', icon: Icons.north_east,
              description: 'Record money out against supplier bills'),
            DocTypeWorkspaceItem(docType: 'Purchase Invoice',
              icon: Icons.receipt_outlined,
              label: s.say('Supplier bills', 'Purchase Invoice')),
            DocTypeWorkspaceItem(docType: 'Expense',
              icon: Icons.local_cafe_outlined,
              label: s.say('Expenses', 'Expense')),
          ],
        ),
        WorkspaceSection(
          label: 'Bank',
          description: 'Statements in, matches accepted, books agreeing',
          items: [
            const CustomWorkspaceItem(routeName: 'bank-reconcile',
              label: 'Bank reconciliation', icon: Icons.rule_outlined,
              description: 'Import statements, match payments, explain the '
                  'rest'),
            DocTypeWorkspaceItem(docType: 'Bank Account',
              icon: Icons.account_balance_outlined,
              label: s.say('Bank accounts', 'Bank Account')),
            if (s.accountant)
              const DocTypeWorkspaceItem(docType: 'Bank Statement Line',
                icon: Icons.receipt_long_outlined),
          ],
        ),
        WorkspaceSection(
          label: s.say('VAT, reports & accountant', 'Compliance & reports'),
          items: [
            const CustomWorkspaceItem(routeName: 'reports',
              label: 'Financial reports', icon: Icons.insights_outlined,
              description: 'Profit, balance sheet, cash and who owes what'),
            DocTypeWorkspaceItem(docType: 'Tax Filing',
              icon: Icons.fact_check_outlined,
              label: s.say('VAT returns', 'Tax Filing')),
            const CustomWorkspaceItem(routeName: 'accountant-export',
              label: 'Accountant export', icon: Icons.download_outlined,
              description: 'Hand your books to your accountant'),
          ],
        ),
        if (s.accountant)
          const WorkspaceSection(
            label: 'Ledger',
            description: 'Accounts, journals and the audit trail',
            items: [
              DocTypeWorkspaceItem(docType: 'Account',
                icon: Icons.account_tree_outlined),
              // Cost Center is a hierarchical (tree) master like Account, used
              // to tag GL postings; surface it so its tree is reachable.
              DocTypeWorkspaceItem(docType: 'Cost Center',
                icon: Icons.donut_small_outlined),
              DocTypeWorkspaceItem(docType: 'Journal Entry',
                icon: Icons.menu_book_outlined),
              DocTypeWorkspaceItem(docType: 'Payment Entry',
                icon: Icons.payments_outlined, label: 'All payment entries'),
              CustomWorkspaceItem(routeName: 'audit-trail',
                label: 'Audit trail', icon: Icons.history,
                description: 'Who changed what, when — across the whole '
                    'book'),
            ],
          ),
        if (s.has(HubFeature.fixedAssets))
          const WorkspaceSection(
            label: 'Fixed assets',
            description: 'The register, straight-line schedules, and the '
                'depreciation run',
            items: [
              CustomWorkspaceItem(routeName: 'assets',
                label: 'Asset register',
                icon: Icons.precision_manufacturing_outlined,
                description: 'Book values and one-tap posting of due '
                    'depreciation'),
              DocTypeWorkspaceItem(docType: 'Asset',
                icon: Icons.precision_manufacturing_outlined),
              DocTypeWorkspaceItem(docType: 'Asset Category',
                icon: Icons.category_outlined),
            ],
          ),
        if (s.has(HubFeature.property))
          const WorkspaceSection(
            label: 'Property & tenancies',
            description: 'Leases whose rent bills itself; arrears on one list',
            items: [
              CustomWorkspaceItem(routeName: 'rent-roll',
                label: 'Rent roll', icon: Icons.apartment_outlined,
                description: 'Active tenancies, next billing and arrears'),
              DocTypeWorkspaceItem(docType: 'Property',
                icon: Icons.home_work_outlined),
              DocTypeWorkspaceItem(docType: 'Lease',
                icon: Icons.assignment_outlined),
            ],
          ),
      ],
      quickActions: [
        const QuickAction(id: 'f_receive_pay', label: 'Receive payment',
          icon: Icons.south_east, routeName: '/w/finance/receive-payment'),
        const QuickAction(id: 'f_pay_supplier', label: 'Pay supplier',
          icon: Icons.north_east, routeName: '/w/finance/pay-supplier'),
        QuickAction(id: 'f_new_expense',
          label: s.say('Record expense', 'New Expense'),
          icon: Icons.local_cafe_outlined, docType: 'Expense'),
        const QuickAction(id: 'f_reconcile', label: 'Reconcile bank',
          icon: Icons.rule_outlined, routeName: '/w/finance/bank-reconcile'),
        if (s.accountant) ...const [
          QuickAction(id: 'f_new_je', label: 'Journal Entry',
            icon: Icons.menu_book_outlined, docType: 'Journal Entry'),
          QuickAction(id: 'f_new_pay', label: 'Payment Entry',
            icon: Icons.payments_outlined, docType: 'Payment Entry'),
        ],
      ],
    );
