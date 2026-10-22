import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';
import 'package:mercantis_hub_app/navigation/hub_navigation.dart';
import 'package:mercantis_hub_app/navigation/hub_shell.dart';
import 'package:mercantis_hub_app/onboarding/business_preset.dart';
import 'package:mercantis_hub_app/settings/hub_settings.dart';

import 'synthetic_business.dart';

/// Holds settings for a test; [apply] updates state without a database so
/// screens that save (feature switches, the hidden-feature view) work.
class FixedHubSettings extends HubSettingsNotifier {
  FixedHubSettings(this.initial);
  final HubSettings initial;

  @override
  HubSettings build() => initial;

  @override
  Future<void> apply(HubSettings next) async => state = next;
}

/// Settings as onboarding leaves them for [preset].
HubSettings presetSettings(BusinessPreset preset) =>
    const HubSettings().applyingPreset(preset);

/// The real Hub router and adaptive shell, with the production navigation
/// wiring and shell overrides, over the [SyntheticBusiness] fixture.
class HubAppHost extends ConsumerStatefulWidget {
  const HubAppHost({super.key, required this.initialLocation, this.theme});

  final String initialLocation;
  final ThemeData? theme;

  @override
  ConsumerState<HubAppHost> createState() => _HubAppHostState();
}

class _HubAppHostState extends ConsumerState<HubAppHost> {
  late final GoRouter _router = () {
    wireHubNavigation(ref);
    return ref.read(appNavigationRegistryProvider).buildRouter(
        initialLocation: widget.initialLocation,
        brandLabel: 'Neuradix Atlas',
        brandMark: 'N');
  }();

  @override
  Widget build(BuildContext context) => MaterialApp.router(
        theme: widget.theme ?? MercantisTheme.light(),
        debugShowCheckedModeBanner: false,
        routerConfig: _router,
      );
}

/// Provider overrides for a Hub app under test.
List<Override> hubTestOverrides(
  HubSettings settings, {
  SyntheticBusiness? business,
  bool teamConnected = false,
}) =>
    [
      ...(business ?? SyntheticBusiness()).overrides(),
      hubSettingsProvider.overrideWith(() => FixedHubSettings(settings)),
      approvalInboxSourceProvider
          .overrideWith((ref) => StaticApprovalInboxSource(const [])),
      ...hubShellOverrides,
    ];

/// Pumps the Hub at [location] on a [size] screen with [textScale].
Future<ProviderContainer> pumpHub(
  WidgetTester tester, {
  required HubSettings settings,
  String location = '/w/home',
  Size size = const Size(390, 844),
  double textScale = 1,
  ThemeData? theme,
  Key? boundaryKey,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(RepaintBoundary(
    key: boundaryKey,
    child: ProviderScope(
      overrides: hubTestOverrides(settings),
      child: HubAppHost(initialLocation: location, theme: theme),
    ),
  ));
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(tester.element(find.byType(HubAppHost)));
}
