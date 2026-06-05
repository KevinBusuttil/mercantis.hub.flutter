import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

import '../manifest/hub_reports.dart';

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
