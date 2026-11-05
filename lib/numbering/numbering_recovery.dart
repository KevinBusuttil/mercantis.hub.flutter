import 'dart:convert';
import 'dart:math';

import 'package:mercantis_core/mercantis_core.dart';
import 'package:sqflite_common/sqflite.dart';

/// Business-facing numbering series: numbers a customer, supplier, tax
/// authority or auditor may hold on paper or in their own books. A restore
/// must never let one of these be issued twice.
///
/// Every other counter series (projects, tasks, internal transfers…) is still
/// advanced from evidence after a restore, but is not put on hold, because
/// a repeated internal number has no meaning outside these books.
const officialNumberingDocTypes = <String>{
  'Sales Invoice', // includes credit notes (is_return)
  'POS Invoice', // till receipts, fiscal receipts
  'Payment Entry', // receipts and payments
  'Customer Deposit',
  'Delivery Note',
  'Quotation',
  'Sales Order',
  'Purchase Order',
  'Purchase Invoice', // own reference for a supplier bill, in the VAT records
  'Purchase Receipt',
  'Expense',
  'Journal Entry',
};

/// Audit trail entries written by numbering recovery use this DocType name
/// (there is no such document; the audit log keys on it).
const numberingAuditDocType = 'Numbering';

/// What a restore did to numbering.
enum NumberingRecoveryMode {
  /// The backup is at least as new as anything this device had issued.
  unchanged,

  /// This device's previous books (same business) proved which numbers were
  /// issued after the backup; the counters were moved past them.
  advancedFromEvidence,

  /// Nothing on this device can prove what was issued after the backup
  /// (new or replacement device, or a different business was here). Official
  /// numbering is on hold until the operator decides.
  holdPendingDecision,
}

class NumberingRecoveryResult {
  const NumberingRecoveryResult({
    required this.mode,
    required this.advanced,
    required this.missingDocuments,
    this.evidence = const [],
  });

  final NumberingRecoveryMode mode;

  /// Series moved, with the number each now continues from.
  final Map<String, int> advanced;

  /// Official documents in the replaced books that are not in the restored
  /// ones: issued after the backup, and now only in the safety copy.
  final List<String> missingDocuments;

  /// Where the evidence came from, for the audit trail and the notice.
  final List<String> evidence;

  Map<String, Object?> toJson() => {
        'mode': mode.name,
        'advanced': advanced,
        'missing_documents': missingDocuments,
        'evidence': evidence,
      };

  /// One paragraph for the restore notice.
  String describe() {
    switch (mode) {
      case NumberingRecoveryMode.unchanged:
        return 'Document numbering continues from the backup.';
      case NumberingRecoveryMode.advancedFromEvidence:
        final missing = missingDocuments.isEmpty
            ? ''
            : ' ${missingDocuments.length} document'
                '${missingDocuments.length == 1 ? ' was' : 's were'} issued '
                'after the backup and are not in the restored books '
                '(${missingDocuments.take(5).join(', ')}'
                '${missingDocuments.length > 5 ? '…' : ''}). Re-enter them '
                'with their original details; they keep their numbers in '
                'the safety copy.';
        return 'Numbers issued on this device after the backup will not be '
            'used again: ${advanced.length} series now continue after the '
            'last number this device issued.$missing';
      case NumberingRecoveryMode.holdPendingDecision:
        return 'Atlas cannot tell which invoice, receipt and payment numbers '
            'were issued after this backup was made. New official documents '
            'are on hold until you confirm the last numbers you issued, or '
            'start a recovery series: Settings › Numbering series.';
    }
  }
}

/// Recovery-safe document numbering after restoring a backup (R3).
///
/// The counters live in the database, so restoring an older backup used to
/// restore older counters and Atlas would issue numbers again that had
/// already gone out. Now, inside the restore's journal (before it commits):
///
/// * If the replaced books on this device are the same business, they are
///   the record of every number issued here after the backup. Each series is
///   moved past the highest of them, and the documents that exist only in
///   the replaced books are listed for re-entry.
/// * Otherwise nothing proves what was issued after the backup, so official
///   numbering is put on hold (enforced by Core's naming policy, so no path
///   can mint around it) until the operator records a decision.
///
/// Both outcomes, and every later decision, are written to the audit log.
abstract final class NumberingRecovery {
  static const _allocator = CounterBlockAllocator();

  /// Restore hook (`prepareInstalled`). [installedPath] holds the verified
  /// restored books; [previousPath] the books they replaced, if any.
  static Future<NumberingRecoveryResult> prepareRestoredBooks({
    required DatabaseFactory factory,
    required String installedPath,
    String? previousPath,
    String deviceId = '',
    String userId = 'restore',
    DateTime? backupCreatedAt,
  }) async {
    final installed = await factory.openDatabase(installedPath,
        options: OpenDatabaseOptions(singleInstance: false));
    try {
      // An older backup may predate the policy table.
      await MigrationRunner.migrate(installed);
      final restoredCompanies = await companies(installed);
      final restoredIssued = await _allocator.issuedThrough(installed);
      final restoredIds = await _officialIds(installed);

      Map<String, int>? previousIssued;
      var missing = <String>[];
      final evidence = <String>[];
      if (previousPath != null) {
        try {
          final prev = await factory.openDatabase(previousPath,
              options: OpenDatabaseOptions(singleInstance: false));
          try {
            final prevCompanies = await companies(prev);
            if (prevCompanies.isNotEmpty &&
                prevCompanies.any(restoredCompanies.contains)) {
              previousIssued = await _allocator.issuedThrough(prev);
              missing = [
                for (final id in await _officialIds(prev))
                  if (!restoredIds.contains(id)) id,
              ]..sort();
              evidence.add('replaced books on this device '
                  '(${prevCompanies.join(', ')})');
            } else if (prevCompanies.isNotEmpty) {
              evidence.add('replaced books belong to a different business '
                  '(${prevCompanies.join(', ')}); not used');
            }
          } finally {
            await prev.close();
          }
        } catch (e) {
          evidence.add('replaced books could not be read ($e)');
        }
      }

      final advanced = <String, int>{};
      if (previousIssued != null) {
        for (final e in previousIssued.entries) {
          if (e.value > (restoredIssued[e.key] ?? 0)) {
            await _allocator.raiseNextNumber(installed, e.key, e.value + 1);
            advanced[e.key] = e.value + 1;
          }
        }
      }

      final NumberingRecoveryMode mode;
      if (previousIssued == null) {
        mode = NumberingRecoveryMode.holdPendingDecision;
        await _hold(installed,
            'Restored from a backup on a device that cannot prove which '
            'numbers were issued after it. Confirm the last numbers issued '
            'or start a recovery series (Settings › Numbering series).');
      } else {
        mode = advanced.isEmpty
            ? NumberingRecoveryMode.unchanged
            : NumberingRecoveryMode.advancedFromEvidence;
      }
      final result = NumberingRecoveryResult(
          mode: mode,
          advanced: advanced,
          missingDocuments: missing,
          evidence: evidence);
      await _audit(installed, 'restore_numbering', userId, deviceId, {
        ...result.toJson(),
        'backup_created_at': backupCreatedAt?.toUtc().toIso8601String(),
        'restored_issued_through': restoredIssued,
      });
      return result;
    } finally {
      await installed.close();
    }
  }

  /// Official DocTypes whose numbering is on hold.
  static Future<List<NamingSeriesPolicy>> holds(DatabaseExecutor db) async => [
        for (final p in await NamingSeriesPolicyStore.all(db))
          if (p.hold) p,
      ];

  /// The active recovery segment, if official numbering moved to one.
  static Future<String?> activeSegment(DatabaseExecutor db) async {
    for (final p in await NamingSeriesPolicyStore.all(db)) {
      if (p.segment.isNotEmpty && officialNumberingDocTypes.contains(p.docType)) {
        return p.segment;
      }
    }
    return null;
  }

  /// Decision 1: the operator has checked their records (the last invoice
  /// sent, the last receipt printed…) and states the last number issued in
  /// each series. Series not mentioned continue from the restored counter.
  /// A number below what the books already hold is refused: that would
  /// re-issue a number.
  static Future<void> confirmLastIssued(
    Database db,
    Map<String, int> lastIssued, {
    required String userId,
    required String deviceId,
  }) async {
    final issued = await _allocator.issuedThrough(db);
    for (final e in lastIssued.entries) {
      if (e.value < (issued[e.key] ?? 0)) {
        throw ArgumentError('${e.key}: the books already hold number '
            '${issued[e.key]}; the last issued number cannot be lower.');
      }
    }
    final moved = <String, int>{};
    for (final e in lastIssued.entries) {
      if (await _allocator.raiseNextNumber(db, e.key, e.value + 1)) {
        moved[e.key] = e.value + 1;
      }
    }
    await _release(db);
    await _audit(db, 'numbering_confirmed', userId, deviceId, {
      'last_issued': lastIssued,
      'continues_from': moved,
    });
  }

  /// Decision 2: the last numbers cannot be verified, so official documents
  /// continue in a distinct series (`SINV-2026-R1-0001`). Only where a
  /// separate series is acceptable to the tax authority; Atlas says so.
  static Future<String> startRecoverySeries(
    Database db, {
    required String userId,
    required String deviceId,
  }) async {
    final existing = await activeSegment(db);
    var n = 1;
    if (existing != null && existing.startsWith('R')) {
      n = (int.tryParse(existing.substring(1)) ?? 0) + 1;
    }
    final segment = 'R$n';
    for (final dt in officialNumberingDocTypes) {
      await NamingSeriesPolicyStore.write(
          db, NamingSeriesPolicy(docType: dt, segment: segment));
    }
    await _audit(db, 'numbering_recovery_series', userId, deviceId,
        {'segment': segment, 'doc_types': officialNumberingDocTypes.toList()});
    return segment;
  }

  /// Audit a hand-set next number (Settings › Numbering series).
  static Future<void> recordManualChange(
          Database db, String series, int nextNumber,
          {required String userId, required String deviceId}) =>
      _audit(db, 'numbering_set_next', userId, deviceId,
          {'series': series, 'next_number': nextNumber});

  /// The company names in [db]: identifies the business across a restore.
  static Future<Set<String>> companies(DatabaseExecutor db) async {
    try {
      return {
        for (final r in await db.query('documents',
            columns: ['id'], where: 'doctype = ?', whereArgs: ['Company']))
          '${r['id']}',
      };
    } on DatabaseException {
      return const {};
    }
  }

  static Future<Set<String>> _officialIds(DatabaseExecutor db) async {
    final marks = List.filled(officialNumberingDocTypes.length, '?').join(',');
    try {
      return {
        for (final r in await db.query('documents',
            columns: ['id'],
            where: 'doctype IN ($marks)',
            whereArgs: officialNumberingDocTypes.toList()))
          '${r['id']}',
      };
    } on DatabaseException {
      return const {};
    }
  }

  static Future<void> _hold(DatabaseExecutor db, String reason) async {
    for (final dt in officialNumberingDocTypes) {
      final current = await NamingSeriesPolicyStore.read(db, dt);
      await NamingSeriesPolicyStore.write(
          db,
          NamingSeriesPolicy(
              docType: dt,
              hold: true,
              holdReason: reason,
              segment: current?.segment ?? ''));
    }
  }

  static Future<void> _release(DatabaseExecutor db) async {
    for (final p in await NamingSeriesPolicyStore.all(db)) {
      if (!p.hold) continue;
      await NamingSeriesPolicyStore.write(
          db, NamingSeriesPolicy(docType: p.docType, segment: p.segment));
    }
  }

  static String _auditId() {
    final r = Random.secure();
    return 'numbering-${List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';
  }

  static Future<void> _audit(DatabaseExecutor db, String action, String userId,
      String deviceId, Map<String, Object?> payload) async {
    await db.insert('audit_log', {
      'id': _auditId(),
      'document_id': 'numbering',
      'doctype': numberingAuditDocType,
      'action': action,
      'user_id': userId,
      'device_id': deviceId,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'payload': jsonEncode(payload),
    });
  }
}
