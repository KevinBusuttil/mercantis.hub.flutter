import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_hub_app/screens/rentals_screen.dart';

/// V3-2: the hire desk shows the fleet's out/free state and each open
/// agreement's next action.
void main() {
  RentalDeskData data() => RentalDeskData(
        units: [
          Document(id: 'UNIT-1', docType: 'Rental Unit', payload: {
            'unit_name': 'Mini digger #1',
          }),
          Document(id: 'UNIT-2', docType: 'Rental Unit', payload: {
            'unit_name': 'Mini digger #2',
          }),
        ],
        customers: [
          Document(id: 'CUST-1', docType: 'Customer', payload: {
            'customer_name': 'Vella Builders',
          }),
        ],
        openAgreements: [
          Document(id: 'RENT-2026-0001', docType: 'Rental Agreement',
              payload: {
                'unit': 'UNIT-1',
                'customer': 'CUST-1',
                'status': 'Out',
                'starts_at': '2026-08-01T09:00:00',
                'ends_at': '2026-08-04T09:00:00',
              }),
          Document(id: 'RENT-2026-0002', docType: 'Rental Agreement',
              payload: {
                'unit': 'UNIT-2',
                'customer': 'CUST-1',
                'status': 'Draft',
                'starts_at': '2026-08-10T09:00:00',
                'ends_at': '2026-08-12T09:00:00',
              }),
        ],
      );

  testWidgets('fleet state and agreement actions render', (tester) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        rentalDeskProvider.overrideWith((ref) async => data()),
      ],
      child: const MaterialApp(home: RentalsScreen()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('New hire'), findsOneWidget);

    // The fleet: #1 is out with the customer named, #2 is free.
    expect(find.text('Mini digger #1'), findsOneWidget);
    expect(find.text('Out — Vella Builders'), findsOneWidget);
    expect(find.text('Free'), findsOneWidget);

    // Open hires: the Out one offers Return, the Draft offers
    // Hand over / Cancel.
    expect(
        find.text('RENT-2026-0001 · Mini digger #1 · Vella Builders'),
        findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Return'), findsOneWidget);
    expect(find.text('Hand over'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Cancel'), findsOneWidget);
  });
}
