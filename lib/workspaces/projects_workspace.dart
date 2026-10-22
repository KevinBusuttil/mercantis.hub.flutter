import 'package:flutter/material.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

import '../features/hub_feature.dart';
import '../navigation/hub_surface.dart';

/// Projects & time (Phase 6): jobs, tasks, timesheets and project billing —
/// shown when Projects is on. Construction contracts are their own optional
/// feature and appear here only when switched on.
WorkspaceDescriptor projectsWorkspace(HubSurface s) => WorkspaceDescriptor(
      id: 'projects',
      label: 'Projects & Time',
      shortLabel: 'Projects',
      icon: Icons.work_outline,
      selectedIcon: Icons.work,
      subtitle: 'Jobs, hours and billable work',
      accentColor: MercantisBrandColors.accentSales,
      order: 15,
      sections: [
        if (s.has(HubFeature.projects)) ...[
          const WorkspaceSection(
            label: 'Work',
            items: [
              DocTypeWorkspaceItem(docType: 'Project',
                icon: Icons.work_outline),
              DocTypeWorkspaceItem(docType: 'Task',
                icon: Icons.check_circle_outline),
              DocTypeWorkspaceItem(docType: 'Timesheet',
                icon: Icons.timer_outlined),
            ],
          ),
          const WorkspaceSection(
            label: 'Billing',
            description: 'Unbilled time and expenses become draft invoices '
                'from the Bill project action on a Project',
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
        if (s.has(HubFeature.construction))
          const WorkspaceSection(
            label: 'Construction',
            description: 'Interim valuations billed less retention; the held '
                'retention releases at practical completion',
            items: [
              CustomWorkspaceItem(routeName: 'contracts',
                label: 'Contracts board', icon: Icons.engineering_outlined,
                description: 'Certified position, billed to date and '
                    'retention held per contract'),
              DocTypeWorkspaceItem(docType: 'Construction Contract',
                icon: Icons.engineering_outlined),
            ],
          ),
      ],
      quickActions: [
        if (s.has(HubFeature.projects)) ...const [
          QuickAction(id: 'proj_new_project', label: 'New project',
            icon: Icons.create_new_folder_outlined, docType: 'Project'),
          QuickAction(id: 'proj_new_timesheet', label: 'Log time',
            icon: Icons.timer_outlined, docType: 'Timesheet'),
        ],
      ],
    );
