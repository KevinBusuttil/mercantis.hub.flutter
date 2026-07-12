import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';
import 'auth/auth_gate.dart';
import 'auth/auth_store.dart';
import 'manifest/hub_manifest.dart';
import 'field_service/maintenance_contract_service.dart';
import 'modules/selling/recurring_invoice_service.dart';
import 'printing/hub_print_formats.dart';
import 'navigation/hub_navigation.dart';
import 'deliveries/delivery_route_service.dart';
import 'ledger/ledger_derivation_service.dart';
import 'manufacturing/manufacturing_service.dart';
import 'onboarding/onboarding_providers.dart';
import 'screens/onboarding_screen.dart';
import 'settings/hub_settings.dart';
import 'sync/company_sync.dart';
import 'team/team_session.dart';

class MercantisHubApp extends ConsumerWidget {
  const MercantisHubApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bootAsync = ref.watch(_bootProvider);
    return bootAsync.when(
      loading: () => MaterialApp(
        theme: MercantisTheme.light(),
        darkTheme: MercantisTheme.dark(),
        themeMode: ref.watch(themeModeProvider),
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
        themeMode: ref.watch(themeModeProvider),
        debugShowCheckedModeBanner: false,
        home: const _HubSplashScreen(),
      ),
      error: (e, _) => MaterialApp(
        theme: MercantisTheme.light(),
        debugShowCheckedModeBanner: false,
        home: Scaffold(body: Center(child: Text('Setup check failed: $e'))),
      ),
      data: (exists) => exists
          ? const AuthGate(child: _HubRouterApp())
          : MaterialApp(
              theme: MercantisTheme.light(),
              darkTheme: MercantisTheme.dark(),
              themeMode: ref.watch(themeModeProvider),
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
    // Instantiate the company-sync controller so background sync runs while
    // signed in. Reading the notifier (not its state) keeps it alive without
    // rebuilding the app on every sync tick.
    ref.read(companySyncProvider.notifier);
    final router = ref.watch(_hubRouterProvider);
    return MaterialApp.router(
      title: 'Neuradix Atlas',
      theme: MercantisTheme.light(),
      darkTheme: MercantisTheme.dark(),
      themeMode: ref.watch(themeModeProvider),
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}

final _hubRouterProvider = Provider((ref) {
  final nav = ref.watch(appNavigationRegistryProvider);
  // Brand the Atlas shell (rail / sidebar) to match the rest of the app, and
  // light up the shell notifications bell (badged with the operator's unread
  // count) pointing at the home workspace's notifications route.
  return nav.buildRouter(
    brandLabel: 'Neuradix Atlas',
    brandMark: 'N',
    notificationsLocation: '/w/home/notifications',
  );
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
  // Subscribe the delivery-route service (status events + Delivery Note mirror).
  await ref.watch(deliveryRouteServiceProvider.future);
  // Load persisted preferences (module visibility) and operator profiles.
  final engine = await ref.watch(documentEngineProvider.future);
  // Brand printed documents: register the company letterhead so every PDF
  // carries the business identity (changes apply on next launch, like
  // module visibility).
  final companies = await engine.list('Company', userRoles: const {'System Manager'});
  if (companies.isNotEmpty) {
    ref
        .read(printServiceProvider)
        .registerLetterHead(companyLetterHead(companies.first.payload));
  }
  await ref.read(hubSettingsProvider.notifier).hydrate(engine);
  await ref.read(authProvider.notifier).hydrate(engine);
  // Load the persisted theme mode (light/dark/system).
  await ref.read(themeModeProvider.notifier).hydrate();
  // Restore this device's Atlas Team connection, if it has one (Team
  // milestone 2). Lives in preferences, never in the synced store.
  await ref.read(teamSessionProvider.notifier).hydrate();
  // Draft whatever recurring invoices are due (retainers). Failures are
  // stamped on each template's last_error rather than blocking boot.
  await ref.read(recurringInvoiceRunProvider.future);
  await ref.read(maintenanceContractRunProvider.future);
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
            Text('Neuradix Atlas', style: theme.textTheme.titleLarge),
            const SizedBox(height: 24),
            const CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}
