import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_hub_app/hospitality/hospitality_audit.dart';
import 'package:mercantis_hub_app/screens/hospitality_audit_screen.dart';

/// V2-5: the void/comp audit screen renders each giveaway with its
/// reason and value, sectioned with totals.
void main() {
  Future<void> pump(WidgetTester tester, HospitalityAudit audit) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        hospitalityAuditProvider.overrideWith((ref) async => audit),
      ],
      child: const MaterialApp(home: HospitalityAuditScreen()),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('sections show entries, reasons and totals', (tester) async {
    await pump(
      tester,
      HospitalityAudit(
        voids: [
          HospitalityAuditEntry(
            kind: 'Voided tab',
            id: 'TAB-2026-0007',
            detail: 'T1 · Anna',
            reason: 'Guests walked out',
            value: 17.5,
            when: DateTime(2026, 7, 12),
          ),
        ],
        comps: [
          HospitalityAuditEntry(
            kind: 'Comped line',
            id: 'TAB-2026-0008',
            detail: '1 × BURGER · Anna',
            reason: 'Dropped at the pass',
            value: 12,
            when: DateTime(2026, 7, 12),
          ),
        ],
        cancellations: const [],
      ),
    );

    expect(find.text('Voided tabs (1)'), findsOneWidget);
    expect(find.text('TAB-2026-0007 · T1 · Anna'), findsOneWidget);
    expect(find.text('“Guests walked out”'), findsOneWidget);
    expect(find.text('17.50'), findsNWidgets(2)); // entry + section total

    expect(find.text('Comped items (1)'), findsOneWidget);
    expect(find.text('“Dropped at the pass”'), findsOneWidget);
    expect(find.text('12.00'), findsNWidgets(2));

    // Empty section renders nothing at all.
    expect(find.textContaining('Cancelled fiscal invoices'), findsNothing);
  });

  testWidgets('a clean book shows the empty state', (tester) async {
    await pump(tester,
        const HospitalityAudit(voids: [], comps: [], cancellations: []));
    expect(find.text('Nothing given away'), findsOneWidget);
  });
}
