import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';
import 'package:mercantis_hub_app/features/hub_feature.dart';
import 'package:mercantis_hub_app/onboarding/business_preset.dart';
import 'package:mercantis_hub_app/settings/hub_settings.dart';

import '../support/hub_app_harness.dart';

void main() {
  final services = presetSettings(BusinessPreset.services);

  group('feature catalogue screen', () {
    testWidgets('lists every optional feature, off for a new Services business',
        (tester) async {
      await pumpHub(tester,
          settings: services,
          location: '/w/setup/features',
          size: const Size(390, 3000));
      for (final f in HubFeature.values) {
        expect(find.text(f.label), findsOneWidget, reason: f.label);
      }
      final switches = tester.widgetList<SwitchListTile>(
          find.byType(SwitchListTile));
      expect(switches.where((s) => s.value), isEmpty);
      // Fiscal compliance is not implied by the till.
      expect(find.textContaining('not implied'), findsOneWidget);
    });

    testWidgets('a switch saves at once and says records are kept',
        (tester) async {
      final c = await pumpHub(tester,
          settings: services.withFeature(HubFeature.rentals, true),
          location: '/w/setup/features',
          size: const Size(390, 3000));
      await tester.ensureVisible(find.text('Rentals / hire'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rentals / hire'));
      await tester.pumpAndSettle();
      expect(c.read(hubSettingsProvider).has(HubFeature.rentals), isFalse);
      expect(find.text('Rentals / hire hidden — records kept'), findsOneWidget);
    });

    testWidgets('tables & kitchen cannot be switched on without the till',
        (tester) async {
      await pumpHub(tester,
          settings: services,
          location: '/w/setup/features',
          size: const Size(390, 3000));
      final tile = tester.widget<SwitchListTile>(find.ancestor(
          of: find.text('Tables & kitchen'),
          matching: find.byType(SwitchListTile)));
      expect(tile.onChanged, isNull);
      expect(find.textContaining('Needs Point of sale'), findsOneWidget);
    });

    testWidgets('changing business type explains what turns on and is hidden',
        (tester) async {
      final c = await pumpHub(tester,
          settings: services,
          location: '/w/setup/features',
          size: const Size(390, 3000));
      await tester.tap(find.text('Change business type'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Retail / Shop').last);
      await tester.pumpAndSettle();
      expect(find.textContaining('Turns on: Stock & warehouses'), findsOneWidget);
      await tester.tap(find.text('Switch'));
      await tester.pumpAndSettle();
      expect(c.read(hubSettingsProvider).businessPresetId, 'retail');
      expect(c.read(hubSettingsProvider).posEnabled, isTrue);
    });

    testWidgets('a legacy installation is offered the simplified navigation',
        (tester) async {
      final c = await pumpHub(tester,
          settings: HubSettings.legacy(),
          location: '/w/setup/features',
          size: const Size(390, 3000));
      expect(find.text('You are on the classic full navigation'), findsOneWidget);
      await tester.tap(find.text('Use simplified navigation'));
      await tester.pumpAndSettle();
      final s = c.read(hubSettingsProvider);
      expect(s.classicNavigation, isFalse);
      expect(s.features, HubFeature.values.toSet()); // nothing switched off
    });
  });

  group('Owner and Accountant words', () {
    Future<DocTypePresentation> presentationFor(
        WidgetTester tester, HubSettings s, String docType) async {
      final c = await pumpHub(tester, settings: s);
      return c.read(docTypePresentationProvider)(docType);
    }

    testWidgets('Owner view uses business words for the lifecycle',
        (tester) async {
      final p = await presentationFor(tester, services, 'Sales Invoice');
      expect(p.label, 'Invoices');
      expect(p.lifecycle.submit, 'Post invoice');
      expect(p.lifecycle.cancel, 'Reverse');
      expect(p.emptyTitle, 'No invoices yet');
    });

    testWidgets('Accountant view keeps the engine terms', (tester) async {
      final p = await presentationFor(tester,
          services.withUserMode(HubUserMode.accountant), 'Sales Invoice');
      expect(p.lifecycle.submit, LifecycleLabels.engine.submit);
      expect(p.label, isNull);
    });

    testWidgets('a classic installation keeps the terms it had',
        (tester) async {
      final p =
          await presentationFor(tester, HubSettings.legacy(), 'Purchase Invoice');
      expect(p.lifecycle.submit, LifecycleLabels.engine.submit);
    });

    testWidgets('journals keep accounting language in the Owner view',
        (tester) async {
      final p = await presentationFor(tester, services, 'Journal Entry');
      expect(p.lifecycle.submit, LifecycleLabels.engine.submit);
    });
  });

  testWidgets('settings screen links to the feature catalogue', (tester) async {
    await pumpHub(tester, settings: services, location: '/w/setup/settings');
    expect(find.textContaining('Business type'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
