import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_hub_app/field_service/field_service_kpis.dart';

/// V1-6: the KPI aggregation is pure — feed it documents, get the numbers
/// an owner asks for: work done, revenue by technician, unbilled leakage,
/// backlog age, and contract health.
void main() {
  Document job(
    String id, {
    String status = 'Completed',
    String? technician,
    String? startsAt,
    String? invoice,
    String? request,
  }) =>
      Document(id: id, docType: 'Job', payload: {
        'subject': id,
        'status': status,
        if (technician != null) 'technician': technician,
        if (startsAt != null) 'starts_at': startsAt,
        if (invoice != null) 'sales_invoice': invoice,
        if (request != null) 'service_request': request,
      });

  Document invoice(String id, num total) =>
      Document(id: id, docType: 'Sales Invoice', payload: {
        'grand_total': total,
      });

  test('completed work, revenue per technician, and unbilled leakage', () {
    final kpis = computeFieldServiceKpis(
      jobs: [
        job('J-1',
            technician: 'MARIA',
            startsAt: '2026-07-02T09:00:00',
            invoice: 'SINV-1'),
        job('J-2',
            technician: 'MARIA',
            startsAt: '2026-07-03T09:00:00',
            invoice: 'SINV-2'),
        job('J-3', technician: 'PETE', startsAt: '2026-07-04T09:00:00'),
        // outside the window — ignored
        job('J-OLD',
            technician: 'MARIA',
            startsAt: '2026-05-01T09:00:00',
            invoice: 'SINV-OLD'),
        job('J-CXL', status: 'Cancelled', startsAt: '2026-07-05T09:00:00'),
        job('J-OPEN', status: 'Scheduled', startsAt: '2026-07-06T09:00:00'),
      ],
      requests: const [],
      contracts: const [],
      invoicesById: {
        'SINV-1': invoice('SINV-1', 130),
        'SINV-2': invoice('SINV-2', 70),
        'SINV-OLD': invoice('SINV-OLD', 999),
      },
      from: '2026-07-01',
      to: '2026-07-31',
      asOf: '2026-07-31',
    );

    expect(kpis.jobsCompleted, 3);
    expect(kpis.jobsCancelled, 1);
    expect(kpis.revenue, 200); // the old invoice never counts
    expect(kpis.unbilledCompleted, 1); // Pete's uninvoiced job

    expect(kpis.perTechnician, hasLength(2));
    expect(kpis.perTechnician.first.technician, 'MARIA'); // revenue-sorted
    expect(kpis.perTechnician.first.jobsCompleted, 2);
    expect(kpis.perTechnician.first.revenue, 200);
    expect(kpis.perTechnician.last.revenue, 0);
  });

  test('backlog age, request→visit gap, and contract health', () {
    final request = Document(
      id: 'SRQ-1',
      docType: 'Service Request',
      payload: {'status': 'Converted'},
      createdAt: DateTime.parse('2026-07-01T08:00:00'),
    );
    final openOld = Document(
      id: 'SRQ-2',
      docType: 'Service Request',
      payload: {'status': 'Open'},
      createdAt: DateTime.parse('2026-07-10T08:00:00'),
    );
    Document contract(String id, {String? next, bool active = true}) =>
        Document(id: id, docType: 'Maintenance Contract', payload: {
          'active': active ? 1 : 0,
          if (next != null) 'next_job_date': next,
        });

    final kpis = computeFieldServiceKpis(
      jobs: [
        job('J-1',
            startsAt: '2026-07-03T08:00:00',
            invoice: 'SINV-1',
            request: 'SRQ-1'),
      ],
      requests: [request, openOld],
      contracts: [
        contract('MC-OK', next: '2026-08-01'),
        contract('MC-LATE', next: '2026-07-01'),
        contract('MC-OFF', next: '2020-01-01', active: false),
      ],
      invoicesById: {'SINV-1': invoice('SINV-1', 100)},
      from: '2026-07-01',
      to: '2026-07-31',
      asOf: '2026-07-20',
    );

    expect(kpis.openRequests, 1);
    expect(kpis.oldestOpenRequestDays, 9); // 10 Jul 08:00 → 20 Jul 00:00
    expect(kpis.avgRequestToVisitDays, closeTo(2, 0.01)); // 1 Jul → 3 Jul
    expect(kpis.activeContracts, 2); // the inactive one is invisible
    expect(kpis.overdueContracts, 1); // MC-LATE
  });

  test('an empty book reports zeros, not crashes', () {
    final kpis = computeFieldServiceKpis(
      jobs: const [],
      requests: const [],
      contracts: const [],
      invoicesById: const {},
      from: '2026-07-01',
      to: '2026-07-31',
      asOf: '2026-07-31',
    );
    expect(kpis.jobsCompleted, 0);
    expect(kpis.revenue, 0);
    expect(kpis.avgRequestToVisitDays, -1);
    expect(kpis.perTechnician, isEmpty);
  });
}
