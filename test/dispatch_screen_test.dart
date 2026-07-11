import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_hub_app/screens/dispatch_screen.dart';

/// V1-3: the dispatch board renders its three zones — the request queue,
/// jobs waiting for a slot, and the technicians' day lanes with job blocks.
void main() {
  final today = DateTime.now();
  final todayIso = today.toIso8601String().split('T').first;

  DispatchData data() => DispatchData(
        openRequests: [
          Document(id: 'SRQ-1', docType: 'Service Request', payload: {
            'subject': 'Boiler dead',
            'customer': 'CUST-1',
            'priority': 'Urgent',
            'status': 'Open',
          }),
        ],
        unscheduledJobs: [
          Document(id: 'JOB-7', docType: 'Job', payload: {
            'subject': 'Repipe bathroom',
            'customer': 'CUST-2',
            'status': 'Draft',
          }),
        ],
        technicians: [
          Document(id: 'TECH-M', docType: 'Schedulable Resource', payload: {
            'resource_name': 'Maria',
            'resource_type': 'Person',
          }),
        ],
        appointments: [
          Document(id: 'APT-1', docType: 'Appointment', payload: {
            'subject': 'JOB-3: Fix leak',
            'resource': 'TECH-M',
            'customer': 'CUST-3',
            'status': 'Scheduled',
            'starts_at': '${todayIso}T09:00:00',
            'ends_at': '${todayIso}T11:00:00',
          }),
        ],
        jobsByAppointment: {
          'APT-1': Document(id: 'JOB-3', docType: 'Job', payload: {
            'subject': 'Fix leak',
            'customer': 'CUST-3',
            'status': 'Scheduled',
            'appointment': 'APT-1',
          }),
        },
      );

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        dispatchDataProvider.overrideWith((ref) async => data()),
      ],
      child: const MaterialApp(home: DispatchScreen()),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('renders queue, waiting jobs, and the day board',
      (tester) async {
    await pump(tester);
    expect(find.textContaining('REQUESTS WAITING (1)'), findsOneWidget);
    expect(find.text('Boiler dead'), findsOneWidget);
    expect(find.text('Make job'), findsOneWidget);

    expect(find.textContaining('WAITING FOR A SLOT (1)'), findsOneWidget);
    expect(find.text('JOB-7 — Repipe bathroom'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Dispatch'), findsOneWidget);

    expect(find.text('Maria'), findsOneWidget); // lane header
    expect(find.text('JOB-3: Fix leak'), findsOneWidget); // booked block
  });

  testWidgets('tapping a job block opens the job sheet', (tester) async {
    await pump(tester);
    await tester.tap(find.text('JOB-3: Fix leak'));
    await tester.pumpAndSettle();
    expect(find.text('Start work'), findsOneWidget);
    expect(find.text('Complete & invoice'), findsOneWidget);
  });
}
