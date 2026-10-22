import 'dart:convert';
import 'dart:io';

import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common/sqflite.dart';

import '../build_info.dart';
import 'business_summary.dart';

/// File extension of an Atlas Solo backup.
const atlasBackupExtension = 'atlasbackup';

/// Device preferences that travel with a backup. Everything here is a
/// non-secret convenience. Deliberately NOT included: the device id (a second
/// device must never share it, or both would draw the same document
/// numbers), the AI capture API key, the Atlas Team session, and the company
/// sync folder (a path on the old device).
const backedUpPreferenceKeys = [
  'core.theme_mode',
  'databrowser.saved_queries',
  'capture.ai.settings',
];

/// Preferences cleared when a restore replaces the books, so the restored
/// data is never pushed into a shared folder or Team the user did not
/// choose again.
const clearedOnRestorePreferenceKeys = [
  'hub.company_folder',
  'hub.auto_sync',
];

/// Remembers when this device last made a backup.
const lastBackupPreferenceKey = 'atlas.backup.last_at';

/// Atlas Solo's backup and restore, on top of Core's [AtlasBackupService]:
/// Hub paths, the business summary that a restore must reproduce, device
/// preferences, and the guards that keep a restore from clashing with Team
/// or folder sync.
class HubBackup {
  HubBackup({required this.dataDirectory, required this.factory})
      : service = AtlasBackupService(
            workDirectory: p.join(dataDirectory, 'backup-work'));

  final String dataDirectory;
  final DatabaseFactory factory;
  final AtlasBackupService service;

  RestoreTarget get target => atlasRestoreTarget(dataDirectory);

  /// Folder where backups made on this device are written first.
  String get backupsDirectory => p.join(dataDirectory, 'backups');

  String get stagingDirectory => p.join(dataDirectory, 'restore-staging');

  String get safetyCopyDirectory =>
      p.join(dataDirectory, atlasPreRestoreFolderName);

  /// A file name like `atlas-harbour-lane-2026-10-22-1405.atlasbackup`.
  static String suggestedFileName(String? company, DateTime now) {
    final slug = (company ?? 'books')
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    String two(int v) => v.toString().padLeft(2, '0');
    final stamp = '${now.year}-${two(now.month)}-${two(now.day)}-'
        '${two(now.hour)}${two(now.minute)}';
    return 'atlas-${slug.isEmpty ? 'books' : slug}-$stamp.$atlasBackupExtension';
  }

  /// Back up the live books to [outputPath] (default: the device backups
  /// folder). [preferences] are included as `config/preferences.json`.
  Future<BackupReport> createBackup({
    required Database database,
    required String passphrase,
    String? outputPath,
    Map<String, Object?> preferences = const {},
    BackupKdfParams? kdf,
  }) async {
    // Only names the file. The recorded summary is computed from the
    // snapshot itself (summarizeSnapshot), so a write made while the backup
    // runs cannot make it disagree with the books it describes.
    final companies = await BusinessSummary.companies(database);
    final out = outputPath ??
        p.join(backupsDirectory,
            suggestedFileName(companies.isEmpty ? null : companies.first,
                DateTime.now()));
    return service.createBackup(
      BackupRequest(
        database: database,
        factory: factory,
        producer: 'Neuradix Atlas',
        appVersion: '${BuildInfo.appVersion} (${BuildInfo.commit})',
        attachmentsRoot: target.attachmentsRoot,
        configFiles: {
          'preferences.json': utf8.encode(jsonEncode(preferences)),
        },
        summarizeSnapshot: BusinessSummary.compute,
      ),
      outputPath: out,
      passphrase: passphrase,
      kdf: kdf,
    );
  }

  /// Decrypt and verify [backupPath] into the staging folder. Nothing live
  /// changes.
  Future<StagedRestore> stage(String backupPath, String passphrase) =>
      service.stageRestore(
        backupPath: backupPath,
        passphrase: passphrase,
        stagingDirectory: stagingDirectory,
        factory: factory,
      );

  /// Swap the staged books in. The live database must already be closed.
  /// Verification re-computes the [BusinessSummary] from the installed file
  /// and requires it to equal the one recorded at backup time, to the cent.
  Future<RestoreOutcome> commit(StagedRestore staged,
          {Future<void> Function(RestoreStep step)? onStep}) =>
      service.commitRestore(
        staged,
        target,
        factory: factory,
        safetyCopyDirectory: safetyCopyDirectory,
        onStep: onStep,
        verifyInstalled: (dbPath) async {
          final db = await factory.openDatabase(dbPath,
              options: OpenDatabaseOptions(singleInstance: false));
          try {
            return BusinessSummary.differences(
                staged.businessSummary, await BusinessSummary.compute(db));
          } finally {
            await db.close();
          }
        },
      );

  /// Read the whitelisted preferences for a backup.
  static Future<Map<String, Object?>> readPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return {
        for (final k in backedUpPreferenceKeys)
          if (prefs.get(k) != null) k: prefs.get(k),
      };
    } catch (_) {
      return const {};
    }
  }

  /// Apply restored preferences and clear the sync settings that must be
  /// chosen again after a restore.
  /// Turns folder sync off before a restore commits, so that if the app
  /// dies after the restored books are installed, the next start cannot sync
  /// them into the previous shared folder. Returns the values to give back
  /// with [resumeFolderSync] if the restore does not go ahead.
  static Future<Map<String, Object>> suspendFolderSync() async {
    final saved = <String, Object>{};
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final k in clearedOnRestorePreferenceKeys) {
        final v = prefs.get(k);
        if (v != null) saved[k] = v;
        await prefs.remove(k);
      }
    } catch (_) {
      // No preferences platform (tests).
    }
    return saved;
  }

  /// Puts back what [suspendFolderSync] turned off (the previous books are
  /// still installed).
  static Future<void> resumeFolderSync(Map<String, Object> saved) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final e in saved.entries) {
        final v = e.value;
        if (v is String) await prefs.setString(e.key, v);
        if (v is bool) await prefs.setBool(e.key, v);
        if (v is int) await prefs.setInt(e.key, v);
        if (v is double) await prefs.setDouble(e.key, v);
        if (v is List) {
          await prefs.setStringList(e.key, [for (final s in v) '$s']);
        }
      }
    } catch (_) {
      // No preferences platform (tests).
    }
  }

  static Future<void> applyRestoredPreferences(StagedRestore staged) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final k in clearedOnRestorePreferenceKeys) {
        await prefs.remove(k);
      }
      final raw = staged.configFiles['preferences.json'];
      if (raw == null) return;
      final map = jsonDecode(utf8.decode(raw));
      if (map is! Map) return;
      for (final entry in map.entries) {
        final key = '${entry.key}';
        if (!backedUpPreferenceKeys.contains(key)) continue;
        final v = entry.value;
        if (v is String) await prefs.setString(key, v);
        if (v is bool) await prefs.setBool(key, v);
        if (v is int) await prefs.setInt(key, v);
        if (v is double) await prefs.setDouble(key, v);
        if (v is List) await prefs.setStringList(key, [for (final s in v) '$s']);
      }
    } catch (_) {
      // No preferences platform (tests): the books restore regardless.
    }
  }

  static Future<DateTime?> lastBackupAt() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getString(lastBackupPreferenceKey);
      return v == null ? null : DateTime.tryParse(v);
    } catch (_) {
      return null;
    }
  }

  static Future<void> recordBackup(DateTime at) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(lastBackupPreferenceKey, at.toIso8601String());
    } catch (_) {}
  }

  /// Backups already in this device's backups folder, newest first.
  List<File> localBackups() {
    final dir = Directory(backupsDirectory);
    if (!dir.existsSync()) return const [];
    final files = [
      for (final f in dir.listSync().whereType<File>())
        if (f.path.endsWith('.$atlasBackupExtension')) f,
    ]..sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
    return files;
  }
}
