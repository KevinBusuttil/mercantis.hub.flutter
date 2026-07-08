import 'dart:math' as math;

import 'package:mercantis_core/mercantis_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common/sqlite_api.dart';

/// What one Team sync exchange did.
class TeamSyncResult {
  const TeamSyncResult({
    required this.pushed,
    required this.pulled,
    required this.applied,
  });

  /// Local mutations shipped to the backend this run.
  final int pushed;

  /// Mutations the backend returned past our cursor (own echoes included).
  final int pulled;

  /// Foreign mutations actually applied locally (own echoes excluded).
  final int applied;
}

/// Persists the per-company pull cursor: the highest server sync version
/// this device has applied. Device-local by nature, so preferences — never
/// the synced store.
class TeamSyncCursorStore {
  static const _prefix = 'hub.team_cursor.';

  Future<int> load(String companyId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('$_prefix$companyId') ?? 0;
  }

  Future<void> save(String companyId, int cursor) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('$_prefix$companyId', cursor);
  }
}

/// One Team sync exchange (Team milestone 3): push pending local mutations
/// to the backend, pull everything past this device's cursor, apply the
/// foreign ones, advance the cursor, acknowledge.
///
/// Unlike the filesystem adapter — which skips its own subdirectory on pull —
/// the backend returns *every* mutation in the company log, including this
/// device's own echoes. They're filtered here by device id before apply
/// (re-applying them is wasted work at best and can wrestle with newer local
/// edits at worst), but the cursor still advances over them so they're never
/// fetched again. A brand-new device starts at cursor 0 and receives the
/// whole company history — that IS the second-device bootstrap.
class TeamSyncRunner {
  TeamSyncRunner({
    required this.database,
    required this.registry,
    required this.adapter,
    required this.localDeviceId,
    required this.companyId,
    TeamSyncCursorStore? cursorStore,
    this.attachmentStore,
  }) : cursorStore = cursorStore ?? TeamSyncCursorStore();

  final Database database;
  final MetadataRegistry registry;
  final CloudAdapter adapter;
  final String localDeviceId;
  final String companyId;
  final TeamSyncCursorStore cursorStore;
  final AttachmentStore? attachmentStore;

  Future<TeamSyncResult> run() async {
    final sync = SyncEngine(
      database: database,
      registry: registry,
      cloudAdapter: adapter,
      attachmentStore: attachmentStore,
    );
    try {
      final pushed = await sync.pendingCount();
      // Throws on transport/backend failure; the engine returns the batch to
      // pending, so nothing strands and the next run retries.
      await sync.pushPendingMutations();

      final cursor = await cursorStore.load(companyId);
      final remote = await adapter.pull(cursor == 0 ? null : '$cursor');

      final foreign =
          remote.where((m) => m.deviceId != localDeviceId).toList();
      await sync.applyRemoteMutations(foreign);

      var advanced = cursor;
      for (final m in remote) {
        final version = int.tryParse(m.syncVersion ?? '');
        if (version != null) advanced = math.max(advanced, version);
      }
      if (advanced != cursor) await cursorStore.save(companyId, advanced);

      if (remote.isNotEmpty) {
        await adapter.acknowledge([for (final m in remote) m.id]);
      }
      return TeamSyncResult(
        pushed: pushed,
        pulled: remote.length,
        applied: foreign.length,
      );
    } finally {
      sync.dispose();
    }
  }
}
