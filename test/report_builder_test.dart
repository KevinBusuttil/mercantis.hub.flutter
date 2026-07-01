import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_hub_app/reports/report_builder.dart';

/// HU3 — the visual report builder's definition-building (pure).
void main() {
  test('count builds a grouped report with a chart over the group', () {
    final def = buildGroupedReport(
      name: 'Invoices by customer',
      sourceDocType: 'Sales Invoice',
      groupBy: 'customer',
      fn: SavedReportAggregateFunction.count,
      ownerUserId: 'u',
    );
    expect(def.isGrouped, isTrue);
    expect(def.groupBy, ['customer']);
    expect(def.aggregates.single.fn, SavedReportAggregateFunction.count);
    expect(def.aggregates.single.fieldKey, ''); // count ignores the value field
    expect(def.chart!.categoryFieldKey, 'customer');
    expect(def.chart!.aggregateIndex, 0);
  });

  test('a numeric fold keeps its value field; chart can be omitted', () {
    final def = buildGroupedReport(
      name: 'Sales by region',
      sourceDocType: 'Sales Invoice',
      groupBy: 'region',
      fn: SavedReportAggregateFunction.sum,
      valueField: 'grand_total',
      ownerUserId: 'u',
      withChart: false,
    );
    expect(def.aggregates.single.fieldKey, 'grand_total');
    expect(def.aggregates.single.fn, SavedReportAggregateFunction.sum);
    expect(def.chart, isNull);
  });
}
