import 'package:mercantis_core/mercantis_core.dart';

import '../ledger/ledger_values.dart';

const _systemRoles = {'System Manager'};

/// One technician's line in the KPI table.
class TechnicianKpi {
  const TechnicianKpi({
    required this.technician,
    required this.jobsCompleted,
    required this.revenue,
  });

  final String technician;
  final int jobsCompleted;
  final num revenue;
}

/// The field-service numbers that tell an owner how the operation is doing
/// (V1-6). Everything is computed from the documents — nothing stored, so
/// the report can never disagree with the records.
class FieldServiceKpis {
  const FieldServiceKpis({
    required this.from,
    required this.to,
    required this.jobsCompleted,
    required this.jobsCancelled,
    required this.revenue,
    required this.unbilledCompleted,
    required this.openRequests,
    required this.oldestOpenRequestDays,
    required this.avgRequestToVisitDays,
    required this.activeContracts,
    required this.overdueContracts,
    required this.perTechnician,
  });

  final String from;
  final String to;

  /// Jobs completed with their visit date inside the window.
  final int jobsCompleted;
  final int jobsCancelled;

  /// Grand totals of the invoices those completed jobs raised.
  final num revenue;

  /// Completed jobs with no invoice — money left on the table.
  final int unbilledCompleted;

  final int openRequests;
  final int oldestOpenRequestDays;

  /// Mean days from the request being logged to the job's visit start.
  /// -1 when no completed job traces back to a request in the window.
  final num avgRequestToVisitDays;

  final int activeContracts;

  /// Active contracts whose next job date is already in the past.
  final int overdueContracts;

  final List<TechnicianKpi> perTechnician;
}

/// Pure aggregation, unit-testable without an engine. [asOf] is "today"
/// for request ages and contract overdue-ness; the window [from, to] is
/// inclusive on both ends and matched against each job's `starts_at` date
/// (unscheduled completed jobs count via their `modified` day fallback —
/// they still happened).
FieldServiceKpis computeFieldServiceKpis({
  required List<Document> jobs,
  required List<Document> requests,
  required List<Document> contracts,
  required Map<String, Document> invoicesById,
  required String from,
  required String to,
  required String asOf,
}) {
  String? jobDay(Document j) {
    final starts = asNonEmpty(j.payload['starts_at']);
    if (starts != null) return starts.split('T').first;
    final modified = j.modifiedAt ?? j.createdAt;
    return modified.toIso8601String().split('T').first;
  }

  bool inWindow(String? day) =>
      day != null && day.compareTo(from) >= 0 && day.compareTo(to) <= 0;

  var completed = 0;
  var cancelled = 0;
  num revenue = 0;
  var unbilled = 0;
  final requestGapsDays = <num>[];
  final byTech = <String, ({int jobs, num revenue})>{};
  final requestById = {for (final r in requests) r.id: r};

  for (final j in jobs) {
    if (!inWindow(jobDay(j))) continue;
    final status = '${j.payload['status']}';
    if (status == 'Cancelled') {
      cancelled++;
      continue;
    }
    if (status != 'Completed') continue;
    completed++;

    num jobRevenue = 0;
    final invoiceId = asNonEmpty(j.payload['sales_invoice']);
    final invoice = invoiceId == null ? null : invoicesById[invoiceId];
    if (invoice == null) {
      unbilled++;
    } else {
      jobRevenue = asNum(invoice.payload['grand_total']);
      revenue += jobRevenue;
    }

    final tech = asNonEmpty(j.payload['technician']) ?? '(unassigned)';
    final prior = byTech[tech] ?? (jobs: 0, revenue: 0);
    byTech[tech] = (jobs: prior.jobs + 1, revenue: prior.revenue + jobRevenue);

    final requestId = asNonEmpty(j.payload['service_request']);
    final request = requestId == null ? null : requestById[requestId];
    final visit = asNonEmpty(j.payload['starts_at']);
    if (request != null && visit != null) {
      final gap =
          DateTime.parse(visit).difference(request.createdAt).inHours / 24.0;
      if (gap >= 0) requestGapsDays.add(gap);
    }
  }

  var openRequests = 0;
  var oldestOpenDays = 0;
  final today = DateTime.parse(asOf);
  for (final r in requests) {
    if ('${r.payload['status']}' != 'Open') continue;
    openRequests++;
    final age = today.difference(r.createdAt).inDays;
    if (age > oldestOpenDays) oldestOpenDays = age;
  }

  var activeContracts = 0;
  var overdueContracts = 0;
  for (final c in contracts) {
    if (!isTrue(c.payload['active'])) continue;
    activeContracts++;
    final next = asNonEmpty(c.payload['next_job_date']);
    if (next != null && next.compareTo(asOf) < 0) overdueContracts++;
  }

  final perTech = [
    for (final e in byTech.entries)
      TechnicianKpi(
        technician: e.key,
        jobsCompleted: e.value.jobs,
        revenue: e.value.revenue,
      ),
  ]..sort((a, b) => b.revenue.compareTo(a.revenue));

  return FieldServiceKpis(
    from: from,
    to: to,
    jobsCompleted: completed,
    jobsCancelled: cancelled,
    revenue: revenue,
    unbilledCompleted: unbilled,
    openRequests: openRequests,
    oldestOpenRequestDays: oldestOpenDays,
    avgRequestToVisitDays: requestGapsDays.isEmpty
        ? -1
        : requestGapsDays.reduce((a, b) => a + b) / requestGapsDays.length,
    activeContracts: activeContracts,
    overdueContracts: overdueContracts,
    perTechnician: perTech,
  );
}

/// Loads everything and aggregates for the last [windowDays] days.
Future<FieldServiceKpis> loadFieldServiceKpis(
  DocumentEngine engine, {
  int windowDays = 30,
}) async {
  final now = DateTime.now();
  final to = now.toIso8601String().split('T').first;
  final from = now
      .subtract(Duration(days: windowDays - 1))
      .toIso8601String()
      .split('T')
      .first;
  final jobs = await engine.list('Job', userRoles: _systemRoles);
  final requests =
      await engine.list('Service Request', userRoles: _systemRoles);
  final contracts =
      await engine.list('Maintenance Contract', userRoles: _systemRoles);
  final invoices =
      await engine.list('Sales Invoice', userRoles: _systemRoles);
  return computeFieldServiceKpis(
    jobs: jobs,
    requests: requests,
    contracts: contracts,
    invoicesById: {for (final i in invoices) i.id: i},
    from: from,
    to: to,
    asOf: to,
  );
}
