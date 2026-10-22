import 'package:mercantis_core_ui/mercantis_core_ui.dart';
import '../features/hub_feature.dart';
import '../navigation/hub_surface.dart';
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

/// The workspaces for [s] — where the business profile, the optional
/// features, the Owner/Accountant view and the Team connection shape the
/// product at workspace, section, item and quick-action level. A Services
/// business sees no stock, till, manufacturing, deliveries or specialist
/// verticals until it switches them on. (Visibility only — hidden modules
/// keep their data, services and records.)
List<WorkspaceDescriptor> hubWorkspaces(HubSurface s) => [
      homeWorkspace(s),
      salesFulfilmentWorkspace(s),
      if (s.has(HubFeature.fieldService)) fieldServiceWorkspace,
      if (s.has(HubFeature.appointments)) appointmentsWorkspace,
      if (s.has(HubFeature.projects) || s.has(HubFeature.construction))
        projectsWorkspace(s),
      purchasingWorkspace(s),
      if (s.has(HubFeature.stock)) inventoryWorkspace(s),
      if (s.has(HubFeature.manufacturing)) manufacturingWorkspace,
      if (s.has(HubFeature.deliveries)) deliveryWorkspace,
      financeWorkspace(s),
      if (s.teamConnected) approvalsWorkspace,
      reportsWorkspace(s),
      setupWorkspace(s),
    ];

/// Which requirement gates each workspace id — for deep links to a workspace
/// that is currently hidden. Unlisted workspaces are essential.
const hubWorkspaceRequirements = <String, Requirement>{
  'field_service': NeedsFeature(HubFeature.fieldService),
  'appointments': NeedsFeature(HubFeature.appointments),
  'projects': NeedsAnyFeature([HubFeature.projects, HubFeature.construction]),
  'inventory': NeedsFeature(HubFeature.stock),
  'manufacturing': NeedsFeature(HubFeature.manufacturing),
  'delivery': NeedsFeature(HubFeature.deliveries),
  'approvals': NeedsTeam(),
};

void registerHubWorkspaces(WorkspaceRegistry registry, HubSurface s) {
  registry.replaceWorkspaces(hubWorkspaces(s));
}
