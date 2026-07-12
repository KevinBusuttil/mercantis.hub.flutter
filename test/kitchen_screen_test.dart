import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_hub_app/screens/kitchen_screen.dart';

/// V2-3: the kitchen display renders each open round as a card — where
/// it's for, how long it's waited, the lines at cooking size — and an
/// empty rail says so.
void main() {
  Document ticket(String id, {String? table, int minutesAgo = 5}) =>
      Document(
        id: id,
        docType: 'Kitchen Ticket',
        payload: {
          'tab': 'TAB-2026-0001',
          if (table != null) 'table': table,
          'status': 'Open',
          'sent_at': DateTime.now()
              .subtract(Duration(minutes: minutesAgo))
              .toIso8601String(),
          'server': 'Anna',
        },
        children: {
          'items': [
            ChildRow(
              id: 'r1', parentId: id, parentDocType: 'Kitchen Ticket',
              tableName: 'items', rowIndex: 0,
              payload: {
                'item': 'BURGER',
                'qty': 1,
                'modifiers': 'well done',
                'notes': 'no bun',
              },
            ),
          ],
        },
      );

  Future<void> pump(WidgetTester tester, KitchenData data) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        kitchenDataProvider.overrideWith((ref) async => data),
      ],
      child: const MaterialApp(home: KitchenScreen()),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('open tickets render as cards with wait time and lines',
      (tester) async {
    await pump(
      tester,
      KitchenData(
        tickets: [
          ticket('KOT-2026-0001', table: 'T1', minutesAgo: 15),
          ticket('KOT-2026-0002'), // bar round
        ],
        tableNames: const {'T1': 'Table 1'},
      ),
    );

    expect(find.text('Table 1 · KOT-2026-0001'), findsOneWidget);
    expect(find.text('Bar · KOT-2026-0002'), findsOneWidget);
    expect(find.text('15 min'), findsOneWidget);
    expect(find.text('1 × BURGER'), findsNWidgets(2));
    expect(find.text('well done'), findsNWidgets(2));
    expect(find.text('“no bun”'), findsNWidgets(2));
    expect(find.widgetWithText(FilledButton, 'Done'), findsNWidgets(2));
  });

  testWidgets('an empty rail says so', (tester) async {
    await pump(tester,
        const KitchenData(tickets: [], tableNames: {}));
    expect(find.text('Rail is clear'), findsOneWidget);
  });
}
