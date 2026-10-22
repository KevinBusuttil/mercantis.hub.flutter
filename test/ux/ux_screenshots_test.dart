import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_hub_app/reports/report_providers.dart';
import 'package:mercantis_hub_app/screens/onboarding_screen.dart';
import 'package:mercantis_hub_app/screens/reports_screen.dart';
import 'package:mercantis_hub_app/onboarding/business_preset.dart';
import 'package:mercantis_hub_app/settings/hub_settings.dart';

import '../support/hub_app_harness.dart';
import '../support/screenshot_fonts.dart';

/// Renders the "after" screenshots in docs/ux/screenshots/after from the real
/// Hub router, shell and screens over the synthetic business fixture. They
/// are a record for review, not a pixel test: regenerate with
///
///   flutter test test/ux/ux_screenshots_test.dart --update-goldens
///
/// and the plain `flutter test` run skips them (font rasterisation differs
/// between machines). Widget tests are not usability testing.
void main() {
  const phone = Size(390, 844);
  const small = Size(360, 740);
  const tablet = Size(1024, 768);
  const desktop = Size(1440, 900);
  const key = Key('ux-capture');
  final skip = !autoUpdateGoldenFiles;

  final services = presetSettings(BusinessPreset.services);
  final trade = presetSettings(BusinessPreset.trade);
  final retail = presetSettings(BusinessPreset.retail);

  void shot(
    String name,
    HubSettings settings, {
    String location = '/w/home',
    Size size = phone,
    double textScale = 1,
    Future<void> Function(WidgetTester t)? then,
  }) {
    testWidgets(name, skip: skip, (tester) async {
      await tester.runAsync(loadScreenshotFonts);
      await pumpHub(tester,
          settings: settings,
          location: location,
          size: size,
          textScale: textScale,
          theme: screenshotTheme(),
          boundaryKey: key);
      if (then != null) {
        await then(tester);
        await tester.pumpAndSettle();
      }
      await expectLater(find.byKey(key),
          matchesGoldenFile('../../docs/ux/screenshots/after/$name.png'));
    });
  }

  void screenShot(String name, HubSettings settings, Widget screen,
      {Size size = phone}) {
    testWidgets(name, skip: skip, (tester) async {
      await tester.runAsync(loadScreenshotFonts);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(RepaintBoundary(
        key: key,
        child: ProviderScope(
          overrides: hubTestOverrides(settings),
          child: MaterialApp(
            theme: screenshotTheme(),
            debugShowCheckedModeBanner: false,
            home: screen,
          ),
        ),
      ));
      await tester.pumpAndSettle();
      await expectLater(find.byKey(key),
          matchesGoldenFile('../../docs/ux/screenshots/after/$name.png'));
    });
  }

  void reportShot(String name, HubSettings settings, String title,
          FutureProvider<ReportResult> provider, {Size size = phone}) =>
      screenShot(name, settings,
          AggregatingReportViewerScreen(title: title, provider: provider),
          size: size);

  Future<void> tapMore(WidgetTester t) => t.tap(find.descendant(
      of: find.byType(NavigationBar), matching: find.text('More')));

  shot('services_phone_home', services);
  shot('services_phone_more', services, then: tapMore);
  shot('services_phone_money', services, location: '/w/finance');
  shot('services_phone_sales', services, location: '/w/sales_fulfilment');
  shot('services_phone_reports', services, location: '/w/finance/reports');
  shot('services_phone_features', services, location: '/w/setup/features');
  shot('services_phone_hidden_feature', services,
      location: '/w/sales_fulfilment/rentals');
  shot('services_small_phone_large_text', services,
      size: small, textScale: 2);
  shot('services_phone_money_accountant',
      services.withUserMode(HubUserMode.accountant),
      location: '/w/finance');
  shot('trade_phone_home', trade);
  shot('retail_phone_home', retail);
  shot('services_tablet_home', services, size: tablet);
  shot('services_desktop_home', services, size: desktop);
  reportShot('phone_profit_and_loss', services, 'Profit & loss',
      profitAndLossProvider);
  reportShot('phone_who_owes_you', services, 'Who owes you', arAgingProvider);
  reportShot('phone_balance_sheet', services, 'Balance sheet',
      balanceSheetProvider);
  reportShot('phone_profit_and_loss_accountant',
      services.withUserMode(HubUserMode.accountant), 'Profit & Loss',
      profitAndLossProvider);
  screenShot('phone_onboarding', const HubSettings(), const OnboardingScreen(),
      size: const Size(390, 1400));
  shot('legacy_phone_features', HubSettings.legacy(),
      location: '/w/setup/features');
}
