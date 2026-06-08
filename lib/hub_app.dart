import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';
import 'manifest/hub_manifest.dart';
import 'navigation/hub_navigation.dart';
import 'ledger/ledger_derivation_service.dart';
import 'manufacturing/manufacturing_service.dart';
import 'onboarding/onboarding_providers.dart';
import 'screens/onboarding_screen.dart';

class MercantisHubApp extends ConsumerWidget {
  const MercantisHubApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bootAsync = ref.watch(_bootProvider);
    return bootAsync.when(
      loading: () => MaterialApp(
        theme: MercantisTheme.light(),
        darkTheme: MercantisTheme.dark(),
        themeMode: ThemeMode.system,
        debugShowCheckedModeBanner: false,
        home: const _HubSplashScreen(),
      ),
      error: (e, _) => MaterialApp(
        theme: MercantisTheme.light(),
        debugShowCheckedModeBanner: false,
        home: Scaffold(body: Center(child: Text('Boot error: $e'))),
      ),
      data: (_) => const _OnboardingGate(),
    );
  }
}

/// After boot, route to onboarding when the install has no Company yet,
/// otherwise to the workspace shell. The onboarding screen carries its own
/// [MaterialApp] since the shell only mounts once setup is complete.
class _OnboardingGate extends ConsumerWidget {
  const _OnboardingGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasCompany = ref.watch(companyExistsProvider);
    return hasCompany.when(
      loading: () => MaterialApp(
        theme: MercantisTheme.light(),
        darkTheme: MercantisTheme.dark(),
        themeMode: ThemeMode.system,
        debugShowCheckedModeBanner: false,
        home: const _HubSplashScreen(),
      ),
      error: (e, _) => MaterialApp(
        theme: MercantisTheme.light(),
        debugShowCheckedModeBanner: false,
        home: Scaffold(body: Center(child: Text('Setup check failed: $e'))),
      ),
      data: (exists) => exists
          ? const _HubRouterApp()
          : MaterialApp(
              theme: MercantisTheme.light(),
              darkTheme: MercantisTheme.dark(),
              themeMode: ThemeMode.system,
              debugShowCheckedModeBanner: false,
              home: const OnboardingScreen(),
            ),
    );
  }
}

class _HubRouterApp extends ConsumerWidget {
  const _HubRouterApp();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Lazily wire workspaces + dashboard cards. Idempotent.
    wireHubNavigation(ref);
    final router = ref.watch(_hubRouterProvider);
    return MaterialApp.router(
      title: 'Mercantis Hub',
      theme: MercantisTheme.light(),
      darkTheme: MercantisTheme.dark(),
      themeMode: ThemeMode.system,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}

final _hubRouterProvider = Provider((ref) {
  final nav = ref.watch(appNavigationRegistryProvider);
  return nav.buildRouter();
});

/// Boot: install the DocType manifest if not already installed (or re-sync its
/// metadata when it is, so manifest changes — e.g. new child-table DocTypes —
/// reach an existing database). Then wire the ledger derivation service so
/// submit/cancel posts GL, subledger, settlement, and stock-ledger rows.
final _bootProvider = FutureProvider<void>((ref) async {
  final installer = await ref.watch(appInstallerProvider.future);
  final manifest = HubManifest.build();
  final isInstalled = await installer.isInstalled(manifest.id);
  if (!isInstalled) {
    await installer.install(manifest);
  } else {
    await installer.syncMetadata(manifest);
  }
  // Subscribe the ledger spine to document events (kept alive for app life).
  await ref.watch(ledgerDerivationServiceProvider.future);
  // Subscribe the manufacturing service (Production Plan → Work Orders).
  await ref.watch(manufacturingDerivationServiceProvider.future);
});

class _HubSplashScreen extends StatelessWidget {
  const _HubSplashScreen();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72, height: 72,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.hub, color: Colors.white, size: 40),
            ),
            const SizedBox(height: 16),
            Text('Mercantis Hub', style: theme.textTheme.titleLarge),
            const SizedBox(height: 24),
            const CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}
