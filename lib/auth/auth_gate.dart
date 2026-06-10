import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

import 'auth_store.dart';
import 'lock_screen.dart';
import 'operator_setup_screen.dart';

/// Sits between onboarding and the workspace shell: blocks the app until an
/// operator profile is unlocked. First run sends you through profile creation;
/// thereafter a cold start re-locks and shows the passcode gate.
class AuthGate extends ConsumerWidget {
  const AuthGate({super.key, required this.child});

  /// The unlocked app (the router shell).
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);

    if (!auth.hydrated) return const _AuthSplash();
    if (!auth.hasProfiles) {
      return const _AuthShell(child: OperatorSetupScreen(firstRun: true));
    }
    if (!auth.unlocked) return const _AuthShell(child: LockScreen());
    return child;
  }
}

/// A MaterialApp wrapper for the pre-shell auth screens (the unlocked app
/// supplies its own MaterialApp.router).
class _AuthShell extends StatelessWidget {
  const _AuthShell({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: MercantisTheme.light(),
      darkTheme: MercantisTheme.dark(),
      themeMode: ThemeMode.system,
      debugShowCheckedModeBanner: false,
      home: child,
    );
  }
}

class _AuthSplash extends StatelessWidget {
  const _AuthSplash();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: MercantisTheme.light(),
      darkTheme: MercantisTheme.dark(),
      themeMode: ThemeMode.system,
      debugShowCheckedModeBanner: false,
      home: const Scaffold(body: Center(child: CircularProgressIndicator())),
    );
  }
}
