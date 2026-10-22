import 'package:flutter/material.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

/// Team-only: approvals route decisions between people, so the workspace is
/// shown when this device is connected to Atlas Team (see hub_workspaces).
const approvalsWorkspace = WorkspaceDescriptor(
  id: 'approvals',
  label: 'Approvals',
  icon: Icons.fact_check_outlined,
  selectedIcon: Icons.fact_check,
  subtitle: 'Decisions waiting for you',
  accentColor: MercantisBrandColors.accentApprovals,
  order: 60,
  sections: [
    WorkspaceSection(
      label: 'Inbox',
      items: [
        CustomWorkspaceItem(
          routeName: 'inbox',
          label: 'All pending',
          icon: Icons.inbox_outlined,
        ),
      ],
    ),
  ],
);
