import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';
import 'manifest/hub_manifest.dart';
import 'navigation/hub_navigation.dart';

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
      data: (_) => const _HubRouterApp(),
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

/// Boot: install the DocType manifest if not already installed.
final _bootProvider = FutureProvider<void>((ref) async {
  final installer = await ref.watch(appInstallerProvider.future);
  final manifest = HubManifest.build();
  final isInstalled = await installer.isInstalled(manifest.id);
  if (!isInstalled) {
    await installer.install(manifest);
  }
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
