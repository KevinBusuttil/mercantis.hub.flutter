import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

import '../manifest/hub_dashboards.dart';
import '../manifest/hub_reports.dart';
import 'aggregating_reports.dart';

/// The Hub's [ReportEngine], reading the real document store via
/// `DocumentEngine.list` and pre-loaded with the [HubReports] catalogue.
final reportEngineProvider = FutureProvider<ReportEngine>((ref) async {
  final engine = await ref.watch(documentEngineProvider.future);
  final reportEngine = ReportEngine(engine.list)..registerAll(HubReports.all());
  return reportEngine;
});

/// Runs a single report by id for the current user's roles.
final reportResultProvider =
    FutureProvider.family<ReportResult, String>((ref, reportId) async {
  final engine = await ref.watch(reportEngineProvider.future);
  final roles = ref.watch(currentUserProvider).roles;
  return engine.execute(reportId, userRoles: roles);
});

/// App-side aggregating reports (Trial Balance, AR/AP aging), reading the real
/// document store. Separate from [reportEngineProvider] because these group/sum
/// rather than flat-project.
final aggregatingReportsProvider = FutureProvider<HubAggregatingReports>((ref) async {
  final engine = await ref.watch(documentEngineProvider.future);
  return HubAggregatingReports(engine.list, fetch: engine.fetch);
});

/// Trial Balance for the current user's roles.
final trialBalanceProvider = FutureProvider<ReportResult>((ref) async {
  final reports = await ref.watch(aggregatingReportsProvider.future);
  final roles = ref.watch(currentUserProvider).roles;
  return reports.trialBalance(userRoles: roles);
});

/// Accounts-receivable aging as of today, for the current user's roles.
final arAgingProvider = FutureProvider<ReportResult>((ref) async {
  final reports = await ref.watch(aggregatingReportsProvider.future);
  final roles = ref.watch(currentUserProvider).roles;
  return reports.arAging(userRoles: roles);
});

/// Accounts-payable aging as of today, for the current user's roles.
final apAgingProvider = FutureProvider<ReportResult>((ref) async {
  final reports = await ref.watch(aggregatingReportsProvider.future);
  final roles = ref.watch(currentUserProvider).roles;
  return reports.apAging(userRoles: roles);
});

/// Profit & Loss from the GL's income/expense balances.
final profitAndLossProvider = FutureProvider<ReportResult>((ref) async {
  final reports = await ref.watch(aggregatingReportsProvider.future);
  final roles = ref.watch(currentUserProvider).roles;
  return reports.profitAndLoss(userRoles: roles);
});

/// Gross margin by item (revenue vs perpetual-inventory COGS).
final grossMarginProvider = FutureProvider<ReportResult>((ref) async {
  final reports = await ref.watch(aggregatingReportsProvider.future);
  final roles = ref.watch(currentUserProvider).roles;
  return reports.grossMarginByItem(userRoles: roles);
});

/// Totalled stock valuation from the Bins.
final stockValuationProvider = FutureProvider<ReportResult>((ref) async {
  final reports = await ref.watch(aggregatingReportsProvider.future);
  final roles = ref.watch(currentUserProvider).roles;
  return reports.stockValuation(userRoles: roles);
});

/// Balance Sheet from the GL's asset/liability/equity balances.
final balanceSheetProvider = FutureProvider<ReportResult>((ref) async {
  final reports = await ref.watch(aggregatingReportsProvider.future);
  final roles = ref.watch(currentUserProvider).roles;
  return reports.balanceSheet(userRoles: roles);
});

/// Cash movements on Cash/Bank accounts grouped by voucher type.
final cashFlowProvider = FutureProvider<ReportResult>((ref) async {
  final reports = await ref.watch(aggregatingReportsProvider.future);
  final roles = ref.watch(currentUserProvider).roles;
  return reports.cashFlowOverview(userRoles: roles);
});

/// Per-project invoiced vs costs, hours, and unbilled time.
final projectProfitabilityProvider = FutureProvider<ReportResult>((ref) async {
  final reports = await ref.watch(aggregatingReportsProvider.future);
  final roles = ref.watch(currentUserProvider).roles;
  return reports.projectProfitability(userRoles: roles);
});

/// Stock ledger vs GL inventory balance — the perpetual-inventory trust check.
final stockGlReconciliationProvider = FutureProvider<ReportResult>((ref) async {
  final reports = await ref.watch(aggregatingReportsProvider.future);
  final roles = ref.watch(currentUserProvider).roles;
  return reports.stockGlReconciliation(userRoles: roles);
});

/// The Hub's [DashboardEngine], sharing the report engine (for `chart` tiles)
/// and pre-loaded with the [HubDashboards] catalogue.
final dashboardEngineProvider = FutureProvider<DashboardEngine>((ref) async {
  final engine = await ref.watch(documentEngineProvider.future);
  final reportEngine = await ref.watch(reportEngineProvider.future);
  return DashboardEngine(engine.list, reportEngine)
    ..registerAll(HubDashboards.all());
});

/// Resolves one dashboard by id for the current user's roles.
final dashboardResultProvider =
    FutureProvider.family<DashboardResult, String>((ref, dashboardId) async {
  final engine = await ref.watch(dashboardEngineProvider.future);
  final roles = ref.watch(currentUserProvider).roles;
  return engine.resolve(dashboardId, userRoles: roles);
});
