import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_hub_app/numbering/numbering_series.dart';
import 'package:mercantis_hub_app/screens/numbering_series_screen.dart';

/// The Next # counter and the Next id sample were redundant (the sample embeds
/// the number), which cramped the table on a phone and made "Set" wrap. The
/// screen now shows just the id sample with a tap-through chevron, and hides the
/// Series column on narrow panes.
void main() {
  const rows = [
    NumberingSeriesRow(
        docType: 'Quotation',
        pattern: 'QTN-.YYYY.-.####',
        seriesKey: 'QTN-.2026.-',
        width: 4,
        nextNumber: 1),
    NumberingSeriesRow(
        docType: 'Purchase Invoice',
        pattern: 'PINV-.YYYY.-.####',
        seriesKey: 'PINV-.2026.-',
        width: 4,
        nextNumber: 1001),
  ];

  Future<void> pump(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        numberingSeriesProvider.overrideWith((ref) async => rows),
      ],
      child: const MaterialApp(home: NumberingSeriesScreen()),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('wide: Series + Next id, no redundant Next # column or Set button',
      (tester) async {
    await pump(tester, const Size(1000, 800));
    expect(tester.takeException(), isNull);
    expect(find.text('Series'), findsOneWidget); // header
    expect(find.text('Next id'), findsOneWidget); // header
    expect(find.text('Next #'), findsNothing); // dropped (redundant)
    expect(find.text('Set'), findsNothing); // replaced by a chevron
    expect(find.text('QTN-.2026.-0001'), findsOneWidget); // id sample
    expect(find.byIcon(Icons.chevron_right), findsNWidgets(2)); // one per row
  });

  testWidgets('narrow: Series is hidden, keeping Document + Next id',
      (tester) async {
    await pump(tester, const Size(400, 800));
    expect(tester.takeException(), isNull);
    expect(find.text('Series'), findsNothing); // hidden on phone
    expect(find.text('Next id'), findsOneWidget);
    expect(find.text('PINV-.2026.-1001'), findsOneWidget);
  });
}
