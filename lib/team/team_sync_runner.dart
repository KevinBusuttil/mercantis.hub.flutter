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
///
/// The backend pages its pull responses (Phase 0.6, gap analysis §8-C9), so
/// that bootstrap arrives as bounded pages, each applied, cursor-committed
/// and acknowledged before the next is fetched — a dropped connection at
/// page 40 of 60 resumes at page 40, not page 1.
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
      // Pull BEFORE push: conflict detection keys on the local document
      // still carrying its unshipped edits (`sync_state=local`) when the
      // foreign edit arrives. Pushing first would flip those documents to
      // `synced` and a genuinely concurrent remote edit would fast-forward
      // over them — exactly the silent loss the policy exists to prevent.
      var cursor = await cursorStore.load(companyId);
      var pulled = 0;
      var applied = 0;
      while (true) {
        final after = cursor == 0 ? null : '$cursor';
        final page = adapter is PagedCloudAdapter
            ? await (adapter as PagedCloudAdapter).pullPage(after)
            : PullPage(await adapter.pull(after), hasMore: false);
        final remote = page.mutations;
        pulled += remote.length;

        final foreign =
            remote.where((m) => m.deviceId != localDeviceId).toList();
        await sync.applyRemoteMutations(foreign);
        applied += foreign.length;

        // Commit the cursor BEFORE fetching the next page: if the loop dies
        // here, this page is already applied and never re-fetched.
        var advanced = cursor;
        for (final m in remote) {
          final version = int.tryParse(m.syncVersion ?? '');
          if (version != null) advanced = math.max(advanced, version);
        }
        final progressed = advanced != cursor;
        if (progressed) {
          cursor = advanced;
          await cursorStore.save(companyId, advanced);
        }

        if (remote.isNotEmpty) {
          await adapter.acknowledge([for (final m in remote) m.id]);
        }
        if (!page.hasMore) break;
        // A page that didn't move the cursor would just repeat itself —
        // refuse to spin even if the server claims there's more.
        if (!progressed) break;
      }

      final pushed = await sync.pendingCount();
      // Throws on transport/backend failure; the engine returns the batch to
      // pending, so nothing strands and the next run retries. Mutations for
      // documents now sitting in conflict are held back by the engine.
      await sync.pushPendingMutations();

      return TeamSyncResult(
        pushed: pushed,
        pulled: pulled,
        applied: applied,
      );
    } finally {
      sync.dispose();
    }
  }
}
