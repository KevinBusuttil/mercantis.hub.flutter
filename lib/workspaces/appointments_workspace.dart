import 'package:flutter/material.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

/// Phase 4 Appointments workspace: the front desk. Book (slot + deposit
/// in one move), run the day, complete to invoice, count commissions.
/// Visible when the Appointments module is enabled (Services preset, the
/// Appointments Setup Pack, or the Settings toggle).
const appointmentsWorkspace = WorkspaceDescriptor(
  id: 'appointments',
  label: 'Appointments',
  shortLabel: 'Bookings',
  icon: Icons.event_available_outlined,
  selectedIcon: Icons.event_available,
  subtitle: 'Front desk: book, complete, commission',
  accentColor: MercantisBrandColors.accentSales,
  order: 16,
  sections: [
    WorkspaceSection(label: 'Front desk', items: [
      CustomWorkspaceItem(routeName: 'booking',
        label: 'Book an appointment', icon: Icons.event_outlined,
        description: 'Service, staff, slot and deposit in one flow — '
            'today\'s list completes straight to invoice'),
      CustomWorkspaceItem(routeName: 'schedule',
        label: 'Schedule', icon: Icons.calendar_month_outlined,
        description: 'All bookings by resource — day and week boards'),
      CustomWorkspaceItem(routeName: 'commissions',
        label: 'Commissions', icon: Icons.percent_outlined,
        description: 'What each staff member earned on invoiced work'),
    ]),
    WorkspaceSection(label: 'Records', items: [
      DocTypeWorkspaceItem(docType: 'Appointment',
        icon: Icons.event_note_outlined),
      DocTypeWorkspaceItem(docType: 'Schedulable Resource',
        icon: Icons.badge_outlined, label: 'Staff & resources'),
      DocTypeWorkspaceItem(docType: 'Commission Rule',
        icon: Icons.percent_outlined),
      DocTypeWorkspaceItem(docType: 'Customer Deposit',
        icon: Icons.savings_outlined),
    ]),
  ],
);
