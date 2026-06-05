import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';
import '../dashboards/hub_dashboard_cards.dart';
import '../mock/mock_data.dart';
import '../screens/dashboards_screen.dart';
import '../screens/approvals_inbox_screen.dart';
import '../screens/customer_account_screen.dart';
import '../screens/delivery_route_screen.dart';
import '../screens/driver_today_screen.dart';
import '../screens/low_stock_screen.dart';
import '../screens/reports_screen.dart';
import '../screens/sales_orders_screen.dart';
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

/// Identifies the logged-in user. Replace with real auth.
final hubCurrentUserOverride = currentUserProvider.overrideWith(
  (_) => const CurrentUser(
    id: 'kevin',
    displayName: 'Kevin Busuttil',
    email: 'kevin@mercantis.local',
    roles: {'System Manager'},
  ),
);

/// Called once on boot to register workspaces, custom routes, and card
/// builders.
void wireHubNavigation(WidgetRef ref) {
  final registry = ref.read(workspaceRegistryProvider);
  if (registry.all.isEmpty) {
    registerHubWorkspaces(registry);

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
  }

  registerHubDashboardCards(ref);
}
