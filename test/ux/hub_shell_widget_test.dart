import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_hub_app/features/hub_feature.dart';
import 'package:mercantis_hub_app/navigation/hub_shell.dart';
import 'package:mercantis_hub_app/onboarding/business_preset.dart';
import 'package:mercantis_hub_app/settings/hub_settings.dart';

import '../support/hub_app_harness.dart';

/// The real Hub router and adaptive shell over synthetic data: the phone bar
/// per profile, the More sheet, deep links into hidden features, live feature
/// switching, widths from a small phone to desktop and large text.
void main() {
  final services = presetSettings(BusinessPreset.services);
  final trade = presetSettings(BusinessPreset.trade);
  final retail = presetSettings(BusinessPreset.retail);

  Finder inBar(String label) => find.descendant(
      of: find.byType(NavigationBar), matching: find.text(label));

  group('phone bar', () {
    for (final (name, s, labels) in [
      ('Services', services, ['Today', 'Customers', 'Invoices', 'Money', 'More']),
      ('Trade', trade, ['Today', 'Sales', 'Stock', 'Money', 'More']),
      ('Retail', retail, ['Today', 'Till', 'Stock', 'Money', 'More']),
    ]) {
      testWidgets('$name shows ${labels.join(' · ')}', (tester) async {
        await pumpHub(tester, settings: s);
        expect(find.byType(NavigationBar), findsOneWidget);
        for (final l in labels) {
          expect(inBar(l), findsOneWidget, reason: l);
        }
        final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
        expect(bar.destinations.length, labels.length);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('More lists the other areas and no hidden vertical',
        (tester) async {
      await pumpHub(tester, settings: services);
      await tester.tap(inBar('More'));
      await tester.pumpAndSettle();
      final sheet = find.byType(BottomSheet);
      Finder inSheet(String text) =>
          find.descendant(of: sheet, matching: find.textContaining(text));
      for (final shown in ['Sales', 'Buying', 'Reports', 'Settings']) {
        expect(inSheet(shown), findsWidgets, reason: shown);
      }
      for (final hidden in [
        'Stock', 'Manufacturing', 'Deliver', 'Field', 'Appointments',
        'Projects', 'Approvals', 'Rental', 'Property', 'Construction',
      ]) {
        expect(inSheet(hidden), findsNothing, reason: hidden);
      }
      // Money is on the bar, so it is not repeated in More.
      expect(find.text('Money'), findsOneWidget);
    });

    testWidgets('Money opens the finance workspace in business words',
        (tester) async {
      await pumpHub(tester, settings: services);
      await tester.tap(inBar('Money'));
      await tester.pumpAndSettle();
      expect(find.text('Get paid'), findsWidgets);
      expect(find.text('Receive payment'), findsWidgets);
      expect(find.text('Journal Entry'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('deep links', () {
    testWidgets('into a hidden feature explain it and offer the switch',
        (tester) async {
      final c = await pumpHub(tester,
          settings: services, location: '/w/sales_fulfilment/rentals');
      expect(find.text('Rentals / hire is turned off'), findsWidgets);
      expect(find.text('Turn on Rentals / hire'), findsOneWidget);
      expect(find.text('Back to Today'), findsOneWidget);
      await tester.tap(find.text('Turn on Rentals / hire'));
      await tester.pump();
      expect(c.read(hubSettingsProvider).has(HubFeature.rentals), isTrue);
    });

    testWidgets('to a hidden workspace land on the explanation',
        (tester) async {
      await pumpHub(tester, settings: services, location: '/w/inventory');
      expect(find.text('Stock & warehouses is turned off'), findsWidgets);
    });

    testWidgets('to an accountant tool offer the Accountant view',
        (tester) async {
      final c = await pumpHub(tester,
          settings: services, location: '/w/reports/report-builder');
      expect(find.text('Switch to Accountant view'), findsOneWidget);
      await tester.tap(find.text('Switch to Accountant view'));
      await tester.pump();
      expect(c.read(hubSettingsProvider).userMode, HubUserMode.accountant);
    });

    testWidgets('to approvals without Team point at Atlas Team',
        (tester) async {
      await pumpHub(tester, settings: services, location: '/w/approvals/inbox');
      expect(find.text('Part of Atlas Team'), findsWidgets);
    });

    testWidgets('that are allowed render the real screen', (tester) async {
      await pumpHub(tester, settings: services, location: '/w/finance');
      expect(find.byType(HiddenFeatureView), findsNothing);
      expect(find.text('Get paid'), findsWidgets);
    });
  });

  testWidgets('switching a feature on applies without a restart',
      (tester) async {
    final c = await pumpHub(tester, settings: services);
    Finder inSheet(String text) => find.descendant(
        of: find.byType(BottomSheet), matching: find.textContaining(text));
    await tester.tap(inBar('More'));
    await tester.pumpAndSettle();
    expect(inSheet('Projects'), findsNothing);
    Navigator.of(tester.element(find.byType(BottomSheet).first)).pop();
    await tester.pumpAndSettle();

    await c
        .read(hubSettingsProvider.notifier)
        .apply(services.withFeature(HubFeature.projects, true));
    await tester.pumpAndSettle();
    await tester.tap(inBar('More'));
    await tester.pumpAndSettle();
    expect(inSheet('Projects'), findsWidgets);
  });

  group('layouts', () {
    const sizes = {
      'small phone 360': Size(360, 740),
      'phone 390': Size(390, 844),
      'large phone 430': Size(430, 932),
      'tablet': Size(1024, 768),
      'desktop': Size(1440, 900),
    };
    for (final (name, s) in [
      ('Services', services),
      ('Trade', trade),
      ('Retail', retail),
    ]) {
      for (final MapEntry(key: label, value: size) in sizes.entries) {
        for (final location in ['/w/home', '/w/finance', '/w/sales_fulfilment']) {
          testWidgets('$name $label $location renders without overflow',
              (tester) async {
            await pumpHub(tester, settings: s, size: size, location: location);
            expect(tester.takeException(), isNull);
          });
        }
      }
    }

    testWidgets('small phone at 200% text keeps the bar and actions usable',
        (tester) async {
      await pumpHub(tester,
          settings: services, size: const Size(360, 740), textScale: 2);
      expect(tester.takeException(), isNull);
      expect(find.byType(NavigationBar), findsOneWidget);
      // Bar labels scale only a little, as platform tab bars do, so five
      // fit a small phone; the rest of the screen follows the full 200%.
      final barScale = MediaQuery.textScalerOf(tester.element(inBar('Customers')));
      expect(barScale.scale(10), lessThanOrEqualTo(11));
      final pageScale = MediaQuery.textScalerOf(tester.element(find.text('Today').first));
      expect(pageScale.scale(10), 20);
      await tester.tap(find.text('Action'));
      await tester.pumpAndSettle();
      expect(find.text('New invoice'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });

  group('accessibility', () {
    testWidgets('bar and More meet tap-target and labelling guidelines',
        (tester) async {
      final handle = tester.ensureSemantics();
      await pumpHub(tester, settings: services);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      expect(find.bySemanticsLabel(RegExp('Customers')), findsWidgets);
      handle.dispose();
    });

    testWidgets('hidden-feature page meets tap-target guidelines',
        (tester) async {
      final handle = tester.ensureSemantics();
      await pumpHub(tester,
          settings: services, location: '/w/sales_fulfilment/rentals');
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      handle.dispose();
    });
  });
}
