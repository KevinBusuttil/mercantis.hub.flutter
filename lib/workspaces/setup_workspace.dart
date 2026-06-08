import 'package:flutter/material.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

const setupWorkspace = WorkspaceDescriptor(
  id: 'setup',
  label: 'Setup',
  icon: Icons.settings_outlined,
  selectedIcon: Icons.settings,
  subtitle: 'Configure the system',
  accentColor: MercantisBrandColors.accentSetup,
  order: 90,
  sections: [
    WorkspaceSection(label: 'Preferences', items: [
      CustomWorkspaceItem(routeName: 'settings',
        label: 'Settings', icon: Icons.tune_outlined,
        description: 'Operator, modules and advanced mode'),
    ]),
    WorkspaceSection(label: 'Organisation', items: [
      DocTypeWorkspaceItem(docType: 'Company', icon: Icons.business_outlined),
      DocTypeWorkspaceItem(docType: 'Fiscal Year', icon: Icons.event_outlined),
      DocTypeWorkspaceItem(docType: 'Currency',
        icon: Icons.currency_exchange),
    ]),
    WorkspaceSection(label: 'Catalogue masters', items: [
      DocTypeWorkspaceItem(docType: 'UOM', icon: Icons.straighten_outlined),
      DocTypeWorkspaceItem(docType: 'Brand', icon: Icons.sell_outlined),
      DocTypeWorkspaceItem(docType: 'Price List', icon: Icons.price_change_outlined),
    ]),
    WorkspaceSection(label: 'Segmentation', items: [
      DocTypeWorkspaceItem(docType: 'Customer Group', icon: Icons.groups_outlined),
      DocTypeWorkspaceItem(docType: 'Supplier Group', icon: Icons.group_work_outlined),
      DocTypeWorkspaceItem(docType: 'Territory', icon: Icons.public_outlined),
      DocTypeWorkspaceItem(docType: 'Address', icon: Icons.location_on_outlined),
    ]),
    WorkspaceSection(label: 'People', items: [
      DocTypeWorkspaceItem(docType: 'User', icon: Icons.person_outline),
      DocTypeWorkspaceItem(docType: 'Role', icon: Icons.badge_outlined),
    ]),
    WorkspaceSection(label: 'Customisation', items: [
      DocTypeWorkspaceItem(docType: 'DocType',
        icon: Icons.description_outlined),
      DocTypeWorkspaceItem(docType: 'Workflow',
        icon: Icons.account_tree_outlined),
      DocTypeWorkspaceItem(docType: 'Custom Field',
        icon: Icons.tune_outlined),
    ]),
  ],
);
