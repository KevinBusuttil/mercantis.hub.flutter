import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_hub_app/migration/take_on_templates.dart';
import 'package:mercantis_hub_app/screens/opening_data_screen.dart';
import 'package:mercantis_hub_app/team/team_session.dart';

/// The opening-data wizard renders every take-on section with its template
/// action, on a phone and on a desktop, before any file is chosen.
void main() {
  for (final size in const [Size(390, 844), Size(1280, 900)]) {
    testWidgets('lists every section at ${size.width.toInt()} px wide',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const ProviderScope(
          child: MaterialApp(home: OpeningDataScreen())));
      await tester.pumpAndSettle();

      expect(find.text('Move from another system'), findsWidgets);
      for (final t in TakeOnTemplate.all) {
        await tester.scrollUntilVisible(find.text(t.title), 200,
            scrollable: find.byType(Scrollable).first);
        expect(find.text(t.title), findsOneWidget);
      }
      expect(find.text('Template'), findsWidgets);
      // Nothing to check until a file is chosen.
      await tester.scrollUntilVisible(find.text('Check'), 200,
          scrollable: find.byType(Scrollable).first);
      final check = tester.widget<OutlinedButton>(find.ancestor(
          of: find.text('Check'), 
          matching: find.byWidgetPredicate((w) => w is OutlinedButton)));
      expect(check.onPressed, isNull);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a Team-connected device cannot import opening data',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
        overrides: [teamSessionProvider.overrideWith((_) => _Connected())],
        child: const MaterialApp(home: OpeningDataScreen())));
    await tester.pumpAndSettle();
    expect(find.textContaining('connected to Atlas Team'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Import'), 200,
        scrollable: find.byType(Scrollable).first);
    final import = tester.widget<FilledButton>(find.ancestor(
        of: find.text('Import'),
        matching: find.byWidgetPredicate((w) => w is FilledButton)));
    expect(import.onPressed, isNull);
  });
}

class _Connected extends TeamSessionNotifier {
  _Connected() : super(TeamSessionStore()) {
    state = const TeamSession(
      baseUrl: 'https://team.example',
      companyId: 'C',
      companyName: 'Company',
      userId: 'U',
      userToken: 'u',
      deviceId: 'D',
      deviceToken: 'd',
      deviceName: 'Phone',
    );
  }
}
