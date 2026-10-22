import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

import '../features/hub_feature.dart';
import '../settings/hub_settings.dart';
import '../workspaces/hub_workspaces.dart';
import 'hub_presentation.dart';
import 'hub_surface.dart';

/// Requirement for each workspace custom route (`/w/<ws>/<route>`), so a deep
/// link, a stale bookmark or a notification into a switched-off feature lands
/// on an explanation with a one-tap way back in — not on the screen as if the
/// feature were on, and not on "route not found". Unlisted routes are
/// essential. Record lists and forms (`/list`, `/form`) are never gated: the
/// data behind a hidden feature stays readable.
const hubRouteRequirements = <String, Requirement>{
  'inbox': NeedsTeam(),
  'low-stock': NeedsFeature(HubFeature.stock),
  'stock-count': NeedsFeature(HubFeature.stock),
  'driver-today': NeedsFeature(HubFeature.deliveries),
  'route': NeedsFeature(HubFeature.deliveries),
  'schedule':
      NeedsAnyFeature([HubFeature.appointments, HubFeature.fieldService]),
  'booking': NeedsFeature(HubFeature.appointments),
  'commissions': NeedsFeature(HubFeature.appointments),
  'assets': NeedsFeature(HubFeature.fixedAssets),
  'rentals': NeedsFeature(HubFeature.rentals),
  'rent-roll': NeedsFeature(HubFeature.property),
  'members': NeedsFeature(HubFeature.memberships),
  'contracts': NeedsFeature(HubFeature.construction),
  'dispatch': NeedsFeature(HubFeature.fieldService),
  'tech-today': NeedsFeature(HubFeature.fieldService),
  'equipment': NeedsFeature(HubFeature.fieldService),
  'field-service-kpis': NeedsFeature(HubFeature.fieldService),
  'pos-till': NeedsFeature(HubFeature.pos),
  'tables': NeedsFeature(HubFeature.hospitality),
  'kitchen': NeedsFeature(HubFeature.hospitality),
  'hospitality-audit': NeedsFeature(HubFeature.hospitality),
  'work-order-complete': NeedsFeature(HubFeature.manufacturing),
  'report-builder': NeedsAccountant(),
};

/// The requirement in force for a workspace location.
Requirement? hubRequirementFor(String workspaceId, String? routeName) =>
    routeName != null
        ? hubRouteRequirements[routeName]
        : hubWorkspaceRequirements[workspaceId];

/// The phone's primary destinations for the business profile — at most four
/// (the shell adds "More", which lists every other visible area).
///
/// * Services: Today · Customers · Invoices · Money
/// * Trade / Manufacturing / Mixed: Today · Sales · Stock · Money
/// * Retail: Today · Till · Stock · Money
///
/// A destination whose feature is switched off falls back to an essential one
/// so the bar never points at a hidden area.
List<ShellDestination> hubPhoneDestinations(HubSurface s) {
  const today = ShellDestination(
    id: 'today', label: 'Today', location: '/w/home',
    icon: Icons.today_outlined, selectedIcon: Icons.today,
  );
  const money = ShellDestination(
    id: 'money', label: 'Money', location: '/w/finance',
    icon: Icons.account_balance_wallet_outlined,
    selectedIcon: Icons.account_balance_wallet,
    semanticsHint: 'Get paid, pay suppliers, bank and VAT',
  );
  const customers = ShellDestination(
    id: 'customers', label: 'Customers', location: '/list/Customer',
    matchPrefixes: ['/form/Customer/', '/w/sales_fulfilment/customer-account',
        '/w/sales_fulfilment/customer-statement'],
    icon: Icons.people_outline, selectedIcon: Icons.people,
  );
  const invoices = ShellDestination(
    id: 'invoices', label: 'Invoices', location: '/list/Sales Invoice',
    matchPrefixes: ['/form/Sales Invoice/', '/list/Quotation',
        '/form/Quotation/'],
    icon: Icons.receipt_long_outlined, selectedIcon: Icons.receipt_long,
  );
  const sales = ShellDestination(
    id: 'sales', label: 'Sales', location: '/w/sales_fulfilment',
    matchPrefixes: ['/list/Sales Invoice', '/form/Sales Invoice/',
        '/list/Quotation', '/form/Quotation/', '/list/Sales Order',
        '/form/Sales Order/', '/list/Customer', '/form/Customer/'],
    icon: Icons.sell_outlined, selectedIcon: Icons.sell,
  );
  const stock = ShellDestination(
    id: 'stock', label: 'Stock', location: '/w/inventory',
    matchPrefixes: ['/list/Item', '/form/Item/', '/list/Stock Entry',
        '/form/Stock Entry/'],
    icon: Icons.inventory_2_outlined, selectedIcon: Icons.inventory_2,
  );
  const till = ShellDestination(
    id: 'till', label: 'Till', location: '/w/sales_fulfilment/pos-till',
    icon: Icons.point_of_sale_outlined, selectedIcon: Icons.point_of_sale,
  );

  final hasStock = s.has(HubFeature.stock);
  final second = switch (s.settings.businessPresetId) {
    'services' || '' when !hasStock => customers,
    'retail' when s.has(HubFeature.pos) => till,
    _ => sales,
  };
  final third = switch (second.id) {
    'customers' => invoices,
    _ => hasStock ? stock : (second.id == 'sales' ? invoices : sales),
  };
  return [today, second, third, money];
}

/// Shows the real screen when its requirement is met; otherwise explains
/// what is hidden and offers the one switch that brings it back.
Widget hubRouteGate(
  BuildContext context, {
  required String workspaceId,
  required String? routeName,
  required WidgetBuilder child,
}) =>
    _HubRouteGate(
      requirement: hubRequirementFor(workspaceId, routeName),
      child: child,
    );

class _HubRouteGate extends ConsumerWidget {
  const _HubRouteGate({required this.requirement, required this.child});

  final Requirement? requirement;
  final WidgetBuilder child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final surface = ref.watch(hubSurfaceProvider);
    if (surface.allows(requirement)) return child(context);
    return HiddenFeatureView(requirement: requirement!);
  }
}

/// The landing for a link into something this installation does not show.
class HiddenFeatureView extends ConsumerStatefulWidget {
  const HiddenFeatureView({super.key, required this.requirement});

  final Requirement requirement;

  @override
  ConsumerState<HiddenFeatureView> createState() => _HiddenFeatureViewState();
}

class _HiddenFeatureViewState extends ConsumerState<HiddenFeatureView> {
  bool _busy = false;

  Future<void> _apply(HubSettings next) async {
    setState(() => _busy = true);
    await ref.read(hubSettingsProvider.notifier).apply(next);
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(hubSettingsProvider);
    final (String title, String message, String action, VoidCallback onTap,
        IconData icon) = switch (widget.requirement) {
      NeedsFeature(:final feature) => (
          '${feature.label} is turned off',
          'Nothing was deleted: records made with it are kept and still '
              'searchable. Turn it on to work with them here again.',
          'Turn on ${feature.label}',
          () => _apply(settings.withFeature(feature, true)),
          feature.icon,
        ),
      NeedsAnyFeature(:final features) => (
          '${features.map((f) => f.label).join(' / ')} is turned off',
          'Turn one of these features on to use this screen.',
          'Turn on ${features.first.label}',
          () => _apply(settings.withFeature(features.first, true)),
          features.first.icon,
        ),
      NeedsAccountant() => (
          'Shown in the Accountant view',
          'This is an accounting tool. Switching view changes only what is '
              'shown — posting rules and permissions stay the same.',
          'Switch to Accountant view',
          () => _apply(settings.withUserMode(HubUserMode.accountant)),
          Icons.account_balance_outlined,
        ),
      NeedsTeam() => (
          'Part of Atlas Team',
          'Approvals route work between people, so they need this device '
              'connected to an Atlas Team company.',
          'Atlas Team settings',
          () => context.go('/w/setup/team'),
          Icons.cloud_outlined,
        ),
      NeedsSystemTools() => (
          'System configuration is hidden',
          'Designers for record types, workflows and fields are for '
              'implementers.',
          'Show system configuration',
          () => _apply(settings.copyWith(systemTools: true)),
          Icons.build_outlined,
        ),
    };
    return ResponsiveScaffold(
      title: title,
      body: EmptyState(
        icon: icon,
        title: title,
        message: message,
        action: Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: [
            FilledButton(
              onPressed: _busy ? null : onTap,
              child: Text(action),
            ),
            OutlinedButton(
              onPressed: () => context.go('/w/home'),
              child: const Text('Back to Today'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Provider overrides that let the business profile drive the Core shell:
/// live workspace visibility, the phone bar, deep-link gating and business
/// language. Installed by `main` (and by tests that render the real shell).
final hubShellOverrides = <Override>[
  visibleWorkspacesProvider.overrideWith((ref) {
    final workspaces = hubWorkspaces(ref.watch(hubSurfaceProvider));
    // Keep the router's id lookup in step with what is shown, so turning a
    // feature on or off applies immediately rather than on next launch.
    ref.read(workspaceRegistryProvider).replaceWorkspaces(workspaces);
    return const WorkspaceVisibilityFilter()
        .apply(workspaces, ref.watch(permissionContextProvider));
  }),
  phoneDestinationsProvider
      .overrideWith((ref) => hubPhoneDestinations(ref.watch(hubSurfaceProvider))),
  workspaceRouteGateProvider.overrideWithValue(hubRouteGate),
  docTypePresentationProvider.overrideWith((ref) {
    final plain = ref.watch(hubSurfaceProvider).plainLanguage;
    return plain ? ownerPresentation : (_) => DocTypePresentation.engine;
  }),
];
