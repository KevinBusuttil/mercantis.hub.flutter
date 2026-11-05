import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

import '../screens/backup_restore_screen.dart' show hubBackupProvider;
import '../support/diagnostic_log.dart';
import '../team/team_session.dart';
import 'backup_protection.dart';

/// The device's automatic-backup service.
final backupProtectionProvider =
    FutureProvider<BackupProtectionService>((ref) async {
  final backup = await ref.watch(hubBackupProvider.future);
  return BackupProtectionService(
    backup: backup,
    database: () async => (await ref.read(mercantisDatabaseProvider.future)).db,
    keys: SecureBackupKeyStore(),
  );
});

/// Freshness for banners and diagnostics; refreshed after each run.
final backupFreshnessProvider = FutureProvider<
    ({
      BackupFreshness freshness,
      BackupProtectionPolicy policy,
      BackupProtectionState state,
    })>((ref) async {
  final s = await ref.watch(backupProtectionProvider.future);
  final policy = await s.policy();
  final state = await s.state();
  return (
    freshness: BackupProtectionService.freshnessOf(policy, state, DateTime.now()),
    policy: policy,
    state: state,
  );
});

/// Runs automatic backups while Atlas is open: shortly after start, on every
/// return to the foreground, and hourly. Nothing runs while Atlas is closed
/// (see [BackupProtectionService]). Not while connected to Atlas Team: Team
/// books are protected on the server and a device backup of them cannot be
/// restored.
final backupSchedulerProvider = Provider<BackupScheduler>((ref) {
  final s = BackupScheduler(ref);
  ref.onDispose(s.dispose);
  s.start();
  return s;
});

class BackupScheduler with WidgetsBindingObserver {
  BackupScheduler(this._ref);

  final Ref _ref;
  Timer? _timer;
  Timer? _first;
  bool _disposed = false;

  static const startDelay = Duration(seconds: 20);
  static const checkEvery = Duration(hours: 1);

  void start() {
    WidgetsBinding.instance.addObserver(this);
    _first = Timer(startDelay, tick);
    _timer = Timer.periodic(checkEvery, (_) => tick());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) tick();
  }

  Future<void> tick() async {
    if (_disposed || _ref.read(teamSessionProvider) != null) return;
    try {
      final service = await _ref.read(backupProtectionProvider.future);
      final r = await service.runIfDue();
      if (r.ran) _ref.invalidate(backupFreshnessProvider);
      if (r.failure != null && r.failure != BackupFailure.busy) {
        DiagnosticLog.instance
            .record('auto-backup', StateError('${r.failure!.name}: ${r.detail}'));
      }
    } catch (e, s) {
      DiagnosticLog.instance.record('auto-backup', e, s);
    }
  }

  void dispose() {
    _disposed = true;
    _first?.cancel();
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
  }
}
