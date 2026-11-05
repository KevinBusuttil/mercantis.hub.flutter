import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';
import 'package:mercantis_hub_app/screens/team_recovery_screen.dart';
import 'package:mercantis_hub_app/team/team_history.dart';
import 'package:mercantis_hub_app/team/team_history_recovery.dart';
import 'package:mercantis_hub_app/team/team_session.dart';

/// C4: what the user sees when the Team server was restored. The recovery
/// itself runs against a real backend in
/// test/team_e2e/team_restore_e2e_test.dart.
void main() {
  const session = TeamSession(
    baseUrl: 'https://team.example',
    companyId: 'co-1',
    companyName: 'Harbour Lane',
    userId: 'u',
    userToken: 't',
    deviceId: 'd',
    deviceToken: 'dt',
    deviceName: 'Office',
  );
  const divergence = TeamHistoryDiverged(
      checkpoint: TeamHistoryCheckpoint(120, 'abc'), serverHead: 125);

  Future<void> pump(WidgetTester tester, Widget home,
      {TeamHistoryDiverged? diverged}) async {
    tester.view.physicalSize = const Size(400, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        teamSessionProvider.overrideWith((ref) => _Fixed(session)),
        teamHistoryDivergedProvider.overrideWith((ref) async => diverged),
      ],
      child: MaterialApp(theme: MercantisTheme.light(), home: home),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('explains the restore and the RPO; needs a passphrase first',
      (tester) async {
    await pump(tester, const TeamRecoveryScreen(), diverged: divergence);
    expect(find.textContaining('restored from a backup'), findsWidgets);
    expect(find.textContaining('up to a day of work'), findsOneWidget);
    FilledButton start() => tester.widget<FilledButton>(find.ancestor(
        of: find.text('Copy, then compare with the server'),
        matching: find.byWidgetPredicate((w) => w is FilledButton)));
    expect(start().onPressed, isNull);
    await tester.enterText(find.byType(TextField).at(0), 'long enough pass');
    await tester.enterText(find.byType(TextField).at(1), 'long enough pass');
    await tester.pump();
    expect(start().onPressed, isNotNull);
    expect(find.text('Switch to the server’s books'), findsNothing,
        reason: 'no switch before the comparison');
  });

  testWidgets('a device that is in step is told so', (tester) async {
    await pump(tester, const TeamRecoveryScreen());
    expect(find.text('This device does not need recovering.'), findsOneWidget);
  });

  testWidgets('the report lists losses, reused numbers and kept work',
      (tester) async {
    final report = TeamRecoveryReport(
        recoveryId: 'rec-1', divergence: divergence, serverHead: 125)
      ..lost.add(const LostOfficialRecord(
          docType: 'Sales Invoice',
          documentId: 'SINV-D1-0007',
          kind: 'posted',
          number: 'SINV-00042',
          postingDate: '2026-11-04',
          total: 118,
          party: 'C-1'))
      ..numberReused.add({
        'doctype': 'Sales Invoice',
        'number': 'SINV-00042',
        'lost_document_id': 'SINV-D1-0007',
        'server_document_id': 'SINV-D2-0003',
      })
      ..lostReported = true
      ..carried.add('Customer C-NEW')
      ..pendingTillSales.add('POS Invoice TILL1-0009')
      ..notCarried.add('Sales Invoice X: it is now an official document');
    await pump(
        tester,
        Scaffold(
            body:
                ListView(children: [TeamRecoveryReportCard(report: report)])));
    expect(find.textContaining('SINV-00042 · 2026-11-04 · C-1 · 118.00'),
        findsOneWidget);
    expect(find.textContaining('now SINV-D2-0003'), findsOneWidget);
    expect(find.textContaining('will not issue the lost numbers again'),
        findsOneWidget);
    expect(find.textContaining('C-NEW'), findsOneWidget);
    expect(find.textContaining('TILL1-0009'), findsOneWidget);
    expect(find.textContaining('Edits not kept'), findsOneWidget);
    expect(report.canSwitch, isTrue);
    report.integrityProblems.add('The trial balance is out by 1.00');
    expect(report.canSwitch, isFalse,
        reason: 'a failed check blocks the switch');
  });
}

class _Fixed extends TeamSessionNotifier {
  _Fixed(TeamSession s) : super(TeamSessionStore()) {
    state = s;
  }
}
