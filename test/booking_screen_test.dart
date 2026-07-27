import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_hub_app/screens/booking_screen.dart';

/// P4-2: the front-desk booking screen renders the guided form and
/// today's bookings with complete-to-invoice on the open ones.
void main() {
  final today = DateTime.now().toIso8601String().split('T').first;

  BookingData data() => BookingData(
        resources: [
          Document(id: 'STY-ANNA', docType: 'Schedulable Resource',
              payload: {
                'resource_name': 'Anna', 'resource_type': 'Person',
              }),
        ],
        services: [
          Document(id: 'CUT', docType: 'Item', payload: {
            'item_code': 'CUT', 'item_name': 'Haircut',
            'item_type': 'Service',
          }),
        ],
        customers: [
          Document(id: 'CUST-1', docType: 'Customer', payload: {
            'customer_name': 'Maria',
          }),
        ],
        needReminder: const [],
        today: [
          Document(id: 'APT-1', docType: 'Appointment', payload: {
            'subject': 'Haircut',
            'resource': 'STY-ANNA',
            'customer': 'CUST-1',
            'status': 'Scheduled',
            'starts_at': '${today}T10:00:00',
            'ends_at': '${today}T11:00:00',
            'deposit': 'DEP-2026-0001',
          }),
          Document(id: 'APT-2', docType: 'Appointment', payload: {
            'subject': 'Colour',
            'resource': 'STY-ANNA',
            'status': 'Completed',
            'starts_at': '${today}T12:00:00',
            'ends_at': '${today}T13:00:00',
          }),
        ],
      );

  testWidgets('renders the booking form and today\'s list',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        bookingDataProvider.overrideWith((ref) async => data()),
      ],
      child: const MaterialApp(home: BookingScreen()),
    ));
    await tester.pumpAndSettle();

    // The guided form.
    expect(find.text('Service'), findsOneWidget);
    expect(find.text('Staff / resource'), findsOneWidget);
    expect(find.text('Customer'), findsOneWidget);
    expect(find.text('Deposit taken now (0 for none)'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Book'), findsOneWidget);

    // Today's bookings: the open one offers completion, with its
    // deposit visible; the completed one doesn't.
    expect(find.textContaining('10:00–11:00  Haircut · Anna'),
        findsOneWidget);
    expect(find.textContaining('deposit DEP-2026-0001'), findsOneWidget);
    expect(find.text('Complete & invoice'), findsOneWidget);
    expect(find.textContaining('12:00–13:00  Colour · Anna'),
        findsOneWidget);
  });
}
