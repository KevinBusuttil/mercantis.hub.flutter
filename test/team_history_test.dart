import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_hub_app/team/team_history.dart';
import 'package:mercantis_hub_app/team/team_sync_runner.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'dart:io';

import 'support/books_harness.dart';

/// C4 — the device side of the server-history check, without a server. The
/// restore scenarios on a real backend and PostgreSQL are in
/// test/team_e2e/team_restore_e2e_test.dart.
void main() {
  const company = 'co-1';

  /// A server whose chain value at version v is `h<v>` (or `x<v>` after a
  /// restore that rewrote history from [rewrittenFrom]).
  TeamHistoryProbe server(int head,
      {int? rewrittenFrom, List<int>? calls, bool old = false}) {
    String hashAt(int v) =>
        rewrittenFrom != null && v >= rewrittenFrom ? 'x$v' : 'h$v';
    return (at) async {
      calls?.add(at);
      if (old) return null;
      return TeamHistoryAnswer(
        head: head,
        headHash: hashAt(head),
        at: at,
        atHash: at > head ? null : hashAt(at),
      );
    };
  }

  test('a matching checkpoint passes and moves to the new head', () async {
    final store = MemoryTeamHistoryStore()
      ..verifiedValue = const TeamHistoryCheckpoint(10, 'h10');
    expect(
        await verifyTeamHistory(
            companyId: company, store: store, probe: server(14), cursor: 10),
        isTrue);
    await advanceTeamHistory(
        companyId: company, store: store, probe: server(14));
    expect(store.verifiedValue, const TeamHistoryCheckpoint(14, 'h14'));
  });

  test(
      'a history rewritten after the checkpoint is caught even when the '
      'log has grown past it', () async {
    final store = MemoryTeamHistoryStore()
      ..verifiedValue = const TeamHistoryCheckpoint(10, 'h10');
    await expectLater(
      verifyTeamHistory(
          companyId: company,
          store: store,
          probe: server(25, rewrittenFrom: 8),
          cursor: 10),
      throwsA(isA<TeamHistoryDiverged>()
          .having((d) => d.logBehind, 'logBehind', isFalse)),
    );
    expect(store.divergedValue, isNotNull, reason: 'the device is marked');

    // Marked: the next sync stops before asking the server anything, and a
    // healthy-looking answer does not clear it (only a recovery does).
    final calls = <int>[];
    await expectLater(
      verifyTeamHistory(
          companyId: company,
          store: store,
          probe: server(30, calls: calls),
          cursor: 10),
      throwsA(isA<TeamHistoryDiverged>()),
    );
    expect(calls, isEmpty);
  });

  test('a log shorter than the checkpoint is a restore', () async {
    final store = MemoryTeamHistoryStore()
      ..verifiedValue = const TeamHistoryCheckpoint(10, 'h10');
    await expectLater(
      verifyTeamHistory(
          companyId: company, store: store, probe: server(6), cursor: 10),
      throwsA(isA<TeamHistoryDiverged>()
          .having((d) => d.logBehind, 'logBehind', isTrue)),
    );
  });

  test(
      'a posting the restore lost is caught although the older checkpoint '
      'still matches', () async {
    final store = MemoryTeamHistoryStore()
      ..verifiedValue = const TeamHistoryCheckpoint(10, 'h10');
    // This device posted at version 12 between syncs; the server was then
    // restored to 11 and moved on to 15 with other work.
    await store.notePosting(company, {'version': 12, 'hash': 'h12'});
    await expectLater(
      verifyTeamHistory(
          companyId: company,
          store: store,
          probe: server(15, rewrittenFrom: 12),
          cursor: 10),
      throwsA(isA<TeamHistoryDiverged>()
          .having((d) => d.checkpoint.version, 'version', 12)),
    );
  });

  test('an older server without the history route keeps the old behaviour',
      () async {
    final store = MemoryTeamHistoryStore()
      ..verifiedValue = const TeamHistoryCheckpoint(10, 'h10');
    expect(
        await verifyTeamHistory(
            companyId: company,
            store: store,
            probe: server(4, old: true),
            cursor: 10),
        isFalse);
    expect(store.divergedValue, isNull);
  });

  test(
      'the first check on this protocol adopts the server, unless the log '
      'is shorter than the cursor', () async {
    final fresh = MemoryTeamHistoryStore();
    expect(
        await verifyTeamHistory(
            companyId: company, store: fresh, probe: server(9), cursor: 9),
        isTrue);
    final behind = MemoryTeamHistoryStore();
    await expectLater(
      verifyTeamHistory(
          companyId: company, store: behind, probe: server(5), cursor: 9),
      throwsA(isA<TeamHistoryDiverged>()),
    );
  });

  test('pending checkpoints are capped and dropped once covered', () async {
    final store = MemoryTeamHistoryStore();
    for (var v = 1; v <= 30; v++) {
      await store.notePosting(company, {'version': v, 'hash': 'h$v'});
    }
    await store.notePosting(company, {'nonsense': true});
    expect(store.pendingValue, hasLength(20));
    expect(store.pendingValue.first.version, 11);
    await advanceTeamHistory(
        companyId: company, store: store, probe: server(25));
    expect(store.pendingValue.map((c) => c.version), [26, 27, 28, 29, 30]);
  });

  test('the preferences store round-trips and resets', () async {
    SharedPreferences.setMockInitialValues({});
    final store = PrefsTeamHistoryStore();
    await store.setVerified(company, const TeamHistoryCheckpoint(3, 'h3'));
    await store.notePosting(company, {'version': 5, 'hash': 'h5'});
    await store.setDiverged(
        company,
        const TeamHistoryDiverged(
            checkpoint: TeamHistoryCheckpoint(5, 'h5'), serverHead: 2));
    final again = PrefsTeamHistoryStore();
    expect(await again.verified(company), const TeamHistoryCheckpoint(3, 'h3'));
    expect(
        await again.pending(company), [const TeamHistoryCheckpoint(5, 'h5')]);
    expect((await again.diverged(company))!.serverHead, 2);
    expect(await again.verified('other'), isNull, reason: 'per company');
    await again.reset(company);
    expect(await again.diverged(company), isNull);
    expect(await again.pending(company), isEmpty);
  });

  group('sync runner', () {
    setUpAll(sqfliteFfiInit);
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('team_history_'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('a diverged server stops the exchange before anything is sent',
        () async {
      final h = await BooksHarness.open(p.join(dir.path, 'm.db'));
      await h.save(Document(id: 'C-1', docType: 'Customer', payload: {
        'customer_name': 'Harbour Bar',
        'customer_type': 'Company',
      }));
      final adapter = _RecordingAdapter();
      final store = MemoryTeamHistoryStore()
        ..verifiedValue = const TeamHistoryCheckpoint(10, 'h10');
      final runner = TeamSyncRunner(
        database: h.db.db,
        registry: MetadataRegistry(h.db.db),
        adapter: adapter,
        localDeviceId: 'device-1',
        companyId: company,
        cursorStore: _MemCursor(10),
        historyProbe: server(40, rewrittenFrom: 5),
        historyStore: store,
      );
      await expectLater(runner.run(), throwsA(isA<TeamHistoryDiverged>()));
      expect(adapter.calls, isEmpty, reason: 'no push, no pull');
      expect(
          await h.db.db
              .query('sync_queue', where: 'status = ?', whereArgs: ['pending']),
          isNotEmpty,
          reason: 'the unsent edit is still queued');

      // A healthy server: the exchange runs and the checkpoint advances.
      final ok = MemoryTeamHistoryStore()
        ..verifiedValue = const TeamHistoryCheckpoint(10, 'h10');
      await TeamSyncRunner(
        database: h.db.db,
        registry: MetadataRegistry(h.db.db),
        adapter: adapter,
        localDeviceId: 'device-1',
        companyId: company,
        cursorStore: _MemCursor(10),
        historyProbe: server(12),
        historyStore: ok,
      ).run();
      expect(adapter.calls, contains('push'));
      expect(ok.verifiedValue, const TeamHistoryCheckpoint(12, 'h12'));
      await h.close();
    });
  });
}

class _MemCursor implements TeamSyncCursorStore {
  _MemCursor(this.value);
  int value;
  @override
  Future<int> load(String companyId) async => value;
  @override
  Future<void> save(String companyId, int cursor) async => value = cursor;
}

class _RecordingAdapter implements CloudAdapter {
  final calls = <String>[];
  @override
  Future<void> push(List<MutationRecord> mutations) async => calls.add('push');
  @override
  Future<List<MutationRecord>> pull(String? afterSyncVersion) async {
    calls.add('pull');
    return const [];
  }

  @override
  Future<void> acknowledge(List<String> mutationIds) async => calls.add('ack');
  @override
  Future<void> pushBlob(String sha256, List<int> bytes) async {}
  @override
  Future<List<int>?> pullBlob(String sha256) async => null;
  @override
  Future<bool> hasBlob(String sha256) async => false;
}
