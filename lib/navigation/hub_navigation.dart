import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';
import '../dashboards/hub_dashboard_cards.dart';
import '../modules/accounting/hub_account_actions.dart';
import '../modules/accounting/hub_history_actions.dart';
import '../modules/channels/hub_channel_actions.dart';
import '../team/hub_portal_actions.dart';
import '../modules/projects/hub_project_actions.dart';
import '../modules/accounting/hub_compliance_actions.dart';
import '../modules/selling/hub_conversion_actions.dart';
import '../modules/selling/hub_quotation_actions.dart';
import '../modules/selling/hub_reminder_actions.dart';
import '../modules/selling/hub_lineage_actions.dart';
import '../printing/hub_print_actions.dart';
import '../screens/account_ledger_screen.dart';
import '../screens/accountant_export_screen.dart';
import '../screens/dashboards_screen.dart';
import '../screens/approvals_inbox_screen.dart';
import '../screens/audit_trail_screen.dart';
import '../screens/bank_reconcile_screen.dart';
import '../screens/assets_screen.dart';
import '../screens/booking_screen.dart';
import '../screens/commissions_screen.dart';
import '../screens/customer_account_screen.dart';
import '../screens/customer_statement_screen.dart';
import '../screens/delivery_route_screen.dart';
import '../screens/driver_today_screen.dart';
import '../screens/guided_payment_screen.dart';
import '../screens/captures_screen.dart';
import '../screens/capture_ai_settings_screen.dart';
import '../screens/capture_review_screen.dart';
import '../screens/company_sync_screen.dart';
import '../screens/low_stock_screen.dart';
import '../screens/notifications_screen.dart';
import '../screens/scan_receipt_screen.dart';
import '../screens/numbering_series_screen.dart';
import '../screens/opening_balances_screen.dart';
import '../screens/pos_till_screen.dart';
import '../screens/report_builder_screen.dart';
import '../screens/reports_screen.dart';
import '../screens/sales_orders_screen.dart';
import '../screens/hospitality_audit_screen.dart';
import '../screens/kitchen_screen.dart';
import '../screens/stock_count_screen.dart';
import '../screens/tables_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/setup_packs_screen.dart';
import '../screens/conflicts_screen.dart';
import '../screens/dispatch_screen.dart';
import '../screens/equipment_screen.dart';
import '../screens/field_service_kpis_screen.dart';
import '../screens/schedule_screen.dart';
import '../screens/tech_today_screen.dart';
import '../screens/team_screen.dart';
import '../screens/setup_checklist_screen.dart';
import '../screens/work_order_complete_screen.dart';
import '../settings/hub_settings.dart';
import '../workspaces/hub_workspaces.dart';

/// Serves the approval inbox by scanning every submittable DocType for
/// documents in docStatus=0 (drafts awaiting submission/approval).
final metadataApprovalInboxSourceOverride =
    approvalInboxSourceProvider.overrideWith(
  (ref) => MetadataApprovalInboxSource(
    ref,
    userRoles: ref.watch(currentUserProvider).roles,
  ),
);

/// Called once on boot to register workspaces, custom routes, and card
/// builders.
void wireHubNavigation(WidgetRef ref) {
  final registry = ref.read(workspaceRegistryProvider);
  if (registry.all.isEmpty) {
    final settings = ref.read(hubSettingsProvider);

    // One-click document conversion (H3): Quotation→Sales Order→Delivery/Invoice,
    // PO→Receipt/Invoice, Lead→Customer/Quotation, surfaced on the document's
    // command bar.
    registerHubConversionActions(ref);
    // Quotation lifecycle (Phase 1A): Mark as Sent / Accepted / Rejected.
    registerHubQuotationActions(ref);
    // Overdue-invoice reminder (Phase 1A): copy a ready-to-send message.
    registerHubReminderActions(ref);
    // Compliance (HU1): a "Prepare return" action on a Tax Filing.
    registerHubComplianceActions(ref);
    // Conversion lineage (HU4): a "Related" action listing up/downstream docs.
    registerHubLineageActions(ref);
    // Printing (HU2): a "Print preview" action rendering the default format.
    registerHubPrintActions(ref);
    // Accounting: a "Ledger" action on an Account, opening its ledger.
    registerHubAccountActions(ref);
    // Phase 8: a "History" action on every saved record (audit trail).
    registerHubHistoryActions(ref);
    // Phase 6: Quotation -> Project and Bill-project actions.
    registerHubProjectActions(ref);
    // Phase 5: CSV order import + posting on Sales Channel / Channel Order.
    registerHubChannelActions(ref);
    // Team: customer portal links minted from the Customer record.
    registerHubPortalActions(ref);
    // Workspace visibility follows the business preset / Settings toggles
    // (applies on next launch, mirroring the Swift visibility model).
    registerHubWorkspaces(registry, settings);

    // Workspace-level custom routes — addressed as /w/<workspaceId>/<name>.
    registry.registerRoute('inbox', (c, s) => const ApprovalsInboxScreen());
    registry.registerRoute('low-stock', (c, s) => const LowStockScreen());
    registry.registerRoute('driver-today',
        (c, s) => const DriverTodayScreen());
    registry.registerRoute('route', (c, s) => const DeliveryRouteScreen());
    registry.registerRoute('customer-account',
        (c, s) => const CustomerAccountScreen());
    registry.registerRoute(
        'customer-statement',
        (c, s) => CustomerStatementScreen(
            customerId: s.uri.queryParameters['customer'] ?? ''));
    registry.registerRoute('account-ledger',
        (c, s) => AccountLedgerScreen(
            accountId: s.uri.queryParameters['account']));
    registry.registerRoute('sales-orders',
        (c, s) => const SalesOrdersScreen());
    registry.registerRoute('reports', (c, s) => const ReportsScreen());
    registry.registerRoute('schedule', (c, s) => const ScheduleScreen());
    registry.registerRoute('booking', (c, s) => const BookingScreen());
    registry.registerRoute(
        'commissions', (c, s) => const CommissionsScreen());
    registry.registerRoute('assets', (c, s) => const AssetsScreen());
    registry.registerRoute('dispatch', (c, s) => const DispatchScreen());
    registry.registerRoute('tech-today', (c, s) => const TechTodayScreen());
    registry.registerRoute('equipment', (c, s) => const EquipmentScreen());
    registry.registerRoute(
        'field-service-kpis', (c, s) => const FieldServiceKpisScreen());
    registry.registerRoute(
        'accountant-export', (c, s) => const AccountantExportScreen());
    registry.registerRoute(
        'report-builder', (c, s) => const ReportBuilderScreen());
    registry.registerRoute('dashboards', (c, s) => const DashboardsScreen());
    registry.registerRoute(
        'receive-payment', (c, s) => const GuidedPaymentScreen(receive: true));
    registry.registerRoute(
        'pay-supplier', (c, s) => const GuidedPaymentScreen(receive: false));
    registry.registerRoute('pos-till', (c, s) => const PosTillScreen());
    registry.registerRoute('tables', (c, s) => const TablesScreen());
    registry.registerRoute('kitchen', (c, s) => const KitchenScreen());
    registry.registerRoute(
        'hospitality-audit', (c, s) => const HospitalityAuditScreen());
    registry.registerRoute(
        'work-order-complete', (c, s) => const WorkOrderCompleteScreen());
    registry.registerRoute('settings', (c, s) => const SettingsScreen());
    registry.registerRoute('team', (c, s) => const TeamScreen());
    registry.registerRoute(
        'sync-conflicts', (c, s) => const ConflictsScreen());
    registry.registerRoute('setup-packs', (c, s) => const SetupPacksScreen());
    registry.registerRoute(
        'setup-checklist', (c, s) => const SetupChecklistScreen());
    registry.registerRoute(
        'opening-balances', (c, s) => const OpeningBalancesScreen());
    registry.registerRoute(
        'stock-count', (c, s) => const StockCountScreen());
    registry.registerRoute(
        'bank-reconcile', (c, s) => const BankReconcileScreen());
    registry.registerRoute(
        'audit-trail',
        (c, s) => AuditTrailScreen(
            docType: s.uri.queryParameters['docType'],
            documentId: s.uri.queryParameters['id']));
    // In-app notification inbox (ADR-048) and recently-opened records — shared
    // core-ui views surfaced from the Home workspace's quick actions.
    registry.registerRoute('notifications', (c, s) => const NotificationsScreen());
    registry.registerRoute('recents', (c, s) => const RecentsView());
    registry.registerRoute(
        'numbering-series', (c, s) => const NumberingSeriesScreen());
    registry.registerRoute(
        'company-sync', (c, s) => const CompanySyncScreen());
    // Document Capture (ADR-049).
    registry.registerRoute('captures', (c, s) => const CapturesScreen());
    registry.registerRoute(
        'capture-ai-settings', (c, s) => const CaptureAiSettingsScreen());
    registry.registerRoute('scan-receipt', (c, s) => const ScanReceiptScreen());
    registry.registerRoute(
        'capture-review',
        (c, s) => CaptureReviewScreen(
            captureId: s.uri.queryParameters['id'] ?? ''));
  }

  registerHubDashboardCards(ref);
}
