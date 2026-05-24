import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';
import 'manifest/hub_manifest.dart';
import 'navigation/hub_router.dart';

class MercantisHubApp extends ConsumerWidget {
  const MercantisHubApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bootAsync = ref.watch(_bootProvider);
    return bootAsync.when(
      loading: () => const MaterialApp(
        home: Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _HubSplash(),
                SizedBox(height: 24),
                CircularProgressIndicator(),
              ],
            ),
          ),
        ),
      ),
      error: (e, _) => MaterialApp(
        home: Scaffold(body: Center(child: Text('Boot error: $e'))),
      ),
      data: (_) {
        final router = ref.watch(hubRouterProvider);
        return MaterialApp.router(
          title: 'Mercantis Hub',
          theme: MercantisTheme.light(),
          darkTheme: MercantisTheme.dark(),
          themeMode: ThemeMode.system,
          routerConfig: router,
          debugShowCheckedModeBanner: false,
        );
      },
    );
  }
}

// Installs HubManifest then resolves to unit.
final _bootProvider = FutureProvider<void>((ref) async {
  final installer = await ref.watch(appInstallerProvider.future);
  final manifest = HubManifest.build();
  final isInstalled = await installer.isInstalled(manifest.id);
  if (!isInstalled) {
    await installer.install(manifest);
  }
});

class _HubSplash extends StatelessWidget {
  const _HubSplash();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary,
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Icon(Icons.hub, color: Colors.white, size: 40),
        ),
        const SizedBox(height: 12),
        Text(
          'Mercantis Hub',
          style: Theme.of(context).textTheme.titleLarge,
        ),
      ],
    );
  }
}
