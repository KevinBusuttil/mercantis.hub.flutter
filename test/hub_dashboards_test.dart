import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_hub_app/manifest/hub_dashboards.dart';
import 'package:mercantis_hub_app/manifest/hub_reports.dart';

/// A lister that returns the same fixed documents for any docType — enough to
/// exercise the dashboard widgets' wiring without a database.
DocumentListFn _lister(List<Document> docs) => (
      String docType, {
      Map<String, dynamic>? filters,
      String? whereExpression,
      List<({String field, bool ascending})>? sortBy,
      int? limit,
      int? offset,
      Set<String>? userRoles,
    }) async =>
        docs;

void main() {
  test('catalogue exposes 5 unique dashboards, each with widgets', () {
    final all = HubDashboards.all();
    expect(all.length, 5);
    expect(all.map((d) => d.id).toSet().length, 5);
    for (final d in all) {
      expect(d.widgets, isNotEmpty, reason: '${d.id} has no widgets');
    }
  });

  test('finance dashboard computes its sum/count/chart tiles on real data',
      () async {
    final docs = [
      Document(id: 'A', docType: 'Sales Invoice', payload: {'outstanding_amount': 100}),
      Document(id: 'B', docType: 'Sales Invoice', payload: {'outstanding_amount': 250}),
    ];
    final list = _lister(docs);
    final reportEngine = ReportEngine(list)..registerAll(HubReports.all());
    final engine = DashboardEngine(list, reportEngine)
      ..registerAll(HubDashboards.all());

    final result = await engine.resolve('finance');
    final byId = {for (final w in result.widgets) w.id: w};

    expect(byId['fin_receivables']!.total, 350);
    expect(byId['fin_receivables']!.display, '350.00');
    expect(byId['fin_payments']!.count, 2);
    expect(byId['fin_gl']!.isError, isFalse); // chart resolved against a real report
  });
}
