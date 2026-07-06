import 'package:flutter/material.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

/// Projects & time (Phase 6): jobs, tasks, timesheets and project billing —
/// visible for the Services / Mixed presets (or the Settings toggle).
const projectsWorkspace = WorkspaceDescriptor(
  id: 'projects',
  label: 'Projects & Time',
  shortLabel: 'Projects',
  icon: Icons.work_outline,
  selectedIcon: Icons.work,
  subtitle: 'Jobs, hours and billable work',
  accentColor: MercantisBrandColors.accentSales,
  order: 15,
  sections: [
    WorkspaceSection(
      label: 'Work',
      items: [
        DocTypeWorkspaceItem(docType: 'Project', icon: Icons.work_outline),
        DocTypeWorkspaceItem(docType: 'Task', icon: Icons.check_circle_outline),
        DocTypeWorkspaceItem(docType: 'Timesheet', icon: Icons.timer_outlined),
      ],
    ),
    WorkspaceSection(
      label: 'Billing',
      description: 'Unbilled time and expenses become draft invoices from '
          'the Bill project action on a Project',
      items: [
        DocTypeWorkspaceItem(
          docType: 'Expense',
          icon: Icons.local_cafe_outlined,
          label: 'Billable expenses',
          listFilter: {'billable': 1},
        ),
      ],
    ),
  ],
  quickActions: [
    QuickAction(id: 'proj_new_project', label: 'New Project',
      icon: Icons.create_new_folder_outlined, docType: 'Project'),
    QuickAction(id: 'proj_new_timesheet', label: 'Log time',
      icon: Icons.timer_outlined, docType: 'Timesheet'),
  ],
);
