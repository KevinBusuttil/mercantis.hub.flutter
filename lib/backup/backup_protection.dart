import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common/sqflite.dart';

import 'business_summary.dart';
import 'hub_backup.dart';

/// Where the device key for automatic backups lives. Production uses the
/// platform's secure storage (Android Keystore-backed encrypted storage,
/// iOS/macOS Keychain, Windows Credential Manager, libsecret on Linux).
abstract class BackupKeyStore {
  Future<List<int>?> read();
  Future<void> write(List<int> key);
  Future<void> delete();
}

class SecureBackupKeyStore implements BackupKeyStore {
  SecureBackupKeyStore([FlutterSecureStorage? storage])
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  static const _key = 'atlas.backup.device_key.v1';
  final FlutterSecureStorage _storage;

  @override
  Future<List<int>?> read() async {
    final v = await _storage.read(key: _key);
    if (v == null || v.isEmpty) return null;
    return base64Decode(v);
  }

  @override
  Future<void> write(List<int> key) =>
      _storage.write(key: _key, value: base64Encode(key));

  @override
  Future<void> delete() => _storage.delete(key: _key);
}

/// For tests, and to model a device whose secure storage was wiped.
class MemoryBackupKeyStore implements BackupKeyStore {
  List<int>? key;
  bool failWrites = false;

  @override
  Future<List<int>?> read() async => key;

  @override
  Future<void> write(List<int> k) async {
    if (failWrites) throw StateError('secure storage unavailable');
    key = List.of(k);
  }

  @override
  Future<void> delete() async => key = null;
}

/// The operator's automatic-backup choices. Stored in device preferences:
/// nothing here is secret.
class BackupProtectionPolicy {
  const BackupProtectionPolicy({
    this.enabled = false,
    this.destination,
    this.intervalHours = defaultIntervalHours,
    this.keep = defaultKeep,
  });

  static const defaultIntervalHours = 24;
  static const defaultKeep = 14;

  final bool enabled;

  /// A folder outside Atlas's private data (a USB drive, a cloud-synced
  /// folder, `Documents/Atlas Backups` on Android).
  final String? destination;
  final int intervalHours;

  /// Automatic backups kept in the destination; older ones are removed.
  /// Backups made by hand are never removed.
  final int keep;

  Duration get interval => Duration(hours: intervalHours);

  BackupProtectionPolicy copyWith(
          {bool? enabled, String? destination, int? intervalHours, int? keep}) =>
      BackupProtectionPolicy(
        enabled: enabled ?? this.enabled,
        destination: destination ?? this.destination,
        intervalHours: intervalHours ?? this.intervalHours,
        keep: keep ?? this.keep,
      );

  Map<String, Object?> toJson() => {
        'enabled': enabled,
        'destination': destination,
        'interval_hours': intervalHours,
        'keep': keep,
      };

  factory BackupProtectionPolicy.fromJson(Map<String, Object?> j) =>
      BackupProtectionPolicy(
        enabled: j['enabled'] == true,
        destination: j['destination'] as String?,
        intervalHours: ((j['interval_hours'] as int?) ?? defaultIntervalHours)
            .clamp(1, 24 * 7),
        keep: ((j['keep'] as int?) ?? defaultKeep).clamp(2, 365),
      );
}

/// Why an automatic backup did not complete. Codes are stable (support,
/// diagnostics); messages are for the operator.
enum BackupFailure {
  destinationMissing('The backup folder cannot be reached. Reconnect the '
      'drive or choose the folder again.'),
  permissionDenied('Atlas is not allowed to write to the backup folder. '
      'Choose the folder again.'),
  noSpace('There is not enough free space for the backup. Free some space or '
      'choose another folder.'),
  keyMissing('The backup key on this device is missing. Enter the recovery '
      'passphrase to resume automatic backups.'),
  busy('Another backup is still running.'),
  failed('The backup did not complete. Nothing was saved; Atlas will try '
      'again.');

  const BackupFailure(this.message);
  final String message;
}

class BackupProtectionState {
  const BackupProtectionState({
    this.lastSuccessAt,
    this.lastFile,
    this.lastBytes,
    this.lastAttemptAt,
    this.lastFailure,
    this.lastFailureDetail,
    this.consecutiveFailures = 0,
  });

  final DateTime? lastSuccessAt;
  final String? lastFile;
  final int? lastBytes;
  final DateTime? lastAttemptAt;
  final BackupFailure? lastFailure;
  final String? lastFailureDetail;
  final int consecutiveFailures;

  Map<String, Object?> toJson() => {
        'last_success_at': lastSuccessAt?.toUtc().toIso8601String(),
        'last_file': lastFile,
        'last_bytes': lastBytes,
        'last_attempt_at': lastAttemptAt?.toUtc().toIso8601String(),
        'last_failure': lastFailure?.name,
        'last_failure_detail': lastFailureDetail,
        'consecutive_failures': consecutiveFailures,
      };

  factory BackupProtectionState.fromJson(Map<String, Object?> j) {
    final f = j['last_failure'];
    return BackupProtectionState(
      lastSuccessAt: DateTime.tryParse('${j['last_success_at']}'),
      lastFile: j['last_file'] as String?,
      lastBytes: j['last_bytes'] as int?,
      lastAttemptAt: DateTime.tryParse('${j['last_attempt_at']}'),
      lastFailure: _failureNamed(f),
      lastFailureDetail: j['last_failure_detail'] as String?,
      consecutiveFailures: (j['consecutive_failures'] as int?) ?? 0,
    );
  }
}

BackupFailure? _failureNamed(Object? name) {
  for (final v in BackupFailure.values) {
    if (v.name == name) return v;
  }
  return null;
}

/// How protected the books are right now.
enum BackupFreshness {
  /// Automatic backup is off.
  off,

  /// The last automatic backup is within the interval.
  fresh,

  /// The interval has passed; the next run (start, resume or the hourly
  /// check while Atlas is open) will back up.
  due,

  /// No good backup for more than twice the interval (or 7 days).
  overdue,

  /// The last attempt failed (see the failure).
  failing,
}

class BackupRunResult {
  const BackupRunResult._(this.ran, this.report, this.failure, this.detail);
  const BackupRunResult.notDue() : this._(false, null, null, null);
  const BackupRunResult.done(BackupReport r) : this._(true, r, null, null);
  const BackupRunResult.failed(BackupFailure f, String detail)
      : this._(true, null, f, detail);

  final bool ran;
  final BackupReport? report;
  final BackupFailure? failure;
  final String? detail;
  bool get ok => ran && failure == null;
}

/// Automatic, encrypted backup to a folder the operator chose (R2).
///
/// **Guarantees, honestly:** a backup runs when Atlas starts, when it comes
/// back to the foreground, and every hour while it is open, whenever the
/// interval has passed. It does **not** run while Atlas is closed: Android
/// and iOS do not reliably run an app's code in the background, and a backup
/// must not race the books from a second process. The freshness status and
/// diagnostics say when the last good backup was made.
///
/// **Encryption:** each automatic backup is format 2 (Core
/// [BackupKeyring]). A random device key in secure storage encrypts it; a
/// slot in every file holds that key encrypted under the recovery
/// passphrase, so a replacement device restores with the passphrase alone.
/// If secure storage is unavailable, automatic backup does not run: it never
/// falls back to an unencrypted file.
class BackupProtectionService {
  BackupProtectionService({
    required this.backup,
    required this.database,
    required this.keys,
    DateTime Function()? clock,
    this.kdf,
  }) : _clock = clock ?? DateTime.now;

  final HubBackup backup;
  final Future<Database> Function() database;
  final BackupKeyStore keys;
  final DateTime Function() _clock;

  /// Test hook: cheaper Argon2 parameters.
  final BackupKdfParams? kdf;

  static const policyKey = 'atlas.backup.protection.policy';
  static const stateKey = 'atlas.backup.protection.state';
  static const slotKey = 'atlas.backup.protection.recovery_slot';
  static const filePrefix = 'atlas-auto-';
  static final _ours =
      RegExp(r'^atlas-auto-[a-z0-9-]+-\d{8}-\d{6}\.atlasbackup$');

  /// How long a lock may sit before it is treated as left by a crash.
  static const staleLock = Duration(hours: 2);

  Future<void>? _running;

  // ------------------------------------------------------------ settings

  Future<BackupProtectionPolicy> policy() async {
    final raw = (await SharedPreferences.getInstance()).getString(policyKey);
    if (raw == null) return const BackupProtectionPolicy();
    try {
      return BackupProtectionPolicy.fromJson(
          Map<String, Object?>.from(jsonDecode(raw) as Map));
    } catch (_) {
      return const BackupProtectionPolicy();
    }
  }

  Future<void> _savePolicy(BackupProtectionPolicy p) async =>
      (await SharedPreferences.getInstance())
          .setString(policyKey, jsonEncode(p.toJson()));

  Future<BackupProtectionState> state() async {
    final raw = (await SharedPreferences.getInstance()).getString(stateKey);
    if (raw == null) return const BackupProtectionState();
    try {
      return BackupProtectionState.fromJson(
          Map<String, Object?>.from(jsonDecode(raw) as Map));
    } catch (_) {
      return const BackupProtectionState();
    }
  }

  Future<void> _saveState(BackupProtectionState s) async =>
      (await SharedPreferences.getInstance())
          .setString(stateKey, jsonEncode(s.toJson()));

  Future<BackupRecoverySlot?> recoverySlot() async {
    final raw = (await SharedPreferences.getInstance()).getString(slotKey);
    if (raw == null) return null;
    try {
      return BackupRecoverySlot.fromJson(
          Map<String, Object?>.from(jsonDecode(raw) as Map));
    } catch (_) {
      return null;
    }
  }

  /// The keyring, or null when the key is missing from secure storage or no
  /// longer matches the recovery slot.
  Future<BackupKeyring?> keyring() async {
    final slot = await recoverySlot();
    if (slot == null) return null;
    try {
      final key = await keys.read();
      if (key == null) return null;
      return BackupKeyring(deviceKey: key, recovery: slot);
    } catch (_) {
      return null;
    }
  }

  // ------------------------------------------------------------ set-up

  /// Switch automatic backup on: check the folder, make the device key and
  /// its recovery slot, prove secure storage holds the key, then make the
  /// first backup. Throws [BackupProtectionException] and changes nothing
  /// if any step fails.
  Future<BackupRunResult> enable({
    required String destination,
    required String passphrase,
    int intervalHours = BackupProtectionPolicy.defaultIntervalHours,
    int keep = BackupProtectionPolicy.defaultKeep,
  }) async {
    final problem = await probeDestination(destination, backup.dataDirectory);
    if (problem != null) throw BackupProtectionException(problem);
    BackupCipher.checkPassphrase(passphrase);
    final ring = await BackupKeyring.create(passphrase, kdf: kdf);
    try {
      await keys.write(ring.deviceKey);
      final back = await keys.read();
      if (back == null || base64Encode(back) != base64Encode(ring.deviceKey)) {
        throw StateError('secure storage did not return the key');
      }
    } catch (e) {
      throw BackupProtectionException(BackupFailure.keyMissing,
          'Secure storage on this device is not available ($e). Automatic '
          'backup stays off; Atlas never writes an unencrypted backup.');
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(slotKey, jsonEncode(ring.recovery.toJson()));
    await _savePolicy(BackupProtectionPolicy(
        enabled: true,
        destination: destination,
        intervalHours: intervalHours,
        keep: keep));
    return runIfDue(force: true);
  }

  Future<void> disable() async {
    final p = await policy();
    await _savePolicy(p.copyWith(enabled: false));
  }

  Future<void> changeDestination(String destination) async {
    final problem = await probeDestination(destination, backup.dataDirectory);
    if (problem != null) throw BackupProtectionException(problem);
    await _savePolicy((await policy()).copyWith(destination: destination));
  }

  Future<void> changeSchedule({int? intervalHours, int? keep}) async =>
      _savePolicy((await policy())
          .copyWith(intervalHours: intervalHours, keep: keep));

  /// Secure storage lost the key (OS reset, restored phone): recover it
  /// from the slot with the recovery passphrase.
  Future<void> recoverKey(String passphrase) async {
    final slot = await recoverySlot();
    if (slot == null) {
      throw const BackupProtectionException(BackupFailure.keyMissing,
          'Automatic backup has not been set up on this device.');
    }
    final key = await slot.unwrap(passphrase);
    await keys.write(key);
  }

  /// Make a new recovery slot under a new passphrase. Backups made before
  /// keep opening with the old passphrase.
  Future<void> changePassphrase(String newPassphrase) async {
    final ring = await keyring();
    if (ring == null) {
      throw const BackupProtectionException(BackupFailure.keyMissing);
    }
    final slot =
        await BackupRecoverySlot.wrap(newPassphrase, ring.deviceKey, kdf: kdf);
    await (await SharedPreferences.getInstance())
        .setString(slotKey, jsonEncode(slot.toJson()));
  }

  // ------------------------------------------------------------ status

  Future<BackupFreshness> freshness() async =>
      freshnessOf(await policy(), await state(), _clock());

  static BackupFreshness freshnessOf(
      BackupProtectionPolicy p, BackupProtectionState s, DateTime now) {
    if (!p.enabled) return BackupFreshness.off;
    final last = s.lastSuccessAt;
    final overdueAfter = p.interval * 2 < const Duration(days: 7)
        ? p.interval * 2
        : const Duration(days: 7);
    if (last == null || now.difference(last) > overdueAfter) {
      return s.lastFailure != null
          ? BackupFreshness.failing
          : BackupFreshness.overdue;
    }
    if (s.lastFailure != null &&
        s.lastAttemptAt != null &&
        s.lastAttemptAt!.isAfter(last)) {
      return BackupFreshness.failing;
    }
    return now.difference(last) >= p.interval
        ? BackupFreshness.due
        : BackupFreshness.fresh;
  }

  /// Null when [dir] is usable: exists, is outside Atlas's data folder, and
  /// a file can be written, read back and removed.
  static Future<BackupFailure?> probeDestination(
      String dir, String dataDirectory) async {
    final d = Directory(dir);
    if (!d.existsSync()) return BackupFailure.destinationMissing;
    final norm = p.normalize(p.absolute(dir));
    final data = p.normalize(p.absolute(dataDirectory));
    if (norm == data || p.isWithin(data, norm)) {
      return BackupFailure.permissionDenied;
    }
    final probe = File(p.join(dir,
        '.atlas-probe-${DateTime.now().microsecondsSinceEpoch}.tmp'));
    try {
      await probe.writeAsString('atlas', flush: true);
      final ok = await probe.readAsString() == 'atlas';
      await probe.delete();
      return ok ? null : BackupFailure.failed;
    } on FileSystemException catch (e) {
      if (probe.existsSync()) {
        try {
          probe.deleteSync();
        } catch (_) {}
      }
      return classify(e);
    }
  }

  /// Map an I/O error to what the operator can do about it.
  static BackupFailure classify(Object e) {
    if (e is BackupProtectionException) return e.failure;
    if (e is FileSystemException) {
      final code = e.osError?.errorCode;
      final msg = '${e.osError?.message} ${e.message}'.toLowerCase();
      // ENOSPC 28, EDQUOT 122/69; Windows ERROR_DISK_FULL 112 / 39.
      if (code == 28 ||
          code == 122 ||
          code == 112 ||
          code == 39 ||
          msg.contains('no space') ||
          msg.contains('disk full') ||
          msg.contains('quota')) {
        return BackupFailure.noSpace;
      }
      // EACCES 13, EPERM 1, EROFS 30; Windows ERROR_ACCESS_DENIED 5.
      if (code == 13 ||
          code == 1 ||
          code == 30 ||
          code == 5 ||
          msg.contains('permission') ||
          msg.contains('access is denied') ||
          msg.contains('read-only')) {
        return BackupFailure.permissionDenied;
      }
      // ENOENT 2, ENOTDIR 20, ENXIO 6, EIO 5 on removable media.
      if (code == 2 || code == 20 || code == 6 || msg.contains('no such')) {
        return BackupFailure.destinationMissing;
      }
    }
    return BackupFailure.failed;
  }

  // ------------------------------------------------------------ running

  /// Back up when automatic backup is on and the interval has passed (or
  /// [force]). Never runs two at once, in this process or another.
  Future<BackupRunResult> runIfDue({bool force = false}) async {
    final policy = await this.policy();
    if (!policy.enabled || policy.destination == null) {
      return const BackupRunResult.notDue();
    }
    if (!force) {
      final last = (await state()).lastSuccessAt;
      if (last != null && _clock().difference(last) < policy.interval) {
        return const BackupRunResult.notDue();
      }
    }
    if (_running != null) {
      return const BackupRunResult.failed(
          BackupFailure.busy, 'a backup is already running');
    }
    final done = Completer<void>();
    _running = done.future;
    try {
      return await _run(policy);
    } finally {
      _running = null;
      done.complete();
    }
  }

  File get _lockFile =>
      File(p.join(backup.dataDirectory, 'backup-work', 'auto-backup.lock'));

  bool _takeLock() {
    final lock = _lockFile;
    lock.parent.createSync(recursive: true);
    // File times are wall-clock time, so staleness is too.
    if (lock.existsSync() &&
        DateTime.now().difference(lock.lastModifiedSync()) > staleLock) {
      lock.deleteSync();
    }
    try {
      lock.createSync(exclusive: true);
      lock.writeAsStringSync('$pid ${_clock().toIso8601String()}');
      return true;
    } on FileSystemException {
      return false;
    }
  }

  Future<BackupRunResult> _run(BackupProtectionPolicy policy) async {
    final started = _clock();
    var st = await state();
    if (!_takeLock()) {
      return const BackupRunResult.failed(
          BackupFailure.busy, 'another backup holds the lock');
    }
    try {
      final dest = policy.destination!;
      final ring = await keyring();
      if (ring == null) throw const BackupProtectionException(BackupFailure.keyMissing);
      final problem = await probeDestination(dest, backup.dataDirectory);
      if (problem != null) throw BackupProtectionException(problem);
      _removeStalePartials(dest);

      final db = await database();
      final companies = await BusinessSummary.companies(db);
      final name = autoFileName(companies.isEmpty ? null : companies.first, started);
      final report = await backup.createBackup(
        database: db,
        keyring: ring,
        outputPath: p.join(dest, name),
        preferences: await HubBackup.readPreferences(),
      );
      // createBackup already decrypted and hash-checked the file before
      // naming it. Re-read the header from its final place, so a folder that
      // silently dropped the rename is caught.
      final header = await AtlasBackupService.readHeader(report.path);
      if (header.keyId != ring.keyId) {
        throw StateError('the backup on disk is not the one just written');
      }
      final pruned = prune(dest, policy.keep, keepPath: report.path);
      st = BackupProtectionState(
        lastSuccessAt: started,
        lastFile: report.path,
        lastBytes: report.bytes,
        lastAttemptAt: started,
      );
      await _saveState(st);
      await HubBackup.recordBackup(started);
      return BackupRunResult.done(
          BackupReport(
              path: report.path,
              bytes: report.bytes,
              manifest: {...report.manifest, 'pruned': pruned},
              missingAttachments: report.missingAttachments));
    } catch (e) {
      final failure = classify(e);
      final detail = e is BackupProtectionException ? e.detail ?? e.failure.message : '$e';
      await _saveState(BackupProtectionState(
        lastSuccessAt: st.lastSuccessAt,
        lastFile: st.lastFile,
        lastBytes: st.lastBytes,
        lastAttemptAt: started,
        lastFailure: failure,
        lastFailureDetail: detail,
        consecutiveFailures: st.consecutiveFailures + 1,
      ));
      return BackupRunResult.failed(failure, detail);
    } finally {
      try {
        _lockFile.deleteSync();
      } catch (_) {}
    }
  }

  /// `atlas-auto-harbour-lane-20261105-141503.atlasbackup`.
  static String autoFileName(String? company, DateTime at) {
    final slug = (company ?? 'books')
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    String two(int v) => v.toString().padLeft(2, '0');
    final l = at.toLocal();
    return '$filePrefix${slug.isEmpty ? 'books' : slug}-'
        '${l.year}${two(l.month)}${two(l.day)}-'
        '${two(l.hour)}${two(l.minute)}${two(l.second)}.$atlasBackupExtension';
  }

  /// Keep the newest [keep] automatic backups in [dir]. Only files Atlas
  /// named as automatic backups are touched; hand-made copies never are.
  /// Returns the paths removed.
  static List<String> prune(String dir, int keep, {String? keepPath}) {
    final mine = [
      for (final f in Directory(dir).listSync().whereType<File>())
        if (_ours.hasMatch(p.basename(f.path))) f,
    ]..sort((a, b) =>
        _stamp(p.basename(b.path)).compareTo(_stamp(p.basename(a.path))));
    final removed = <String>[];
    for (final f in mine.skip(keep)) {
      if (keepPath != null && p.equals(f.path, keepPath)) continue;
      try {
        f.deleteSync();
        removed.add(f.path);
      } catch (_) {
        // A file another install made (Android scoped storage) cannot be
        // removed by this one. It is left, not an error.
      }
    }
    return removed;
  }

  static String _stamp(String name) {
    final m = RegExp(r'-(\d{8}-\d{6})\.atlasbackup$').firstMatch(name);
    return m?.group(1) ?? '';
  }

  void _removeStalePartials(String dir) {
    for (final f in Directory(dir).listSync().whereType<File>()) {
      final n = p.basename(f.path);
      if (n.startsWith(filePrefix) && n.endsWith('.atlasbackup.partial')) {
        try {
          f.deleteSync();
        } catch (_) {}
      }
    }
  }
}

class BackupProtectionException implements Exception {
  const BackupProtectionException(this.failure, [this.detail]);
  final BackupFailure failure;
  final String? detail;

  @override
  String toString() => detail ?? failure.message;
}
