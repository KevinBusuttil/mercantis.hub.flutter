import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ledger/ledger_derivation_service.dart';
import '../numbering/numbering_series.dart';
import '../screens/screen_providers.dart';
import '../team/team_account_client.dart';
import '../team/team_session.dart';
import '../team/team_sync_runner.dart';

/// Device-local prefs keys (each device mounts the shared folder at its own
/// path, so neither lives in a synced document).
const _folderKey = 'hub.company_folder';
const _autoKey = 'hub.auto_sync';

enum SyncPhase { idle, syncing, error }

/// A snapshot of the company-sync state for the UI.
class SyncStatus {
  const SyncStatus({
    this.folder,
    this.teamCompany,
    required this.deviceId,
    this.autoEnabled = true,
    this.phase = SyncPhase.idle,
    this.pending = 0,
    this.failed = 0,
    this.lastSyncedAt,
    this.lastPushed = 0,
    this.lastPulled = 0,
    this.message,
  });

  /// The connected shared folder, or null when not joined to a company.
  final String? folder;

  /// The Atlas Team company this device syncs with, or null (Team milestone
  /// 3). When set, the Team backend is the transport and the folder — the
  /// Solo transport — is ignored.
  final String? teamCompany;
  final String deviceId;

  /// Whether background sync (timer + on-change + on-resume) is on.
  final bool autoEnabled;
  final SyncPhase phase;

  /// Local changes still waiting to be pushed.
  final int pending;

  /// Changes the server permanently rejected (quarantined until the user
  /// retries them — e.g. an edit to an officially posted document).
  final int failed;
  final DateTime? lastSyncedAt;
  final int lastPushed;
  final int lastPulled;
  final String? message;

  bool get teamConnected => teamCompany != null && teamCompany!.isNotEmpty;
  bool get connected =>
      teamConnected || (folder != null && folder!.isNotEmpty);

  SyncStatus copyWith({
    String? folder,
    String? teamCompany,
    bool? autoEnabled,
    SyncPhase? phase,
    int? pending,
    int? failed,
    DateTime? lastSyncedAt,
    int? lastPushed,
    int? lastPulled,
    String? message,
  }) =>
      SyncStatus(
        folder: folder ?? this.folder,
        teamCompany: teamCompany ?? this.teamCompany,
        deviceId: deviceId,
        autoEnabled: autoEnabled ?? this.autoEnabled,
        phase: phase ?? this.phase,
        pending: pending ?? this.pending,
        failed: failed ?? this.failed,
        lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
        lastPushed: lastPushed ?? this.lastPushed,
        lastPulled: lastPulled ?? this.lastPulled,
        message: message,
      );
}

/// Drives serverless multi-user sync: a shared folder is the "cloud"
/// (FileSystemCloudAdapter, ADR-047). A sync is push local changes → pull
/// peers' changes → re-derive local balances → refresh the UI. The append-only
/// ledgers replicate directly; `Bin`/invoice `outstanding` are recomputed
/// locally after each pull rather than trusted from the wire.
///
/// When connected and auto-sync is on it also syncs in the background: on a
/// timer, shortly after local document changes (debounced), and on app resume.
class CompanySyncNotifier extends AsyncNotifier<SyncStatus> {
  static const _interval = Duration(seconds: 30);
  static const _debounceDelay = Duration(seconds: 3);

  // Mirrors of the persisted state, kept so the background machinery doesn't
  // race the async `state`.
  String? _folder;
  TeamSession? _team;
  bool _autoEnabled = true;

  bool get _transportConnected =>
      _team != null || (_folder != null && _folder!.isNotEmpty);

  Timer? _timer;
  Timer? _debounce;
  final List<SubscriptionToken> _tokens = [];
  AppLifecycleListener? _lifecycle;
  bool _busy = false;

  @override
  Future<SyncStatus> build() async {
    ref.onDispose(_stopAuto);
    // Rebuilds when the device joins/leaves an Atlas Team company, so the
    // transport and the background machinery follow the session.
    _team = ref.watch(teamSessionProvider);
    final deviceId = await ref.read(deviceIdProvider.future);
    final prefs = await SharedPreferences.getInstance();
    _folder = prefs.getString(_folderKey);
    _autoEnabled = prefs.getBool(_autoKey) ?? true;
    final team = _team;
    final status = SyncStatus(
      folder: _folder,
      teamCompany: team == null
          ? null
          : (team.companyName.isEmpty ? team.companyId : team.companyName),
      deviceId: deviceId,
      autoEnabled: _autoEnabled,
      pending: await _pendingCount(),
      failed: await _failedCount(),
    );
    _startAuto();
    return status;
  }

  Future<int> _pendingCount() async {
    final db = (await ref.read(mercantisDatabaseProvider.future)).db;
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM sync_queue WHERE status = ?',
      [MutationStatus.pending.name],
    );
    return (rows.first['c'] as int?) ?? 0;
  }

  Future<int> _failedCount() async {
    final db = (await ref.read(mercantisDatabaseProvider.future)).db;
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM sync_queue WHERE status = ?',
      [MutationStatus.failed.name],
    );
    return (rows.first['c'] as int?) ?? 0;
  }

  /// The explicit user action after a permanent server rejection: requeue
  /// the quarantined changes and try again immediately.
  Future<void> retryFailed() async {
    final db = (await ref.read(mercantisDatabaseProvider.future)).db;
    await db.update(
      'sync_queue',
      {'status': MutationStatus.pending.name},
      where: 'status = ?',
      whereArgs: [MutationStatus.failed.name],
    );
    await syncNow();
  }

  /// Connect (or switch) the company folder and run an initial exchange.
  Future<void> connect(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_folderKey, path);
    _folder = path;
    final base = state.valueOrNull;
    if (base != null) state = AsyncData(base.copyWith(folder: path));
    _startAuto();
    await syncNow();
  }

  /// Forget the company folder (stops syncing; local data stays).
  Future<void> disconnect() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_folderKey);
    _folder = null;
    _stopAuto();
    final base = state.valueOrNull;
    if (base != null) {
      state = AsyncData(SyncStatus(
        deviceId: base.deviceId,
        autoEnabled: _autoEnabled,
        pending: base.pending,
      ));
    }
  }

  /// Turn background sync on/off (persisted).
  Future<void> setAutoEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoKey, enabled);
    _autoEnabled = enabled;
    final base = state.valueOrNull;
    if (base != null) state = AsyncData(base.copyWith(autoEnabled: enabled));
    _startAuto();
  }

  Future<void> syncNow() async {
    final current = state.valueOrNull;
    if (current == null || !current.connected || _busy) return;
    _busy = true;
    state = AsyncData(current.copyWith(phase: SyncPhase.syncing, message: null));

    try {
      final db = (await ref.read(mercantisDatabaseProvider.future)).db;
      final registry = await ref.read(metadataRegistryProvider.future);

      int pushed = 0;
      int pulled = 0;
      int applied = 0;
      final team = _team;
      if (team != null) {
        // Team transport: the backend is the log; the runner filters our own
        // echoes and keeps the pull cursor.
        final adapter = TeamAccountClient.adapterFor(team);
        try {
          final result = await TeamSyncRunner(
            database: db,
            registry: registry,
            adapter: adapter,
            localDeviceId: current.deviceId,
            companyId: team.companyId,
          ).run();
          pushed = result.pushed;
          pulled = result.pulled;
          applied = result.applied;
        } finally {
          adapter.close();
        }
      } else {
        // Solo transport: the shared folder is the log; the adapter itself
        // skips our own subdirectory on pull.
        final adapter = await FileSystemCloudAdapter.create(
          root: Directory(current.folder!),
          localDeviceId: current.deviceId,
        );
        final sync = SyncEngine(
          database: db,
          registry: registry,
          cloudAdapter: adapter,
        );
        try {
          pushed = await _pendingCount();
          await sync.pushPendingMutations();
          final remote = await adapter.pull(null);
          pulled = remote.length;
          applied = remote.length;
          await sync.applyRemoteMutations(remote);
          await adapter.acknowledge([for (final m in remote) m.id]);
        } finally {
          sync.dispose();
        }
      }

      if (applied > 0) {
        // Re-derive balances locally rather than trusting them from the wire.
        final ledger = await ref.read(ledgerDerivationServiceProvider.future);
        await ledger.recomputeAllDerived();
        _refreshData();
      }

      state = AsyncData(current.copyWith(
        phase: SyncPhase.idle,
        pending: await _pendingCount(),
        failed: await _failedCount(),
        lastSyncedAt: DateTime.now(),
        lastPushed: pushed,
        lastPulled: pulled,
      ));
    } catch (e) {
      final base = state.valueOrNull ?? current;
      state = AsyncData(base.copyWith(
          phase: SyncPhase.error,
          message: e is CloudHttpException ? e.message : '$e'));
    } finally {
      _busy = false;
    }
  }

  // ── Background machinery ────────────────────────────────────────────────

  /// (Re)arm the timer, the on-change subscription and the resume hook to match
  /// the current folder + auto-enabled state. Idempotent.
  void _startAuto() {
    _stopAuto();
    if (!_transportConnected || !_autoEnabled) return;

    _timer = Timer.periodic(_interval, (_) => _autoSync());

    final emitter = ref.read(eventEmitterProvider);
    _tokens
      ..add(emitter.subscribe<DocumentSavedEvent>((_) => _scheduleAuto()))
      ..add(emitter.subscribe<DocumentSubmittedEvent>((_) => _scheduleAuto()))
      ..add(emitter.subscribe<DocumentCancelledEvent>((_) => _scheduleAuto()));

    try {
      _lifecycle = AppLifecycleListener(onResume: _autoSync);
    } catch (_) {
      // No widget binding (e.g. unit tests): the timer/events still cover sync.
      _lifecycle = null;
    }
  }

  void _stopAuto() {
    _timer?.cancel();
    _timer = null;
    _debounce?.cancel();
    _debounce = null;
    for (final t in _tokens) {
      t.cancel();
    }
    _tokens.clear();
    _lifecycle?.dispose();
    _lifecycle = null;
  }

  /// Coalesce a burst of local changes (a submit fans out into many ledger
  /// saves) into a single sync shortly after activity settles.
  void _scheduleAuto() {
    if (!_autoEnabled || !_transportConnected) return;
    _debounce?.cancel();
    _debounce = Timer(_debounceDelay, _autoSync);
  }

  void _autoSync() {
    if (!_autoEnabled || !_transportConnected || _busy) return;
    // Fire-and-forget; syncNow owns its own error handling and busy guard.
    unawaited(syncNow());
  }

  /// Invalidate the bespoke data providers so pulled documents surface without
  /// a manual refresh. Generic metadata list/form views re-fetch on navigation.
  void _refreshData() {
    ref.invalidate(salesOrdersProvider);
    ref.invalidate(customerAccountsProvider);
    ref.invalidate(lowStockProvider);
    ref.invalidate(latestDeliveryRouteProvider);
    ref.invalidate(numberingSeriesProvider);
  }
}

final companySyncProvider =
    AsyncNotifierProvider<CompanySyncNotifier, SyncStatus>(
        CompanySyncNotifier.new);
