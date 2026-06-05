import 'package:flutter/material.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

class ApprovalsInboxScreen extends StatelessWidget {
  const ApprovalsInboxScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ResponsiveScaffold(
      title: 'Approvals',
      subtitle: 'Documents waiting for your decision',
      body: ApprovalInboxList(),
      padBody: false,
    );
  }
}
