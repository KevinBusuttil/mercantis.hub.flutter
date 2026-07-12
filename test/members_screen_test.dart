import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_hub_app/membership/membership_service.dart';
import 'package:mercantis_hub_app/screens/members_screen.dart';

/// V7: the members list renders billing state per member and the right
/// action per status.
void main() {
  MembersData data() => MembersData(
        lines: [
          MemberRollLine(
            membership: Document(id: 'MEM-2026-0001',
                docType: 'Membership', payload: {'status': 'Active'}),
            member: 'MBR-1',
            planName: 'Gold',
            fee: 50,
            frequency: 'Monthly',
            nextInvoiceDate: '2026-08-10',
            arrears: 100,
          ),
          MemberRollLine(
            membership: Document(id: 'MEM-2026-0002',
                docType: 'Membership', payload: {'status': 'Paused'}),
            member: 'MBR-2',
            planName: 'Silver',
            fee: 30,
            frequency: 'Monthly',
            arrears: 0,
          ),
        ],
        drafts: [
          Document(id: 'MEM-2026-0003', docType: 'Membership', payload: {
            'status': 'Draft', 'member': 'MBR-3', 'plan': 'GOLD',
          }),
        ],
      );

  testWidgets('rows show plan, billing, arrears and per-status actions',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        membersProvider.overrideWith((ref) async => data()),
      ],
      child: const MaterialApp(home: MembersScreen()),
    ));
    await tester.pumpAndSettle();

    // Draft waits with Activate.
    expect(find.text('MEM-2026-0003 · MBR-3 · GOLD'), findsOneWidget);
    expect(find.text('Activate'), findsOneWidget);

    // Active member: billing line, arrears, Pause.
    expect(find.text('MBR-1 · Gold'), findsOneWidget);
    expect(find.text('50.00 monthly · next 2026-08-10'), findsOneWidget);
    expect(find.text('100.00'), findsOneWidget);
    expect(find.text('Pause'), findsOneWidget);

    // Paused member: no billing, Resume.
    expect(find.text('MBR-2 · Silver'), findsOneWidget);
    expect(find.text('Paused — no billing'), findsOneWidget);
    expect(find.text('Resume'), findsOneWidget);

    // Cancel offered on both.
    expect(find.text('Cancel'), findsNWidgets(2));
  });
}
