import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class _Dest {
  const _Dest(this.label, this.icon, this.selectedIcon, this.path);
  final String label;
  final Widget icon;
  final Widget selectedIcon;
  final String path;
}

const _destinations = [
  _Dest('Home', Icon(Icons.home_outlined), Icon(Icons.home), '/home'),
  _Dest('CRM', Icon(Icons.people_outline), Icon(Icons.people), '/list/Customer'),
  _Dest('Selling', Icon(Icons.receipt_long_outlined), Icon(Icons.receipt_long), '/list/Sales Invoice'),
  _Dest('Buying', Icon(Icons.shopping_cart_outlined), Icon(Icons.shopping_cart), '/list/Purchase Invoice'),
  _Dest('Stock', Icon(Icons.inventory_2_outlined), Icon(Icons.inventory_2), '/list/Item'),
  _Dest('Accounting', Icon(Icons.account_balance_outlined), Icon(Icons.account_balance), '/list/Journal Entry'),
];

class HubShell extends ConsumerWidget {
  const HubShell({super.key, required this.child});
  final Widget child;

  int _selectedIndex(BuildContext context) {
    final loc = GoRouterState.of(context).matchedLocation;
    for (int i = 0; i < _destinations.length; i++) {
      if (loc.startsWith(_destinations[i].path)) return i;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wide = MediaQuery.sizeOf(context).width >= 800;
    final selected = _selectedIndex(context);

    if (wide) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: selected,
              onDestinationSelected: (i) =>
                  context.go(_destinations[i].path),
              leading: const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: _HubLogo(),
              ),
              destinations: [
                for (final d in _destinations)
                  NavigationRailDestination(
                    icon: d.icon,
                    selectedIcon: d.selectedIcon,
                    label: Text(d.label),
                  ),
              ],
            ),
            const VerticalDivider(thickness: 1, width: 1),
            Expanded(child: child),
          ],
        ),
      );
    }

    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: selected,
        onDestinationSelected: (i) => context.go(_destinations[i].path),
        destinations: [
          for (final d in _destinations)
            NavigationDestination(
              icon: d.icon,
              selectedIcon: d.selectedIcon,
              label: d.label,
            ),
        ],
      ),
    );
  }
}

class _HubLogo extends StatelessWidget {
  const _HubLogo();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.hub, color: Colors.white, size: 20),
        ),
        const SizedBox(height: 4),
        Text(
          'Hub',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
        ),
      ],
    );
  }
}
