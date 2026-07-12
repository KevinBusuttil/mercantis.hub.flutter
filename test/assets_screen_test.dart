import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_hub_app/screens/assets_screen.dart';

/// S10: the register shows gross / depreciated / book value per asset
/// and offers the depreciation run only when periods are due.
void main() {
  Document van() => Document(
        id: 'AST-2026-0001',
        docType: 'Asset',
        payload: {
          'asset_name': 'Delivery van',
          'status': 'In Use',
          'purchase_date': '2026-01-15',
          'gross_purchase_amount': 1200,
        },
        children: {
          'schedule': [
            ChildRow(
              id: 'r1', parentId: 'AST-2026-0001', parentDocType: 'Asset',
              tableName: 'schedule', rowIndex: 0,
              payload: {
                'period_date': '2026-02-15',
                'amount': 100,
                'posted': 1,
                'journal_entry': 'JV-.2026.-0001',
              },
            ),
            ChildRow(
              id: 'r2', parentId: 'AST-2026-0001', parentDocType: 'Asset',
              tableName: 'schedule', rowIndex: 1,
              payload: {'period_date': '2026-03-15', 'amount': 100},
            ),
          ],
        },
      );

  Future<void> pump(WidgetTester tester, AssetsData data) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        assetsDataProvider.overrideWith((ref) async => data),
      ],
      child: const MaterialApp(home: AssetsScreen()),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('register rows show book value; due periods enable the run',
      (tester) async {
    await pump(tester, AssetsData(assets: [van()], dueCount: 1));
    expect(find.text('Delivery van · AST-2026-0001'), findsOneWidget);
    expect(find.textContaining('gross 1200.00'), findsOneWidget);
    expect(find.textContaining('depreciated 100.00'), findsOneWidget);
    expect(find.text('1100.00'), findsOneWidget); // NBV
    expect(
        find.text('Post due depreciation (1)'), findsOneWidget);
  });

  testWidgets('nothing due disables the run', (tester) async {
    await pump(tester, AssetsData(assets: [van()], dueCount: 0));
    expect(find.text('Depreciation up to date'), findsOneWidget);
    final button = tester
        .widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);
  });
}
