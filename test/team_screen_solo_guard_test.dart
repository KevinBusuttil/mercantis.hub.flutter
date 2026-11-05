import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';
import 'package:mercantis_hub_app/screens/solo_to_team_screen.dart';
import 'package:mercantis_hub_app/screens/team_screen.dart';

/// C3: a device whose books already hold issued documents is never offered
/// the direct "create" or "join" connection (that splits the books, see
/// test/team_e2e/solo_to_team_e2e_test.dart); it is offered the conversion.
void main() {
  Future<void> pump(WidgetTester tester, int history) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [soloHistoryProvider.overrideWith((ref) async => history)],
      child: MaterialApp(
        theme: MercantisTheme.light(),
        home: const TeamScreen(),
      ),
    ));
    await tester.pumpAndSettle();
  }

  FilledButton button(WidgetTester tester, String label) =>
      tester.widget<FilledButton>(find.ancestor(
          of: find.text(label),
          matching: find.byWidgetPredicate((w) => w is FilledButton)));

  testWidgets('books with history: direct connect is off, the move is offered',
      (tester) async {
    await pump(tester, 12);
    expect(
        find.byWidgetPredicate((w) =>
            w is AtlasSectionCard &&
            w.name == 'These books already hold 12 issued documents'),
        findsOneWidget);
    expect(button(tester, 'Create company & connect').onPressed, isNull);
    expect(button(tester, 'Join & connect').onPressed, isNull);
    final move = find.text('Move these books to Atlas Team…');
    await tester.ensureVisible(move);
    await tester.tap(move);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(SoloToTeamScreen), findsOneWidget);
  });

  testWidgets('a fresh book connects directly as before', (tester) async {
    await pump(tester, 0);
    expect(find.text('Move these books to Atlas Team…'), findsNothing);
    expect(button(tester, 'Create company & connect').onPressed, isNotNull);
    expect(button(tester, 'Join & connect').onPressed, isNotNull);
  });
}
