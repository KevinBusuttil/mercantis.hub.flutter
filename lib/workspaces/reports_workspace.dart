import 'package:flutter/material.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

import '../navigation/hub_surface.dart';

/// Reports: the financial reports (summary first on phones, full tables on
/// demand) and the dashboards; the ad-hoc report builder is an Accountant
/// tool. (Replaces three "coming soon" entries whose routes never existed.)
WorkspaceDescriptor reportsWorkspace(HubSurface s) => WorkspaceDescriptor(
      id: 'reports',
      label: s.say('Reports', 'Reports & Insights'),
      shortLabel: 'Reports',
      icon: Icons.insights_outlined,
      selectedIcon: Icons.insights,
      subtitle: s.say('How the business is doing',
          'Statements, dashboards and analysis'),
      accentColor: MercantisBrandColors.accentReports,
      order: 70,
      sections: [
        const WorkspaceSection(label: 'Reports', items: [
          CustomWorkspaceItem(routeName: 'reports',
            label: 'Financial reports', icon: Icons.insights_outlined,
            description: 'Profit & loss, balance sheet, cash, who owes '
                'what, stock and margins'),
          CustomWorkspaceItem(routeName: 'dashboards',
            label: 'Dashboards', icon: Icons.dashboard_outlined,
            description: 'Live tiles over your books'),
        ]),
        if (s.accountant)
          const WorkspaceSection(label: 'Build', items: [
            CustomWorkspaceItem(routeName: 'report-builder',
              label: 'Report builder', icon: Icons.tune,
              description: 'Ad-hoc lists over any record type'),
          ]),
      ],
    );
