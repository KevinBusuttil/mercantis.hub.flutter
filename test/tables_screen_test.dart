import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_hub_app/screens/tables_screen.dart';

/// V2-2: the floor map renders free/occupied tables with running totals,
/// bar tabs as chips, and an occupied table opens its tab sheet.
void main() {
  Document tab(String id, {String? table, num covers = 2}) => Document(
        id: id,
        docType: 'POS Tab',
        payload: {
          if (table != null) 'table': table,
          'status': 'Open',
          'covers': covers,
          'server': 'Anna',
        },
        children: {
          'items': [
            ChildRow(
              id: 'r1', parentId: id, parentDocType: 'POS Tab',
              tableName: 'items', rowIndex: 0,
              payload: {
                'item': 'BURGER',
                'qty': 1,
                'rate': 12,
                'modifiers': '+cheese',
                'modifier_amount': 0.5,
              },
            ),
            ChildRow(
              id: 'r2', parentId: id, parentDocType: 'POS Tab',
              tableName: 'items', rowIndex: 1,
              payload: {'item': 'COLA', 'qty': 2, 'rate': 2.5},
            ),
          ],
        },
      );

  TablesData data() => TablesData(
        tables: [
          Document(id: 'T1', docType: 'POS Table', payload: {
            'table_name': 'Table 1', 'area': 'Terrace', 'seats': 4,
          }),
          Document(id: 'T2', docType: 'POS Table', payload: {
            'table_name': 'Table 2', 'area': 'Terrace', 'seats': 2,
          }),
        ],
        openTabsByTable: {'T1': tab('TAB-2026-0001', table: 'T1')},
        barTabs: [tab('TAB-2026-0002')],
        items: const [],
        profile: null,
        sessionId: null,
      );

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        tablesDataProvider.overrideWith((ref) async => data()),
      ],
      child: const MaterialApp(home: TablesScreen()),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('floor map: occupied table shows the running total, '
      'free table shows Free, bar tabs are chips', (tester) async {
    await pump(tester);

    expect(find.text('Terrace'), findsOneWidget); // area header
    expect(find.text('Table 1'), findsOneWidget);
    expect(find.text('2 covers'), findsOneWidget);
    // 1 × (12 + 0.50) + 2 × 2.50 = 17.50 on the occupied card.
    expect(find.text('17.50'), findsOneWidget);
    expect(find.text('Table 2'), findsOneWidget);
    expect(find.text('Free'), findsOneWidget);

    expect(find.text('Bar tabs'), findsOneWidget);
    expect(find.text('TAB-2026-0002'), findsOneWidget);
    expect(find.text('Open bar tab'), findsOneWidget);
  });

  testWidgets('tapping an occupied table opens the tab sheet',
      (tester) async {
    await pump(tester);
    await tester.tap(find.text('Table 1'));
    await tester.pumpAndSettle();

    expect(find.textContaining('TAB-2026-0001'), findsOneWidget);
    expect(find.text('1 × BURGER (+cheese)  12.50'), findsOneWidget);
    expect(find.text('2 × COLA  5.00'), findsOneWidget);
    expect(find.text('Total (ex VAT): 17.50'), findsOneWidget);
    expect(find.text('Add items'), findsOneWidget);
    expect(find.text('Settle'), findsOneWidget);
    expect(find.text('Split'), findsOneWidget);
    expect(find.text('Merge'), findsOneWidget);
    expect(find.text('Void'), findsOneWidget);
  });

  testWidgets('tapping a free table asks to open a tab', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Table 2'));
    await tester.pumpAndSettle();

    expect(find.text('Open Table 2'), findsOneWidget);
    expect(find.text('Open tab'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });
}
