import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';
import '../dashboards/hub_dashboard_cards.dart';
import '../mock/mock_data.dart';
import '../screens/approvals_inbox_screen.dart';
import '../screens/customer_account_screen.dart';
import '../screens/delivery_route_screen.dart';
import '../screens/driver_today_screen.dart';
import '../screens/low_stock_screen.dart';
import '../screens/sales_orders_screen.dart';
import '../workspaces/hub_workspaces.dart';

/// Override [approvalInboxSourceProvider] so the prototype gets mock data.
final hubApprovalInboxSourceOverride = approvalInboxSourceProvider.overrideWith(
  (ref) => StaticApprovalInboxSource(MockData.approvals()),
);

/// Called once on boot to register workspaces, custom routes, and card builders.
void wireHubNavigation(WidgetRef ref) {
  final registry = ref.read(workspaceRegistryProvider);
  if (registry.all.isEmpty) {
    registerHubWorkspaces(registry);

    // Workspace-level custom routes — these are addressed as
    //   /w/<workspaceId>/<routeName>
    registry.registerRoute('inbox', (c, s) => const ApprovalsInboxScreen());
    registry.registerRoute('low-stock', (c, s) => const LowStockScreen());
    registry.registerRoute('driver-today',
        (c, s) => const DriverTodayScreen());
    registry.registerRoute('route', (c, s) => const DeliveryRouteScreen());
    registry.registerRoute('customer-account',
        (c, s) => const CustomerAccountScreen());
    registry.registerRoute('sales-orders',
        (c, s) => const SalesOrdersScreen());
  }

  registerHubDashboardCards(ref);
}
