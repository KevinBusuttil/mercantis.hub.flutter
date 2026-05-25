import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'hub_modules.dart';

class _Dest {
  const _Dest(this.label, this.icon, this.selectedIcon, this.path);
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final String path;
}

List<_Dest> _buildDestinations() {
  return [
    const _Dest('Home', Icons.home_outlined, Icons.home, '/home'),
    for (final m in HubModules.all)
      _Dest(
        m.label,
        m.icon,
        m.selectedIcon ?? m.icon,
        '/module/${m.id}',
      ),
  ];
}

class HubShell extends ConsumerWidget {
  const HubShell({super.key, required this.child});
  final Widget child;

  int _selectedIndex(BuildContext context, List<_Dest> destinations) {
    final loc = GoRouterState.of(context).matchedLocation;
    // Prefer the longest matching prefix so /module/crm doesn't collide with
    // /module/.
    int bestIndex = 0;
    int bestLength = 0;
    for (int i = 0; i < destinations.length; i++) {
      final path = destinations[i].path;
      if (loc == path || loc.startsWith('$path/')) {
        if (path.length > bestLength) {
          bestIndex = i;
          bestLength = path.length;
        }
      }
    }
    return bestIndex;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final destinations = _buildDestinations();
    final wide = MediaQuery.sizeOf(context).width >= 800;
    final selected = _selectedIndex(context, destinations);

    if (wide) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: selected,
              labelType: NavigationRailLabelType.all,
              onDestinationSelected: (i) =>
                  context.go(destinations[i].path),
              leading: const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: _HubLogo(),
              ),
              destinations: [
                for (final d in destinations)
                  NavigationRailDestination(
                    icon: Icon(d.icon),
                    selectedIcon: Icon(d.selectedIcon),
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

    // On narrow layouts the bottom navigation bar shows Home + a handful of
    // modules. Anything beyond five entries is collapsed into a "More" sheet
    // so we keep room for the Material 3 NavigationBar layout.
    const maxBottomDestinations = 5;
    final showAll = destinations.length <= maxBottomDestinations;
    final visible = showAll
        ? destinations
        : destinations.sublist(0, maxBottomDestinations - 1);

    int narrowSelected = selected;
    if (!showAll && narrowSelected >= visible.length) {
      narrowSelected = 0;
    }

    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: narrowSelected,
        onDestinationSelected: (i) {
          if (!showAll && i == visible.length) {
            _showMoreSheet(context, destinations.sublist(visible.length));
            return;
          }
          context.go(visible[i].path);
        },
        destinations: [
          for (final d in visible)
            NavigationDestination(
              icon: Icon(d.icon),
              selectedIcon: Icon(d.selectedIcon),
              label: d.label,
            ),
          if (!showAll)
            const NavigationDestination(
              icon: Icon(Icons.more_horiz),
              label: 'More',
            ),
        ],
      ),
    );
  }

  void _showMoreSheet(BuildContext context, List<_Dest> overflow) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final d in overflow)
              ListTile(
                leading: Icon(d.icon),
                title: Text(d.label),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  context.go(d.path);
                },
              ),
          ],
        ),
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
