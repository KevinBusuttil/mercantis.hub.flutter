import 'package:flutter/material.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

/// V1 Field Service workspace: the dispatcher's board plus the raw
/// registers behind it. Visible when the Field Service module is enabled
/// (Services and Trade presets turn it on).
const fieldServiceWorkspace = WorkspaceDescriptor(
  id: 'field_service',
  label: 'Field Service',
  shortLabel: 'Jobs',
  icon: Icons.home_repair_service_outlined,
  selectedIcon: Icons.home_repair_service,
  subtitle: 'Requests, jobs and dispatch',
  accentColor: MercantisBrandColors.accentDelivery,
  order: 15,
  sections: [
    WorkspaceSection(label: 'Run the day', items: [
      CustomWorkspaceItem(routeName: 'dispatch',
        label: 'Dispatch board', icon: Icons.space_dashboard_outlined,
        description: 'The request queue, jobs waiting for a slot, and '
            'every technician\'s day'),
      CustomWorkspaceItem(routeName: 'tech-today',
        label: 'My day (technician)', icon: Icons.engineering_outlined,
        description: 'Your jobs today: checklist, parts, hours, sign-off'),
      CustomWorkspaceItem(routeName: 'schedule',
        label: 'Schedule', icon: Icons.calendar_month_outlined,
        description: 'All bookings by resource — day and week boards'),
      CustomWorkspaceItem(routeName: 'field-service-kpis',
        label: 'KPIs', icon: Icons.insights_outlined,
        description: 'Jobs done, revenue per technician, backlog and '
            'contract health'),
    ]),
    WorkspaceSection(label: 'Records', items: [
      CustomWorkspaceItem(routeName: 'equipment',
        label: 'Equipment & history', icon: Icons.directions_car_outlined,
        description: 'The customer\'s cars, boilers and machines — every '
            'visit on record per unit'),
      DocTypeWorkspaceItem(docType: 'Service Request',
        icon: Icons.call_received_outlined),
      DocTypeWorkspaceItem(docType: 'Job', icon: Icons.handyman_outlined),
      DocTypeWorkspaceItem(docType: 'Customer Equipment',
        icon: Icons.directions_car_outlined),
      DocTypeWorkspaceItem(docType: 'Maintenance Contract',
        icon: Icons.event_repeat_outlined),
      DocTypeWorkspaceItem(docType: 'Schedulable Resource',
        icon: Icons.engineering_outlined),
    ]),
  ],
);
