import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_hub_app/scheduling/resource_calendar.dart';

/// S1b: the calendar widget is pure presentation — lanes, positioned
/// blocks, entry taps, and slot taps snapped down to the slot grid.
void main() {
  final day = DateTime(2026, 7, 13);
  final lanes = [
    CalendarLane(id: 'CHAIR-1', label: 'Chair 1', date: day),
    CalendarLane(id: 'CHAIR-2', label: 'Chair 2', date: day),
  ];
  final entries = [
    CalendarEntry(
      id: 'APT-1',
      laneId: 'CHAIR-1',
      start: DateTime(2026, 7, 13, 9),
      end: DateTime(2026, 7, 13, 10),
      title: 'Anna',
      subtitle: 'CUST-1',
    ),
    CalendarEntry(
      id: 'APT-2',
      laneId: 'CHAIR-2',
      start: DateTime(2026, 7, 13, 11),
      end: DateTime(2026, 7, 13, 12, 30),
      title: 'Bert',
    ),
  ];

  Future<void> pump(
    WidgetTester tester, {
    void Function(CalendarEntry)? onEntryTap,
    void Function(CalendarLane, DateTime)? onSlotTap,
  }) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ResourceCalendar(
          lanes: lanes,
          entries: entries,
          onEntryTap: onEntryTap,
          onSlotTap: onSlotTap,
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('renders lane headers and entry blocks', (tester) async {
    await pump(tester);
    expect(find.text('Chair 1'), findsOneWidget);
    expect(find.text('Chair 2'), findsOneWidget);
    expect(find.text('Anna'), findsOneWidget);
    expect(find.text('Bert'), findsOneWidget);
    expect(find.text('CUST-1'), findsOneWidget); // tall block shows subtitle
    expect(find.text('09:00'), findsOneWidget); // time gutter
  });

  testWidgets('tapping a block reports the entry', (tester) async {
    CalendarEntry? tapped;
    await pump(tester, onEntryTap: (e) => tapped = e);
    await tester.tap(find.text('Anna'));
    expect(tapped!.id, 'APT-1');
  });

  testWidgets('tapping empty space books the snapped slot in that lane',
      (tester) async {
    CalendarLane? lane;
    DateTime? slot;
    await pump(tester, onSlotTap: (l, t) {
      lane = l;
      slot = t;
    });
    // Default geometry: startHour 7, hourHeight 64 → 8:45 sits 1.75h down.
    // 8:45 must snap DOWN to the 8:30 slot.
    final laneBox = tester.getRect(find.byType(GestureDetector).first);
    await tester.tapAt(Offset(laneBox.left + 20, laneBox.top + 1.75 * 64));
    expect(lane!.id, 'CHAIR-1');
    expect(slot, DateTime(2026, 7, 13, 8, 30));
  });

  testWidgets('an empty lane list explains itself', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: ResourceCalendar(lanes: [], entries: []),
      ),
    ));
    expect(find.text('Nothing to schedule on'), findsOneWidget);
  });
}
