import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart' show ReportResult;
import 'package:mercantis_core_ui/mercantis_core_ui.dart';
import 'package:mercantis_hub_app/onboarding/business_preset.dart';
import 'package:mercantis_hub_app/reports/report_providers.dart';
import 'package:mercantis_hub_app/screens/onboarding_screen.dart';
import 'package:mercantis_hub_app/screens/reports_screen.dart';
import 'package:mercantis_hub_app/screens/startup_error_screen.dart';
import 'package:mercantis_hub_app/screens/support_screen.dart';
import 'package:mercantis_hub_app/settings/hub_settings.dart';
import 'package:mercantis_hub_app/support/support_diagnostics.dart';

import '../support/hub_app_harness.dart';

/// Automated accessibility checks (plan M1.2 accessibility acceptance) over
/// the screens of the ten Solo journeys that render without a database:
/// the phone/tablet shell and its workspaces, the summary-first reports,
/// first-run setup and the support screens.
///
/// Guidelines (Flutter's implementations of the platform rules):
/// - Android tap targets ≥ 48×48 dp, iOS tap targets ≥ 44×44 pt;
/// - every tappable element has a semantic label;
/// - text contrast ≥ 4.5:1 (3:1 for large text), WCAG AA.
///
/// What this does NOT prove: TalkBack/VoiceOver reading order and
/// announcements, keyboard-only operation, or physical ergonomics. Those are
/// manual rows in docs/release/ACCESSIBILITY_ACCEPTANCE.md and stay PENDING
/// until someone performs them on a device. Database-backed list and form
/// screens are not covered here (see that document).
void main() {
  final guidelines = <String, AccessibilityGuideline>{
    'Android tap target': androidTapTargetGuideline,
    'iOS tap target': iOSTapTargetGuideline,
    'labelled tap target': labeledTapTargetGuideline,
    'text contrast': textContrastGuideline,
  };

  final services = presetSettings(BusinessPreset.services);
  final trade = presetSettings(BusinessPreset.trade);
  final retail = presetSettings(BusinessPreset.retail);
  const phone = Size(390, 844);
  const tablet = Size(1024, 768);

  void route(String name, HubSettings settings,
      {String location = '/w/home', Size size = phone, bool dark = false}) {
    for (final g in guidelines.entries) {
      testWidgets('$name: ${g.key}', (tester) async {
        final semantics = tester.ensureSemantics();
        await pumpHub(tester,
            settings: settings,
            location: location,
            size: size,
            theme: dark ? MercantisTheme.dark() : null);
        await expectLater(tester, meetsGuideline(g.value));
        semantics.dispose();
      });
    }
  }

  void screen(String name, Widget child,
      {HubSettings? settings, Size size = phone}) {
    for (final g in guidelines.entries) {
      testWidgets('$name: ${g.key}', (tester) async {
        final semantics = tester.ensureSemantics();
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(ProviderScope(
          overrides: hubTestOverrides(settings ?? services),
          child: MaterialApp(
            theme: MercantisTheme.light(),
            debugShowCheckedModeBanner: false,
            home: child,
          ),
        ));
        await tester.pumpAndSettle();
        await expectLater(tester, meetsGuideline(g.value));
        semantics.dispose();
      });
    }
  }

  void report(String name, String title, FutureProvider<ReportResult> p) =>
      screen(name, AggregatingReportViewerScreen(title: title, provider: p));

  group('shell and workspaces', () {
    route('Services home (phone)', services);
    route('Trade home (phone)', trade);
    route('Retail home (phone)', retail);
    route('Services home (tablet)', services, size: tablet);
    route('Services home (phone, dark)', services, dark: true);
    route('Money (phone)', services, location: '/w/finance');
    route('Sales (phone)', services, location: '/w/sales_fulfilment');
    route('Reports (phone)', services, location: '/w/finance/reports');
    route('Setup (phone)', services, location: '/w/setup');
    route('Business type & features (phone)', services,
        location: '/w/setup/features');
  });

  group('summary-first reports', () {
    report('Profit & loss', 'Profit & loss', profitAndLossProvider);
    report('Who owes you (AR ageing)', 'Who owes you', arAgingProvider);
    report('Balance sheet', 'Balance sheet', balanceSheetProvider);
  });

  group('first run and support', () {
    screen('First-run setup', const OnboardingScreen(),
        settings: const HubSettings(), size: const Size(390, 1400));
    testWidgets('Help & diagnostics: all guidelines', (tester) async {
      final semantics = tester.ensureSemantics();
      final r = await SupportDiagnostics.collect(
          bootError: 'example', includeIntegrityCheck: false);
      await tester.pumpWidget(MaterialApp(
          theme: MercantisTheme.light(),
          home: Scaffold(body: DiagnosticsReportView(report: r))));
      for (final g in guidelines.values) {
        await expectLater(tester, meetsGuideline(g));
      }
      semantics.dispose();
    });
    testWidgets('Start-up error: all guidelines', (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(MaterialApp(
          theme: MercantisTheme.light(),
          home: const StartupErrorScreen(error: 'example')));
      await tester.pumpAndSettle();
      for (final g in guidelines.values) {
        await expectLater(tester, meetsGuideline(g));
      }
      semantics.dispose();
    });
  });
}
