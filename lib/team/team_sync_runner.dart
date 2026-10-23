import 'dart:convert';
import 'dart:math' as math;

import 'package:mercantis_core/mercantis_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common/sqlite_api.dart';

import '../support/diagnostic_log.dart';
import 'team_posting_service.dart' show buildSubmitCommand;

/// Ledger rows only the Team server authors (the backend's
/// `authority::DERIVED_DOCTYPES`). The local engine still derives them —
/// for previews, and for the till's offline sales — but in Team they never
/// leave the device: the server derives the official rows (with the same
/// deterministic ids) and replicates them to every device, and it refuses
/// client-authored ones.
const teamServerDerivedDocTypes = {
  'GL Entry',
  'Stock Ledger Entry',
  'Bin',
  'Settlement',
  'Customer Transaction',
  'Supplier Transaction',
  'Tax Transaction',
};

/// A till sale the server would not confirm, with its reason (e.g. the till
/// series is bound to another register, or the period is locked). The sale
/// stays a local fiscal sale until someone resolves it.
class TillSaleAttention {
  const TillSaleAttention(this.invoiceId, this.reason);
  final String invoiceId;
  final String reason;
  @override
  String toString() => '$invoiceId: $reason';
}

/// What one Team sync exchange did.
class TeamSyncResult {
  const TeamSyncResult({
    required this.pushed,
    required this.pulled,
    required this.applied,
    this.confirmedTillSales = 0,
    this.tillSalesNeedingAttention = const [],
    this.cursorReset = false,
  });

  /// Local mutations shipped to the backend this run.
  final int pushed;

  /// Mutations the backend returned past our cursor (own echoes included).
  final int pulled;

  /// Foreign mutations actually applied locally (own echoes excluded).
  final int applied;

  /// Offline till sales the server confirmed this run (Team-wide accounting
  /// now exists for them).
  final int confirmedTillSales;

  /// Till sales the server refused to confirm, for the user to resolve.
  final List<TillSaleAttention> tillSalesNeedingAttention;

  /// The server's log was behind this device's cursor (it was restored
  /// from a backup), so the device re-pulled the whole log from 0.
  final bool cursorReset;
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
    this.confirmTillSale,
    this.logHead,
  }) : cursorStore = cursorStore ?? TeamSyncCursorStore();

  final Database database;
  final MetadataRegistry registry;
  final CloudAdapter adapter;
  final String localDeviceId;
  final String companyId;
  final TeamSyncCursorStore cursorStore;
  final AttachmentStore? attachmentStore;

  /// Sends one submit-document command to the posting authority (the
  /// production wiring is `TeamPostingClient.submitDocument`). Null skips
  /// till-sale confirmation (tests of the plain sync plane).
  final Future<Map<String, dynamic>> Function(Map<String, dynamic> command)?
      confirmTillSale;

  /// The server log's newest sync version (`head` of a pull). Null skips the
  /// restored-server check.
  final Future<int?> Function()? logHead;

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
      // The server's ledger rows always win over this device's provisional
      // ones, so they must not look like unshipped local edits to conflict
      // detection.
      await _yieldServerDerivedRows();
      var cursor = await cursorStore.load(companyId);
      var cursorReset = false;
      var (pulled, applied) = await _pullAll(sync, cursor);
      if (pulled == 0 && cursor > 0 && logHead != null) {
        // Nothing new — or the server was restored from a backup older
        // than our last sync, so its log now ends before our cursor and
        // every later mutation would be skipped. Re-pull from 0; applying
        // is idempotent.
        final head = await logHead!();
        if (head != null && head < cursor) {
          DiagnosticLog.instance.record('sync',
              'Team log head $head is behind cursor $cursor: server restored, re-pulling');
          await cursorStore.save(companyId, 0);
          cursorReset = true;
          (pulled, applied) = await _pullAll(sync, 0);
        }
      }

      await _yieldServerDerivedRows();
      final pushed = await sync.pendingCount();
      // Throws on transport/backend failure; the engine returns the batch to
      // pending, so nothing strands and the next run retries. Mutations for
      // documents now sitting in conflict are held back by the engine.
      await sync.pushPendingMutations();

      final (confirmed, attention) = await _confirmTillSales();
      if (confirmed > 0) {
        // The confirmations' official rows (GL, stock, tax, bins) are on
        // the log now: bring them home in the same exchange.
        final (morePulled, moreApplied) =
            await _pullAll(sync, await cursorStore.load(companyId));
        pulled += morePulled;
        applied += moreApplied;
      }

      return TeamSyncResult(
        pushed: pushed,
        pulled: pulled,
        applied: applied,
        confirmedTillSales: confirmed,
        tillSalesNeedingAttention: attention,
        cursorReset: cursorReset,
      );
    } finally {
      sync.dispose();
    }
  }

  /// Pages through the log after [start], applying foreign mutations and
  /// committing the cursor per page. Returns (pulled, applied).
  Future<(int, int)> _pullAll(SyncEngine sync, int start) async {
    var cursor = start;
    var pulled = 0;
    var applied = 0;
    while (true) {
      final after = cursor == 0 ? null : '$cursor';
      final page = adapter is PagedCloudAdapter
          ? await (adapter as PagedCloudAdapter).pullPage(after)
          : PullPage(await adapter.pull(after), hasMore: false);
      final remote = page.mutations;
      pulled += remote.length;

      final foreign = remote.where((m) => m.deviceId != localDeviceId).toList();
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
    return (pulled, applied);
  }

  /// Locally derived ledger rows never ship in Team (see
  /// [teamServerDerivedDocTypes]): their queued mutations are dropped, and
  /// the rows are marked synced (any conflict on them cleared) so the
  /// server's official rows — same deterministic ids — fast-forward over
  /// these provisional ones on pull. Without this a till's own offline sale
  /// leaves its Bin "edited locally", the server's Bin for the confirmed sale
  /// is parked as a conflict, and the till's stock never converges.
  Future<void> _yieldServerDerivedRows() async {
    final inDerived =
        'doctype IN (${List.filled(teamServerDerivedDocTypes.length, '?').join(', ')})';
    await database.transaction((txn) async {
      await txn.delete('sync_queue',
          where: 'status = ? AND $inDerived',
          whereArgs: [MutationStatus.pending.name, ...teamServerDerivedDocTypes]);
      await txn.update('documents', {'sync_state': SyncState.synced.name},
          where: 'sync_state != ? AND $inDerived',
          whereArgs: [SyncState.synced.name, ...teamServerDerivedDocTypes]);
      await txn.delete('sync_conflicts',
          where: inDerived, whereArgs: [...teamServerDerivedDocTypes]);
    });
  }

  /// Asks the server to confirm every till sale this device completed
  /// offline and the server has not confirmed yet (no `official_number`).
  /// Idempotent: the command key is derived from the receipt id, so a
  /// confirmation whose response was lost replays instead of posting twice.
  /// A transport failure stops the round (the next sync retries); a refusal
  /// is reported per sale.
  Future<(int, List<TillSaleAttention>)> _confirmTillSales() async {
    final confirm = confirmTillSale;
    if (confirm == null) return (0, const <TillSaleAttention>[]);
    final rows = await database.query(
      'documents',
      where: 'doctype = ? AND docstatus = 1',
      whereArgs: ['POS Invoice'],
      orderBy: 'created_at ASC',
    );
    var confirmed = 0;
    final attention = <TillSaleAttention>[];
    for (final row in rows) {
      final doc = Document.fromDbRow(row);
      final number = doc.payload['official_number'];
      if (number is String && number.isNotEmpty) continue;
      // Only this till's own sales: another register confirms its own (the
      // server binds a till series to the first device confirming with it).
      if (!await _soldHere(doc.id)) continue;
      final children = await database.query('document_children',
          where: 'parent_id = ?', whereArgs: [doc.id]);
      final hydrated = Document.fromDbRow(row,
          childRows: children.map(ChildRow.fromDbRow).toList());
      final command = buildSubmitCommand(hydrated)..['offline_fiscal'] = true;
      try {
        final response = await confirm(command);
        confirmed++;
        final shortfalls = response['stock_shortfalls'];
        if (shortfalls is List && shortfalls.isNotEmpty) {
          DiagnosticLog.instance.record('pos',
              'Till sale ${doc.id} confirmed with stock shortfalls: ${jsonEncode(shortfalls)}');
        }
      } on CloudHttpException catch (e) {
        if (e.statusCode >= 400 && e.statusCode < 500 && e.statusCode != 429) {
          attention.add(TillSaleAttention(doc.id, e.message));
          DiagnosticLog.instance
              .record('pos', 'Till sale ${doc.id} not confirmed: ${e.message}');
        } else {
          break; // transient: retry the rest next sync
        }
      }
    }
    return (confirmed, attention);
  }

  /// Whether this device submitted [invoiceId] itself (its own submit
  /// mutation is in the local queue) — a till confirms only its own sales.
  Future<bool> _soldHere(String invoiceId) async {
    final rows = await database.query(
      'sync_queue',
      columns: ['device_id'],
      where: 'document_id = ? AND doctype = ? AND type = ?',
      whereArgs: [invoiceId, 'POS Invoice', MutationType.submitDocument.name],
      limit: 1,
    );
    return rows.isNotEmpty && rows.first['device_id'] == localDeviceId;
  }
}
