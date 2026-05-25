import 'package:mercantis_core_ui/mercantis_core_ui.dart';
import 'approvals_workspace.dart';
import 'delivery_workspace.dart';
import 'finance_workspace.dart';
import 'home_workspace.dart';
import 'inventory_workspace.dart';
import 'purchasing_workspace.dart';
import 'reports_workspace.dart';
import 'sales_fulfilment_workspace.dart';
import 'setup_workspace.dart';

const hubWorkspaces = <WorkspaceDescriptor>[
  homeWorkspace,
  salesFulfilmentWorkspace,
  purchasingWorkspace,
  inventoryWorkspace,
  deliveryWorkspace,
  financeWorkspace,
  approvalsWorkspace,
  reportsWorkspace,
  setupWorkspace,
];

void registerHubWorkspaces(WorkspaceRegistry registry) {
  registry.registerAll(hubWorkspaces);
}
