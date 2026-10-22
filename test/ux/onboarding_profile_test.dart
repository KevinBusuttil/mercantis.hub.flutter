import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_hub_app/screens/onboarding_screen.dart';
import 'package:mercantis_hub_app/settings/hub_settings.dart';

import '../support/hub_app_harness.dart';

/// First run: the business type shapes the phone bar, and the suggested
/// extras are opt-in rather than switched on behind the user's back.
void main() {
  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: hubTestOverrides(const HubSettings()),
      child: const MaterialApp(home: OnboardingScreen()),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('Services previews its phone bar and offers extras off',
      (tester) async {
    await pump(tester);
    expect(find.text('On your phone: Today · Customers · Invoices · Money · More'),
        findsOneWidget);
    final chips = tester.widgetList<FilterChip>(find.byType(FilterChip));
    expect(chips, isNotEmpty);
    expect(chips.where((c) => c.selected), isEmpty);
    expect(find.text('Projects & time'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('choosing Retail previews the till', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Retail / Shop'));
    await tester.pumpAndSettle();
    expect(find.text('On your phone: Today · Till · Stock · Money · More'),
        findsOneWidget);
  });

  testWidgets('choosing Trade previews stock', (tester) async {
    await pump(tester);
    await tester.tap(find.textContaining('Trade').first);
    await tester.pumpAndSettle();
    expect(find.text('On your phone: Today · Sales · Stock · Money · More'),
        findsOneWidget);
  });
}
