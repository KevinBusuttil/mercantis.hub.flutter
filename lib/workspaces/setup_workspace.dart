import 'package:flutter/material.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

import '../features/hub_feature.dart';
import '../navigation/hub_surface.dart';

/// Settings & setup. Owner essentials first (checklist, features, business
/// details); accounting masters in the Accountant view; users, roles and the
/// DocType/workflow/custom-field designers only with system configuration on.
WorkspaceDescriptor setupWorkspace(HubSurface s) => WorkspaceDescriptor(
      id: 'setup',
      label: s.say('Settings', 'Setup'),
      icon: Icons.settings_outlined,
      selectedIcon: Icons.settings,
      subtitle: s.say('Your business, features and preferences',
          'Configure the system'),
      accentColor: MercantisBrandColors.accentSetup,
      order: 90,
      sections: [
        const WorkspaceSection(label: 'Getting started', items: [
          CustomWorkspaceItem(routeName: 'setup-checklist',
            label: 'Setup checklist', icon: Icons.checklist_outlined,
            description: 'What still needs doing — and whether you can '
                'safely start invoicing'),
          CustomWorkspaceItem(routeName: 'features',
            label: 'Business type & features', icon: Icons.tune_outlined,
            description: 'Turn optional features on or off — nothing is '
                'deleted when hidden'),
          CustomWorkspaceItem(routeName: 'setup-packs',
            label: 'Setup packs', icon: Icons.inventory_2_outlined,
            description: 'Add business shapes: accounts, modules and rules, '
                'safely and recorded'),
        ]),
        const WorkspaceSection(label: 'Preferences', items: [
          CustomWorkspaceItem(routeName: 'settings',
            label: 'Settings', icon: Icons.settings_outlined,
            description: 'Operator, view (Owner / Accountant), appearance '
                'and tools'),
          CustomWorkspaceItem(routeName: 'team',
            label: 'Atlas Team', icon: Icons.cloud_outlined,
            description: 'Connect this device to a Team backend and invite '
                'teammates'),
        ]),
        WorkspaceSection(label: s.say('Your business', 'Organisation'), items: [
          DocTypeWorkspaceItem(docType: 'Company',
            icon: Icons.business_outlined,
            label: s.plainLanguage ? 'Business details' : null),
          const CustomWorkspaceItem(routeName: 'opening-balances',
            label: 'Opening balances',
            icon: Icons.playlist_add_check_outlined,
            description: 'Bring balances over from your previous system'),
          const CustomWorkspaceItem(routeName: 'numbering-series',
            label: 'Document numbering', icon: Icons.tag,
            description: 'Invoice and document number sequences'),
          if (s.accountant) ...const [
            DocTypeWorkspaceItem(docType: 'Fiscal Year',
              icon: Icons.event_outlined),
            DocTypeWorkspaceItem(docType: 'Currency',
              icon: Icons.currency_exchange),
          ],
        ]),
        if (s.accountant || s.has(HubFeature.stock))
          WorkspaceSection(label: 'Catalogue masters', items: [
            const DocTypeWorkspaceItem(docType: 'Price List',
              icon: Icons.price_change_outlined),
            const DocTypeWorkspaceItem(docType: 'UOM',
              icon: Icons.straighten_outlined),
            if (s.accountant)
              const DocTypeWorkspaceItem(docType: 'Brand',
                icon: Icons.sell_outlined),
          ]),
        if (s.accountant)
          const WorkspaceSection(label: 'Segmentation', items: [
            DocTypeWorkspaceItem(docType: 'Customer Group',
              icon: Icons.groups_outlined),
            DocTypeWorkspaceItem(docType: 'Supplier Group',
              icon: Icons.group_work_outlined),
            DocTypeWorkspaceItem(docType: 'Territory',
              icon: Icons.public_outlined),
            DocTypeWorkspaceItem(docType: 'Address',
              icon: Icons.location_on_outlined),
          ]),
        if (s.systemTools) ...const [
          WorkspaceSection(label: 'People', items: [
            DocTypeWorkspaceItem(docType: 'User', icon: Icons.person_outline),
            DocTypeWorkspaceItem(docType: 'Role', icon: Icons.badge_outlined),
          ]),
          WorkspaceSection(label: 'System configuration', items: [
            DocTypeWorkspaceItem(docType: 'DocType',
              icon: Icons.description_outlined),
            DocTypeWorkspaceItem(docType: 'Workflow',
              icon: Icons.account_tree_outlined),
            DocTypeWorkspaceItem(docType: 'Custom Field',
              icon: Icons.tune_outlined),
          ]),
        ],
      ],
    );
