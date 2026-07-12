import 'package:mercantis_core_ui/mercantis_core_ui.dart';
import '../settings/hub_settings.dart';
import 'appointments_workspace.dart';
import 'approvals_workspace.dart';
import 'delivery_workspace.dart';
import 'field_service_workspace.dart';
import 'finance_workspace.dart';
import 'home_workspace.dart';
import 'inventory_workspace.dart';
import 'manufacturing_workspace.dart';
import 'purchasing_workspace.dart';
import 'projects_workspace.dart';
import 'reports_workspace.dart';
import 'sales_fulfilment_workspace.dart';
import 'setup_workspace.dart';

/// The workspaces visible for [settings] — where the business preset (and the
/// Settings module toggles it seeds) actually shapes the product: a Services
/// business sees no Stock, POS, Manufacturing or Deliveries surfaces.
/// (Visibility only — hidden modules keep their data and routes intact.)
List<WorkspaceDescriptor> hubWorkspaces(HubSettings settings) => [
      homeWorkspace,
      salesFulfilmentWorkspace(posEnabled: settings.posEnabled),
      if (settings.fieldServiceEnabled) fieldServiceWorkspace,
      if (settings.appointmentsEnabled) appointmentsWorkspace,
      if (settings.projectsEnabled) projectsWorkspace,
      purchasingWorkspace,
      if (settings.stockEnabled) inventoryWorkspace,
      if (settings.manufacturingEnabled) manufacturingWorkspace,
      if (settings.deliveriesEnabled) deliveryWorkspace,
      financeWorkspace,
      approvalsWorkspace,
      reportsWorkspace,
      setupWorkspace,
    ];

void registerHubWorkspaces(WorkspaceRegistry registry, HubSettings settings) {
  registry.registerAll(hubWorkspaces(settings));
}
