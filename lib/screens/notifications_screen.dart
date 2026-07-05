import 'package:flutter/material.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

/// Hosts the shared [NotificationInboxView] (ADR-048) as a hub route. The inbox
/// carries its own header + "Mark all read" action, so this just gives it a
/// screen surface within the shell.
class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: SafeArea(child: NotificationInboxView()));
}
