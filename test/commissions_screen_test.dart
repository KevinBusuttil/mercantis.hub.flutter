import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_hub_app/booking/booking_service.dart';
import 'package:mercantis_hub_app/screens/commissions_screen.dart';

/// P4-2: the commission report renders one row per staff member with
/// the invoiced base and the earned commission.
void main() {
  Future<void> pump(WidgetTester tester, CommissionsData data) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        commissionsDataProvider.overrideWith((ref) async => data),
      ],
      child: const MaterialApp(home: CommissionsScreen()),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('rows show name, base and commission', (tester) async {
    await pump(
      tester,
      const CommissionsData(
        from: '2026-07-01',
        lines: [
          CommissionLine(
              resource: 'STY-ANNA',
              appointments: 2,
              base: 110,
              commission: 19),
        ],
        names: {'STY-ANNA': 'Anna'},
      ),
    );
    expect(find.text('Since 2026-07-01'), findsOneWidget);
    expect(find.text('Anna'), findsOneWidget);
    expect(find.text('2 completed · invoiced 110.00'), findsOneWidget);
    expect(find.text('19.00'), findsOneWidget);
  });

  testWidgets('no commission shows the empty state', (tester) async {
    await pump(tester,
        const CommissionsData(from: '2026-07-01', lines: [], names: {}));
    expect(find.text('No commission yet'), findsOneWidget);
  });
}
