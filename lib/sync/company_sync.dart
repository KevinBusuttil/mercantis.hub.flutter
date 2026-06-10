import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ledger/ledger_derivation_service.dart';
import '../numbering/numbering_series.dart';
import '../screens/screen_providers.dart';

/// Where the shared company folder path is remembered. This is device-local
/// (each device mounts the same iCloud/Dropbox/OneDrive folder at its own path)
/// so it lives in shared_preferences, never in a synced document.
const _folderKey = 'hub.company_folder';

enum SyncPhase { idle, syncing, error }

/// A snapshot of the company-sync state for the UI.
class SyncStatus {
  const SyncStatus({
    this.folder,
    required this.deviceId,
    this.phase = SyncPhase.idle,
    this.pending = 0,
    this.lastSyncedAt,
    this.lastPushed = 0,
    this.lastPulled = 0,
    this.message,
  });

  /// The connected shared folder, or null when not joined to a company.
  final String? folder;
  final String deviceId;
  final SyncPhase phase;

  /// Local changes still waiting to be pushed.
  final int pending;
  final DateTime? lastSyncedAt;
  final int lastPushed;
  final int lastPulled;
  final String? message;

  bool get connected => folder != null && folder!.isNotEmpty;

  SyncStatus copyWith({
    String? folder,
    SyncPhase? phase,
    int? pending,
    DateTime? lastSyncedAt,
    int? lastPushed,
    int? lastPulled,
    String? message,
  }) =>
      SyncStatus(
        folder: folder ?? this.folder,
        deviceId: deviceId,
        phase: phase ?? this.phase,
        pending: pending ?? this.pending,
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
class CompanySyncNotifier extends AsyncNotifier<SyncStatus> {
  @override
  Future<SyncStatus> build() async {
    final deviceId = await ref.read(deviceIdProvider.future);
    final prefs = await SharedPreferences.getInstance();
    return SyncStatus(
      folder: prefs.getString(_folderKey),
      deviceId: deviceId,
      pending: await _pendingCount(),
    );
  }

  Future<int> _pendingCount() async {
    final db = (await ref.read(mercantisDatabaseProvider.future)).db;
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM sync_queue WHERE status = ?',
      [MutationStatus.pending.name],
    );
    return (rows.first['c'] as int?) ?? 0;
  }

  /// Connect (or switch) the company folder and run an initial exchange.
  Future<void> connect(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_folderKey, path);
    final base = state.valueOrNull;
    if (base != null) state = AsyncData(base.copyWith(folder: path));
    await syncNow();
  }

  /// Forget the company folder (stops syncing; local data stays).
  Future<void> disconnect() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_folderKey);
    final base = state.valueOrNull;
    if (base != null) {
      state = AsyncData(SyncStatus(deviceId: base.deviceId, pending: base.pending));
    }
  }

  Future<void> syncNow() async {
    final current = state.valueOrNull;
    if (current == null || !current.connected) return;
    state = AsyncData(current.copyWith(phase: SyncPhase.syncing, message: null));

    try {
      final db = (await ref.read(mercantisDatabaseProvider.future)).db;
      final registry = await ref.read(metadataRegistryProvider.future);
      final adapter = await FileSystemCloudAdapter.create(
        root: Directory(current.folder!),
        localDeviceId: current.deviceId,
      );
      final sync = SyncEngine(
        database: db,
        registry: registry,
        cloudAdapter: adapter,
      );

      int pushed = 0;
      int pulled = 0;
      try {
        pushed = await _pendingCount();
        await sync.pushPendingMutations();
        final remote = await adapter.pull(null);
        pulled = remote.length;
        await sync.applyRemoteMutations(remote);
        if (remote.isNotEmpty) {
          final ledger = await ref.read(ledgerDerivationServiceProvider.future);
          await ledger.recomputeAllDerived();
          _refreshData();
        }
        await adapter.acknowledge([for (final m in remote) m.id]);
      } finally {
        sync.dispose();
      }

      state = AsyncData(current.copyWith(
        phase: SyncPhase.idle,
        pending: await _pendingCount(),
        lastSyncedAt: DateTime.now(),
        lastPushed: pushed,
        lastPulled: pulled,
      ));
    } catch (e) {
      final base = state.valueOrNull ?? current;
      state = AsyncData(base.copyWith(phase: SyncPhase.error, message: '$e'));
    }
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
