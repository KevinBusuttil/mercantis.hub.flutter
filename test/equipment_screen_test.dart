import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_hub_app/screens/equipment_screen.dart';

/// V4: the equipment register lists units with owner and visit count;
/// tapping one opens its service history with "Book it in".
void main() {
  EquipmentData data() => EquipmentData(
        equipment: [
          Document(id: 'CAR-1', docType: 'Customer Equipment', payload: {
            'equipment_name': 'Toyota Yaris',
            'customer': 'CUST-1',
            'registration_no': 'ABC-123',
            'make': 'Toyota',
            'model': 'Yaris',
          }),
        ],
        customerNames: const {'CUST-1': 'Borg'},
        historyByEquipment: {
          'CAR-1': [
            Document(id: 'JOB-9', docType: 'Job', payload: {
              'subject': 'Brakes',
              'status': 'Completed',
              'starts_at': '2026-02-10T09:00:00',
              'sales_invoice': 'SINV-0042',
            }),
          ],
        },
      );

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        equipmentDataProvider.overrideWith((ref) async => data()),
      ],
      child: const MaterialApp(home: EquipmentScreen()),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('units list with owner and visit count', (tester) async {
    await pump(tester);
    expect(find.text('Toyota Yaris · ABC-123'), findsOneWidget);
    expect(find.text('Borg · 1 visit(s)'), findsOneWidget);
  });

  testWidgets('tapping a unit opens its history with Book it in',
      (tester) async {
    await pump(tester);
    await tester.tap(find.text('Toyota Yaris · ABC-123'));
    await tester.pumpAndSettle();

    expect(find.text('Toyota · Yaris · ABC-123'), findsOneWidget);
    expect(
        find.text('2026-02-10  JOB-9 — Brakes (Completed · SINV-0042)'),
        findsOneWidget);
    expect(find.text('Book it in'), findsOneWidget);
  });
}
