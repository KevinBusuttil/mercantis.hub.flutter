import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart'
    show
        atlasDatabaseFileName,
        atlasPreRestoreFolderName,
        atlasRestoreJournalFolderName;
import 'package:path/path.dart' as p;
import 'package:sqflite_common/sqflite.dart';

import '../build_info.dart';
import '../settings/hub_settings.dart';
import '../sync/company_sync.dart';
import 'diagnostic_log.dart';

/// A support diagnostics bundle (plan M1.6): enough to diagnose a support
/// case without asking the customer to open SQLite or install developer
/// tools, and nothing more.
///
/// What it contains: build, platform, schema version, enabled modules,
/// record COUNTS, posting/sync/backup/recovery status and recent redacted
/// errors.
///
/// What it never contains: company, customer or supplier names, document
/// contents, amounts, balances, attachments, file paths, folder or server
/// addresses, the device id itself, passcodes, passphrases or API keys.
/// `test/support_diagnostics_test.dart` enforces this on a populated book.
class DiagnosticsReport {
  DiagnosticsReport({
    required this.diagnosticId,
    required this.generatedAt,
    required this.sections,
  });

  /// Random id the customer quotes so support can match the bundle to a case.
  final String diagnosticId;
  final DateTime generatedAt;

  /// Section title → ordered key/value pairs. Values are strings, numbers,
  /// booleans or lists of strings.
  final Map<String, Map<String, Object?>> sections;

  Map<String, Object?> toJson() => {
        'format': 'atlas-diagnostics/1',
        'diagnostic_id': diagnosticId,
        'generated_at': generatedAt.toUtc().toIso8601String(),
        'sections': sections,
      };

  String toPrettyJson() => const JsonEncoder.withIndent('  ').convert(toJson());

  /// Plain text a customer can read before sending, and paste into an e-mail.
  String toText() {
    final b = StringBuffer()
      ..writeln('Neuradix Atlas support diagnostics')
      ..writeln('Diagnostic id: $diagnosticId')
      ..writeln('Generated: ${generatedAt.toUtc().toIso8601String()}')
      ..writeln('Contains no customer names, amounts, documents or '
          'passwords.');
    for (final section in sections.entries) {
      b
        ..writeln()
        ..writeln('== ${section.key} ==');
      for (final e in section.value.entries) {
        final v = e.value;
        if (v is List) {
          b.writeln('${e.key}:');
          for (final item in v) {
            b.writeln('  - ${'$item'.replaceAll('\n', '\n    ')}');
          }
        } else {
          b.writeln('${e.key}: ${v ?? '—'}');
        }
      }
    }
    return b.toString();
  }

  /// A file name like `atlas-diagnostics-20261022-1405-ab12cd.txt`.
  String get suggestedFileName {
    final t = generatedAt.toUtc();
    String two(int v) => v.toString().padLeft(2, '0');
    return 'atlas-diagnostics-${t.year}${two(t.month)}${two(t.day)}-'
        '${two(t.hour)}${two(t.minute)}-${diagnosticId.substring(0, 6)}.txt';
  }
}

class SupportDiagnostics {
  const SupportDiagnostics._();

  /// Collect a report. Every input is optional so a report can be produced
  /// even when boot failed before the database opened. Each probe is
  /// isolated: one that fails reports its own error instead of aborting the
  /// bundle.
  static Future<DiagnosticsReport> collect({
    Database? database,
    String? dataDirectory,
    HubSettings? settings,
    SyncStatus? sync,
    String? deviceId,
    DateTime? lastBackupAt,
    int? localBackupCount,
    String? bootError,
    List<DiagnosticEvent> events = const [],
    DateTime? now,
    bool includeIntegrityCheck = true,
  }) async {
    final at = now ?? DateTime.now();
    final sections = <String, Map<String, Object?>>{};

    sections['Application'] = {
      'version': BuildInfo.appVersion,
      'commit': BuildInfo.commitLabel,
      if (BuildInfo.ref.isNotEmpty) 'branch': BuildInfo.ref,
      if (BuildInfo.buildTime.isNotEmpty) 'built': BuildInfo.buildTime,
      'build mode': kReleaseMode
          ? 'release'
          : kProfileMode
              ? 'profile'
              : 'debug',
      if (bootError != null)
        'start-up error': DiagnosticRedactor.redact(bootError),
    };

    sections['Platform'] = await _probe(() async => {
          'operating system': Platform.operatingSystem,
          'os version': Platform.operatingSystemVersion,
          'dart': Platform.version.split(' ').first,
          'locale': Platform.localeName,
          'processors': Platform.numberOfProcessors,
          if (deviceId != null && deviceId.isNotEmpty)
            // A one-way fingerprint: enough to tell two devices apart in a
            // numbering case, useless for anything else.
            'device fingerprint':
                sha256.convert(utf8.encode(deviceId)).toString().substring(0, 8),
        });

    if (database != null) {
      sections['Database'] = await _probe(() => _database(
          database, dataDirectory,
          includeIntegrityCheck: includeIntegrityCheck));
      sections['Postings'] = await _probe(() => _postings(database));
      sections['Records'] = await _probe(() => _records(database));
    } else {
      sections['Database'] = {'status': 'not open'};
    }

    if (settings != null) {
      sections['Business setup'] = {
        'business type': settings.businessPresetId.isEmpty
            ? '(not set)'
            : settings.businessPresetId,
        'view': settings.userMode.title,
        'classic navigation': settings.classicNavigation,
        'enabled features': [
          for (final f in settings.features.toList()
            ..sort((a, b) => a.name.compareTo(b.name)))
            f.label,
        ],
      };
    }

    sections['Backup & recovery'] = await _probe(() async => {
          'last backup': lastBackupAt == null
              ? 'never on this device'
              : '${lastBackupAt.toUtc().toIso8601String()} '
                  '(${at.difference(lastBackupAt).inDays} days ago)',
          if (localBackupCount != null)
            'backups kept on this device': localBackupCount,
          if (dataDirectory != null) ...{
            'interrupted restore pending': Directory(
                    p.join(dataDirectory, atlasRestoreJournalFolderName))
                .existsSync(),
            'pre-restore safety copy present': Directory(
                    p.join(dataDirectory, atlasPreRestoreFolderName))
                .existsSync(),
          },
        });

    sections['Sync'] = sync == null
        ? {'mode': 'unknown'}
        : {
            'mode': sync.teamConnected
                ? 'Atlas Team'
                : sync.connected
                    ? 'shared folder'
                    : 'this device only (Solo)',
            if (sync.connected) ...{
              'automatic sync': sync.autoEnabled,
              'state': sync.phase.name,
              'changes waiting to send': sync.pending,
              'changes rejected': sync.failed,
              'last synced': sync.lastSyncedAt?.toUtc().toIso8601String() ??
                  'never',
              if (sync.message != null)
                'last message': DiagnosticRedactor.redact(sync.message!),
            },
          };

    final recent = events.reversed.take(20).toList();
    sections['Recent errors'] = {
      'count kept on device': events.length,
      'latest (newest first)': [
        for (final e in recent)
          '${e.at.toUtc().toIso8601String()} [${e.source}] ${e.message}'
              '${e.stack == null ? '' : '\n${e.stack!.split('\n').take(4).join('\n')}'}',
      ],
    };

    return DiagnosticsReport(
      diagnosticId: _newId(),
      generatedAt: at,
      sections: sections,
    );
  }

  static Future<Map<String, Object?>> _database(
      Database db, String? dataDirectory,
      {required bool includeIntegrityCheck}) async {
    final version = await MigrationRunner.schemaVersion(db);
    final out = <String, Object?>{
      'schema version': version,
      'newest schema this build supports': MigrationRunner.latestVersion,
    };
    if (dataDirectory != null) {
      final file = File(p.join(dataDirectory, atlasDatabaseFileName));
      if (file.existsSync()) out['file size'] = _size(file.lengthSync());
    }
    final journal = await db.rawQuery('PRAGMA journal_mode');
    out['journal mode'] = journal.isEmpty ? null : journal.first.values.first;
    if (includeIntegrityCheck) {
      final check = await db.rawQuery('PRAGMA quick_check');
      final verdict = check.map((r) => '${r.values.first}').toList();
      out['integrity'] = verdict.length == 1 && verdict.first == 'ok'
          ? 'ok'
          : 'PROBLEMS FOUND (${verdict.length})';
    }
    final att = await db.rawQuery(
        'SELECT COUNT(*) AS n, COALESCE(SUM(byte_size), 0) AS bytes FROM attachments');
    out['attachments'] =
        '${att.first['n']} (${_size((att.first['bytes'] as num).toInt())})';
    return out;
  }

  static Future<Map<String, Object?>> _postings(Database db) async {
    final rows = await db.rawQuery(
        'SELECT status, COUNT(*) AS n FROM posting_batches GROUP BY status');
    final byStatus = {for (final r in rows) '${r['status']}': r['n']};
    final failed = await db.rawQuery(
        'SELECT error_code, COUNT(*) AS n FROM posting_batches '
        "WHERE status = 'failed' GROUP BY error_code");
    final queue = await db.rawQuery(
        'SELECT status, COUNT(*) AS n FROM sync_queue GROUP BY status');
    final conflicts =
        await db.rawQuery('SELECT COUNT(*) AS n FROM sync_conflicts');
    return {
      'posting batches by status': [
        for (final e in byStatus.entries) '${e.key}: ${e.value}',
      ],
      'postings owed (failed)': byStatus['failed'] ?? 0,
      // Pending is normal for a moment after a submit; one that stays
      // pending is completed at the next start.
      'postings pending': byStatus['pending'] ?? 0,
      'failure codes': [
        for (final r in failed) '${r['error_code'] ?? 'unknown'}: ${r['n']}',
      ],
      'change log by status': [
        for (final r in queue) '${r['status']}: ${r['n']}',
      ],
      'unresolved sync conflicts': conflicts.first['n'],
    };
  }

  static Future<Map<String, Object?>> _records(Database db) async {
    final rows = await db.rawQuery(
        'SELECT doctype, docstatus, COUNT(*) AS n FROM documents '
        'GROUP BY doctype, docstatus ORDER BY doctype, docstatus');
    final perType = <String, List<String>>{};
    var total = 0;
    for (final r in rows) {
      final n = (r['n'] as num).toInt();
      total += n;
      final state = switch (r['docstatus']) {
        0 => 'draft/master',
        1 => 'submitted',
        2 => 'cancelled',
        final other => 'status $other',
      };
      perType.putIfAbsent('${r['doctype']}', () => []).add('$state $n');
    }
    return {
      'total records': total,
      'by type': [
        for (final e in perType.entries) '${e.key}: ${e.value.join(', ')}',
      ],
    };
  }

  static Future<Map<String, Object?>> _probe(
      Future<Map<String, Object?>> Function() body) async {
    try {
      return await body();
    } catch (e) {
      return {'error': DiagnosticRedactor.redact('$e')};
    }
  }

  static String _size(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  static String _newId() {
    final rng = Random.secure();
    return List.generate(
        12, (_) => rng.nextInt(36).toRadixString(36)).join().toUpperCase();
  }
}
