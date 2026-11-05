import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// C4: what this device knows about the Team server's history.
///
/// The server keeps a hash chain over its replication log (backend
/// `src/history.rs`). After every successful sync the device stores the
/// server's head and the chain value there: its **checkpoint**. A posting
/// response carries the head too, kept as a *pending* checkpoint until the
/// next sync verifies it.
///
/// Before syncing again the device asks for the chain value at each
/// checkpoint. A server restored from a backup cannot produce the same value
/// for a version written after the backup, even when its log has since
/// grown past that version, and it cannot fake it by restoring a stored
/// generation number, because the value is computed from the log itself.
class TeamHistoryCheckpoint {
  const TeamHistoryCheckpoint(this.version, this.hash);
  final int version;
  final String hash;

  Map<String, Object> toJson() => {'version': version, 'hash': hash};

  /// A divergence found from the sync cursor alone (an upgraded device
  /// with no checkpoint yet, against a log shorter than its cursor): there
  /// is no chain value to compare, only the version.
  const TeamHistoryCheckpoint.cursorOnly(this.version) : hash = '';

  bool get isCursorOnly => hash.isEmpty;

  /// A checkpoint as stored. An empty hash is refused unless
  /// [allowCursorOnly] (a divergence marker may be cursor-only; a checkpoint
  /// to verify against never is).
  static TeamHistoryCheckpoint? fromJson(Object? j,
      {bool allowCursorOnly = false}) {
    if (j is! Map) return null;
    final v = j['version'];
    final h = j['hash'];
    if (v is! int || h is! String) return null;
    if (h.isEmpty && !allowCursorOnly) return null;
    return TeamHistoryCheckpoint(v, h);
  }

  @override
  bool operator ==(Object other) =>
      other is TeamHistoryCheckpoint &&
      other.version == version &&
      other.hash == hash;

  @override
  int get hashCode => Object.hash(version, hash);

  @override
  String toString() =>
      '$version:${hash.length > 12 ? hash.substring(0, 12) : hash}';
}

/// The server's history no longer contains what this device saw: it was
/// restored from a backup. Ordinary sync and Team posting stop until the
/// device recovers (`TeamHistoryRecovery`).
class TeamHistoryDiverged implements Exception {
  const TeamHistoryDiverged({
    required this.checkpoint,
    required this.serverHead,
    this.detectedAt,
  });

  /// The checkpoint that no longer matches.
  final TeamHistoryCheckpoint checkpoint;

  /// The server's log head when it was detected.
  final int serverHead;
  final DateTime? detectedAt;

  bool get logBehind => serverHead < checkpoint.version;

  Map<String, Object?> toJson() => {
        'checkpoint': checkpoint.toJson(),
        'server_head': serverHead,
        'detected_at': (detectedAt ?? DateTime.now()).toIso8601String(),
      };

  static TeamHistoryDiverged? fromJson(Object? j) {
    if (j is! Map) return null;
    final c =
        TeamHistoryCheckpoint.fromJson(j['checkpoint'], allowCursorOnly: true);
    if (c == null) return null;
    return TeamHistoryDiverged(
      checkpoint: c,
      serverHead: j['server_head'] is int ? j['server_head'] as int : 0,
      detectedAt: DateTime.tryParse('${j['detected_at']}'),
    );
  }

  @override
  String toString() =>
      'The Atlas Team server was restored from a backup: its history no '
      'longer matches what this device synced (version ${checkpoint.version}'
      '${logBehind ? ', server now ends at $serverHead' : ''}). Sync and Team '
      'posting are paused on this device until it recovers: Team › Recover '
      'this device.';
}

/// Where a device keeps its checkpoints and the "recovery needed" mark, per
/// company. Device-local by nature: never synced, never in the database
/// (the recovery replaces the database).
abstract class TeamHistoryStore {
  Future<TeamHistoryCheckpoint?> verified(String companyId);
  Future<void> setVerified(String companyId, TeamHistoryCheckpoint c);

  /// Checkpoints from posting responses, not yet verified by a sync.
  Future<List<TeamHistoryCheckpoint>> pending(String companyId);
  Future<void> setPending(String companyId, List<TeamHistoryCheckpoint> c);

  Future<TeamHistoryDiverged?> diverged(String companyId);
  Future<void> setDiverged(String companyId, TeamHistoryDiverged? d);

  /// Records a posting response's `history` as a pending checkpoint.
  Future<void> notePosting(String companyId, Object? history) async {
    final c = TeamHistoryCheckpoint.fromJson(history);
    if (c == null) return;
    await notePending(companyId, c);
  }

  /// Adds [c] to the pending checkpoints (checked by the next sync, dropped
  /// once a sync's head covers it).
  Future<void> notePending(String companyId, TeamHistoryCheckpoint c) async {
    if (c.isCursorOnly) return;
    final list = [
      for (final p in await pending(companyId))
        if (p != c) p,
      c,
    ]..sort((a, b) => a.version.compareTo(b.version));
    // The newest few are enough: each covers everything before it.
    await setPending(
        companyId, list.length > 20 ? list.sublist(list.length - 20) : list);
  }

  /// Forgets everything for [companyId] (a recovered or new book).
  Future<void> reset(String companyId) async {
    await setPending(companyId, const []);
    await setDiverged(companyId, null);
  }
}

class PrefsTeamHistoryStore extends TeamHistoryStore {
  static const _prefix = 'hub.team_history.';

  Future<Map<String, Object?>> _read(String companyId) async {
    final raw =
        (await SharedPreferences.getInstance()).getString('$_prefix$companyId');
    if (raw == null) return {};
    try {
      return Map<String, Object?>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return {};
    }
  }

  Future<void> _write(String companyId, Map<String, Object?> m) async =>
      (await SharedPreferences.getInstance())
          .setString('$_prefix$companyId', jsonEncode(m));

  @override
  Future<TeamHistoryCheckpoint?> verified(String companyId) async =>
      TeamHistoryCheckpoint.fromJson((await _read(companyId))['verified']);

  @override
  Future<void> setVerified(String companyId, TeamHistoryCheckpoint c) async =>
      _write(companyId, {...await _read(companyId), 'verified': c.toJson()});

  @override
  Future<List<TeamHistoryCheckpoint>> pending(String companyId) async {
    final raw = (await _read(companyId))['pending'];
    return [
      if (raw is List)
        for (final j in raw)
          if (TeamHistoryCheckpoint.fromJson(j) case final c?) c,
    ];
  }

  @override
  Future<void> setPending(
          String companyId, List<TeamHistoryCheckpoint> c) async =>
      _write(companyId, {
        ...await _read(companyId),
        'pending': [for (final x in c) x.toJson()],
      });

  @override
  Future<TeamHistoryDiverged?> diverged(String companyId) async =>
      TeamHistoryDiverged.fromJson((await _read(companyId))['diverged']);

  @override
  Future<void> setDiverged(String companyId, TeamHistoryDiverged? d) async {
    final m = await _read(companyId);
    if (d == null) {
      m.remove('diverged');
    } else {
      m['diverged'] = d.toJson();
    }
    await _write(companyId, m);
  }
}

/// For tests and for building a book in a staging file, where the live
/// device's marks must not be touched.
class MemoryTeamHistoryStore extends TeamHistoryStore {
  TeamHistoryCheckpoint? verifiedValue;
  List<TeamHistoryCheckpoint> pendingValue = const [];
  TeamHistoryDiverged? divergedValue;

  @override
  Future<TeamHistoryCheckpoint?> verified(String companyId) async =>
      verifiedValue;
  @override
  Future<void> setVerified(String companyId, TeamHistoryCheckpoint c) async =>
      verifiedValue = c;
  @override
  Future<List<TeamHistoryCheckpoint>> pending(String companyId) async =>
      pendingValue;
  @override
  Future<void> setPending(
          String companyId, List<TeamHistoryCheckpoint> c) async =>
      pendingValue = List.of(c);
  @override
  Future<TeamHistoryDiverged?> diverged(String companyId) async =>
      divergedValue;
  @override
  Future<void> setDiverged(String companyId, TeamHistoryDiverged? d) async =>
      divergedValue = d;
}

/// The server's answer to `GET …/sync/history?at=N`.
class TeamHistoryAnswer {
  const TeamHistoryAnswer({
    required this.head,
    required this.headHash,
    required this.at,
    required this.atHash,
  });
  final int head;
  final String headHash;
  final int at;
  final String? atHash;

  TeamHistoryCheckpoint get headCheckpoint =>
      TeamHistoryCheckpoint(head, headHash);

  static TeamHistoryAnswer? fromJson(Object? j) {
    if (j is! Map || j['head'] is! int || j['headHash'] is! String) {
      return null;
    }
    return TeamHistoryAnswer(
      head: j['head'] as int,
      headHash: j['headHash'] as String,
      at: j['at'] is int ? j['at'] as int : 0,
      atHash: j['atHash'] is String ? j['atHash'] as String : null,
    );
  }
}

/// Asks the server for its history at a version. Returns null when the
/// server predates the history protocol (older servers keep the old
/// head-behind-cursor check, which sees only a restore with no later
/// activity).
typedef TeamHistoryProbe = Future<TeamHistoryAnswer?> Function(int at);

/// The check every sync runs first. Throws [TeamHistoryDiverged] (and marks
/// the device) when the server no longer has the history this device saw.
/// Returns false when the server cannot answer (older server).
Future<bool> verifyTeamHistory({
  required String companyId,
  required TeamHistoryStore store,
  required TeamHistoryProbe probe,
  required int cursor,
}) async {
  final marked = await store.diverged(companyId);
  if (marked != null) throw marked;

  final verified = await store.verified(companyId);
  final pending = await store.pending(companyId);
  final toCheck = <TeamHistoryCheckpoint>[
    if (verified != null) verified,
    ...pending,
  ];
  if (toCheck.isEmpty) {
    // First sync on this protocol (a new device or an upgraded one): there
    // is nothing to compare with yet, except that a log shorter than our
    // cursor was certainly restored.
    final now = await probe(0);
    if (now == null) return false;
    if (cursor > now.head) {
      await _mark(
          store, companyId, TeamHistoryCheckpoint.cursorOnly(cursor), now.head);
    }
    return true;
  }
  for (final c in toCheck) {
    final answer = await probe(c.version);
    if (answer == null) return false;
    if (answer.atHash == null || answer.atHash != c.hash) {
      await _mark(store, companyId, c, answer.head);
    }
  }
  return true;
}

Future<Never> _mark(TeamHistoryStore store, String companyId,
    TeamHistoryCheckpoint c, int head) async {
  final d = TeamHistoryDiverged(
      checkpoint: c, serverHead: head, detectedAt: DateTime.now());
  await store.setDiverged(companyId, d);
  throw d;
}

/// After a successful sync: the server's head becomes the verified
/// checkpoint, and the pending ones it covers are dropped.
Future<void> advanceTeamHistory({
  required String companyId,
  required TeamHistoryStore store,
  required TeamHistoryProbe probe,
}) async {
  final now = await probe(0);
  if (now == null) return;
  await store.setVerified(companyId, now.headCheckpoint);
  final rest = [
    for (final c in await store.pending(companyId))
      if (c.version > now.head) c,
  ];
  await store.setPending(companyId, rest);
}
