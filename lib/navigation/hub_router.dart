import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';
import 'hub_shell.dart';

final hubRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/home',
    routes: [
      ShellRoute(
        builder: (context, state, child) => HubShell(child: child),
        routes: [
          GoRoute(
            path: '/home',
            builder: (context, state) => const DocTypeListView(),
          ),
          GoRoute(
            path: '/list/:docType',
            builder: (context, state) =>
                GenericListView(docTypeName: state.pathParameters['docType']!),
          ),
          GoRoute(
            path: '/form/:docType/new',
            builder: (context, state) => GenericFormView(
              docTypeName: state.pathParameters['docType']!,
              documentName: null,
            ),
          ),
          GoRoute(
            path: '/form/:docType/:name',
            builder: (context, state) => GenericFormView(
              docTypeName: state.pathParameters['docType']!,
              documentName: state.pathParameters['name'],
            ),
          ),
          GoRoute(
            path: '/settings',
            builder: (context, state) => const _SettingsView(),
          ),
        ],
      ),
    ],
  );
});

class _SettingsView extends StatelessWidget {
  const _SettingsView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: const Center(child: Text('Settings coming soon')),
    );
  }
}
