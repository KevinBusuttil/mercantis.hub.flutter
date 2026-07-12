import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_hub_app/property/lease_service.dart';
import 'package:mercantis_hub_app/screens/rent_roll_screen.dart';

/// V5: the rent roll shows active tenancies with arrears (worst first)
/// and Draft leases waiting for activation.
void main() {
  RentRollData data() => RentRollData(
        lines: [
          RentRollLine(
            lease: Document(id: 'LSE-2026-0001', docType: 'Lease',
                payload: {'status': 'Active'}),
            propertyName: 'Sliema Apt 4',
            tenant: 'TEN-1',
            rent: 800,
            frequency: 'Monthly',
            nextInvoiceDate: '2026-09-01',
            arrears: 1600,
          ),
        ],
        drafts: [
          Document(id: 'LSE-2026-0002', docType: 'Lease', payload: {
            'status': 'Draft',
            'property': 'PROP-B',
            'tenant': 'TEN-2',
          }),
        ],
      );

  testWidgets('roll rows, arrears and pending activations render',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        rentRollProvider.overrideWith((ref) async => data()),
      ],
      child: const MaterialApp(home: RentRollScreen()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Waiting to start'), findsOneWidget);
    expect(find.text('LSE-2026-0002 · PROP-B · TEN-2'), findsOneWidget);
    expect(find.text('Activate'), findsOneWidget);

    expect(find.text('Sliema Apt 4 · TEN-1 · LSE-2026-0001'),
        findsOneWidget);
    expect(find.text('800.00 monthly · next 2026-09-01'), findsOneWidget);
    expect(find.text('1600.00'), findsOneWidget);
    expect(find.text('End lease'), findsOneWidget);
  });

  testWidgets('a clean book shows the empty state', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        rentRollProvider.overrideWith(
            (ref) async => const RentRollData(lines: [], drafts: [])),
      ],
      child: const MaterialApp(home: RentRollScreen()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('No active leases'), findsOneWidget);
  });
}
