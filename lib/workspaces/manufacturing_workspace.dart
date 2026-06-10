import 'package:flutter/material.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

const manufacturingWorkspace = WorkspaceDescriptor(
  id: 'manufacturing',
  label: 'Manufacturing',
  shortLabel: 'Mfg',
  icon: Icons.precision_manufacturing_outlined,
  selectedIcon: Icons.precision_manufacturing,
  subtitle: 'BOMs, work orders and production',
  accentColor: MercantisBrandColors.accentManufacturing,
  order: 35,
  sections: [
    WorkspaceSection(
      label: 'Production',
      description: 'Plan and run production',
      items: [
        DocTypeWorkspaceItem(docType: 'Production Plan', icon: Icons.event_note_outlined),
        DocTypeWorkspaceItem(docType: 'Work Order', icon: Icons.build_circle_outlined),
        CustomWorkspaceItem(routeName: 'work-order-complete',
          label: 'Complete Work Order', icon: Icons.task_alt_outlined,
          description: 'Post production: consume materials, produce goods'),
        DocTypeWorkspaceItem(docType: 'Job Card', icon: Icons.assignment_turned_in_outlined),
      ],
    ),
    WorkspaceSection(
      label: 'Engineering',
      description: 'Bills of materials and routings',
      items: [
        DocTypeWorkspaceItem(docType: 'BOM', icon: Icons.account_tree_outlined),
        DocTypeWorkspaceItem(docType: 'Operation', icon: Icons.handyman_outlined),
        DocTypeWorkspaceItem(docType: 'Workstation', icon: Icons.factory_outlined),
      ],
    ),
  ],
  quickActions: [
    QuickAction(id: 'mf_new_bom', label: 'New BOM',
      icon: Icons.account_tree_outlined, docType: 'BOM'),
    QuickAction(id: 'mf_new_wo', label: 'New Work Order',
      icon: Icons.build_circle_outlined, docType: 'Work Order'),
    QuickAction(id: 'mf_new_pp', label: 'New Production Plan',
      icon: Icons.event_note_outlined, docType: 'Production Plan'),
    QuickAction(id: 'mf_complete_wo', label: 'Complete Work Order',
      icon: Icons.task_alt_outlined, routeName: '/w/manufacturing/work-order-complete'),
  ],
);
