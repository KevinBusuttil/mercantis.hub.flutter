import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_hub_app/screens/conflicts_screen.dart';
import 'package:mercantis_hub_app/sync/conflict_providers.dart';

/// Phase 0.10: the conflicts screen shows both sides of each stuck document
/// and offers keep-mine / take-theirs — no silent winner.
void main() {
  SyncConflict conflict() => SyncConflict(
        documentId: 'N-1',
        docType: 'Note',
        detectedAt: DateTime.fromMillisecondsSinceEpoch(1751900000000),
        remote: MutationRecord(
          id: 'mut-9',
          type: MutationType.updateDocument,
          docType: 'Note',
          documentId: 'N-1',
          payload: const {'id': 'N-1', 'doctype': 'Note'},
          deviceId: 'devB',
          userId: 'maria',
          localTimestamp: DateTime.fromMillisecondsSinceEpoch(1751800000000),
          syncVersion: '9',
        ),
        local: Document(
            id: 'N-1', docType: 'Note', payload: const {'title': 'mine'}),
      );

  Future<void> pump(WidgetTester tester, List<SyncConflict> conflicts) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        syncConflictsProvider.overrideWith((ref) async => conflicts),
      ],
      child: const MaterialApp(home: ConflictsScreen()),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('a conflict shows both sides and the two resolutions',
      (tester) async {
    await pump(tester, [conflict()]);
    expect(find.textContaining('NOTE · N-1'), findsOneWidget);
    expect(find.textContaining('by maria'), findsOneWidget);
    expect(find.text('Keep mine'), findsOneWidget);
    expect(find.text('Take theirs'), findsOneWidget);
  });

  testWidgets('resolution asks for confirmation first', (tester) async {
    await pump(tester, [conflict()]);
    await tester.tap(find.text('Take theirs'));
    await tester.pumpAndSettle();
    expect(find.text('Take their version?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Take their version?'), findsNothing);
    // Cancelled: the row is still there, nothing resolved.
    expect(find.textContaining('NOTE · N-1'), findsOneWidget);
  });

  testWidgets('empty state says merges are automatic', (tester) async {
    await pump(tester, const []);
    expect(find.text('No conflicts'), findsOneWidget);
  });
}
