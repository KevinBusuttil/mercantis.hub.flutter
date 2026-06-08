import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';
import '../dashboards/hub_dashboard_cards.dart';
import '../mock/mock_data.dart';
import '../screens/dashboards_screen.dart';
import '../screens/approvals_inbox_screen.dart';
import '../screens/customer_account_screen.dart';
import '../screens/delivery_route_screen.dart';
import '../screens/driver_today_screen.dart';
import '../screens/guided_payment_screen.dart';
import '../screens/low_stock_screen.dart';
import '../screens/pos_till_screen.dart';
import '../screens/reports_screen.dart';
import '../screens/sales_orders_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/work_order_complete_screen.dart';
import '../settings/hub_settings.dart';
import '../workspaces/hub_workspaces.dart';

/// Prototype: serve the approval inbox from in-memory mock entries.
final mockApprovalInboxSourceOverride = approvalInboxSourceProvider.overrideWith(
  (ref) => StaticApprovalInboxSource(MockData.approvals()),
);

/// Production: serve the approval inbox by scanning every submittable
/// DocType for documents in docStatus=0.
final metadataApprovalInboxSourceOverride =
    approvalInboxSourceProvider.overrideWith(
  (ref) => MetadataApprovalInboxSource(
    ref,
    userRoles: ref.watch(currentUserProvider).roles,
  ),
);

/// Backwards-compatible alias used by main.dart.
final hubApprovalInboxSourceOverride = mockApprovalInboxSourceOverride;

/// The active operator, sourced from persisted [HubSettings] (editable in
/// Settings) rather than hardcoded. Roles stay System Manager until a real
/// identity provider is wired.
final hubCurrentUserOverride = currentUserProvider.overrideWith((ref) {
  final s = ref.watch(hubSettingsProvider);
  return CurrentUser(
    id: 'operator',
    displayName: s.operatorName,
    email: s.operatorEmail,
    roles: const {'System Manager'},
  );
});

/// Optional modules can be hidden via Settings; gate their workspaces here.
/// (Takes effect on next launch, mirroring the Swift visibility model.)
bool _workspaceEnabled(String id, HubSettings s) {
  switch (id) {
    case 'manufacturing':
      return s.manufacturingEnabled;
    case 'delivery':
      return s.deliveriesEnabled;
    default:
      return true;
  }
}

/// Called once on boot to register workspaces, custom routes, and card
/// builders.
void wireHubNavigation(WidgetRef ref) {
  final registry = ref.read(workspaceRegistryProvider);
  if (registry.all.isEmpty) {
    final settings = ref.read(hubSettingsProvider);
    registry.registerAll([
      for (final w in hubWorkspaces)
        if (_workspaceEnabled(w.id, settings)) w,
    ]);

    // Workspace-level custom routes — addressed as /w/<workspaceId>/<name>.
    registry.registerRoute('inbox', (c, s) => const ApprovalsInboxScreen());
    registry.registerRoute('low-stock', (c, s) => const LowStockScreen());
    registry.registerRoute('driver-today',
        (c, s) => const DriverTodayScreen());
    registry.registerRoute('route', (c, s) => const DeliveryRouteScreen());
    registry.registerRoute('customer-account',
        (c, s) => const CustomerAccountScreen());
    registry.registerRoute('sales-orders',
        (c, s) => const SalesOrdersScreen());
    registry.registerRoute('reports', (c, s) => const ReportsScreen());
    registry.registerRoute('dashboards', (c, s) => const DashboardsScreen());
    registry.registerRoute(
        'receive-payment', (c, s) => const GuidedPaymentScreen(receive: true));
    registry.registerRoute(
        'pay-supplier', (c, s) => const GuidedPaymentScreen(receive: false));
    registry.registerRoute('pos-till', (c, s) => const PosTillScreen());
    registry.registerRoute(
        'work-order-complete', (c, s) => const WorkOrderCompleteScreen());
    registry.registerRoute('settings', (c, s) => const SettingsScreen());
  }

  registerHubDashboardCards(ref);
}
