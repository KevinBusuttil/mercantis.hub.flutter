import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

/// The Hub's [SavedReportEngine] (HU3), reading the real document store and
/// DocType metadata — so the visual report builder can execute grouped /
/// aggregated reports (C7) with row-level access preserved.
final savedReportEngineProvider = FutureProvider<SavedReportEngine>((ref) async {
  final engine = await ref.watch(documentEngineProvider.future);
  final registry = await ref.watch(metadataRegistryProvider.future);
  return SavedReportEngine(engine.list, registry);
});

/// Builds a one-group / one-aggregate [SavedReportDefinition] from the visual
/// builder's selections (HU3). `count` ignores [valueField]; the numeric folds
/// aggregate it. When [withChart] is set, a chart plots the aggregate over the
/// group. Pure — the heavy lifting is the C7 engine's.
SavedReportDefinition buildGroupedReport({
  required String name,
  required String sourceDocType,
  required String groupBy,
  required SavedReportAggregateFunction fn,
  String? valueField,
  required String ownerUserId,
  bool withChart = true,
  SavedReportChartType chartType = SavedReportChartType.bar,
  DateTime? now,
}) {
  final aggregate = SavedReportAggregate(
    fieldKey: fn == SavedReportAggregateFunction.count ? '' : (valueField ?? ''),
    fn: fn,
  );
  return SavedReportDefinition(
    name: name,
    sourceDocType: sourceDocType,
    ownerUserId: ownerUserId,
    groupBy: [groupBy],
    aggregates: [aggregate],
    chart: withChart
        ? SavedReportChart(
            type: chartType, categoryFieldKey: groupBy, aggregateIndex: 0)
        : null,
    createdAt: now,
    updatedAt: now,
  );
}
