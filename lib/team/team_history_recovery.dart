import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:mercantis_core/mercantis_core.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common/sqlite_api.dart';

import '../ledger/ledger_derivation.dart';
import '../manifest/hub_manifest.dart';
import '../support/diagnostic_log.dart';
import 'solo_to_team.dart';
import 'solo_to_team_runner.dart';
import 'team_history.dart';
import 'team_posting_service.dart';
import 'team_session.dart';
import 'team_sync_runner.dart';

/// An official record this device had and the restored server does not.
class LostOfficialRecord {
  const LostOfficialRecord({
    required this.docType,
    required this.documentId,
    required this.kind,
    this.number,
    this.postingDate,
    this.total,
    this.party,
  });

  final String docType;
  final String documentId;

  /// `posted` (the server has no such document) or `cancellation` (the
  /// server still shows it submitted; the cancellation was lost).
  final String kind;
  final String? number;
  final String? postingDate;
  final num? total;
  final String? party;

  Map<String, Object?> toJson() => {
        'doctype': docType,
        'document_id': documentId,
        'kind': kind,
        'number': number,
        'posting_date': postingDate,
        'total': total,
        'party': party,
      };

  String describe() => [
        docType,
        number ?? documentId,
        if (postingDate != null) postingDate,
        if (party != null) party,
        if (total != null) total!.toStringAsFixed(2),
        if (kind == 'cancellation') '(its cancellation)',
      ].join(' · ');
}

/// What a recovery found and did. Kept beside the archived book as
/// `recovery-report.json` and shown to the user before the switch.
class TeamRecoveryReport {
  TeamRecoveryReport({
    required this.recoveryId,
    required this.divergence,
    required this.serverHead,
  });

  final String recoveryId;
  final TeamHistoryDiverged divergence;
  final int serverHead;

  final lost = <LostOfficialRecord>[];

  /// Official numbers the restored server has since given to other
  /// documents (from the server's answer to the lost-history report).
  final numberReused = <Map<String, Object?>>[];

  /// Floors the server set so lost numbers are never issued again.
  final numberingFloors = <Map<String, Object?>>[];
  bool lostReported = false;
  String? reportProblem;

  /// Drafts and master edits not yet on the server, carried into the
  /// recovered book to be sent on the next sync.
  final carried = <String>[];

  /// Unsent edits that could not be carried, with why.
  final notCarried = <String>[];

  /// Till sales completed offline and not yet confirmed: carried, and sent
  /// for confirmation on the next sync.
  final pendingTillSales = <String>[];

  /// Consistency problems in the book rebuilt from the server. A recovery
  /// with any of these does not switch.
  final integrityProblems = <String>[];

  String? snapshotPath;

  bool get canSwitch => integrityProblems.isEmpty;

  Map<String, Object?> toJson() => {
        'recovery_id': recoveryId,
        'divergence': divergence.toJson(),
        'server_head': serverHead,
        'snapshot': snapshotPath,
        'lost': [for (final l in lost) l.toJson()],
        'lost_reported': lostReported,
        'report_problem': reportProblem,
        'number_reused': numberReused,
        'numbering_floors': numberingFloors,
        'carried': carried,
        'not_carried': notCarried,
        'pending_till_sales': pendingTillSales,
        'integrity_problems': integrityProblems,
      };
}

/// The recovered book, built and checked but not yet live.
class PreparedTeamRecovery {
  const PreparedTeamRecovery({
    required this.report,
    required this.stagingPath,
    required this.cursor,
    required this.checkpoint,
  });
  final TeamRecoveryReport report;
  final String stagingPath;
  final int cursor;
  final TeamHistoryCheckpoint? checkpoint;
}

/// C4: recovers a Team device after the server was restored from a backup
/// and its history no longer matches what the device saw.
///
/// Never a blind wipe and never a cursor reset:
///  1. The caller takes an encrypted snapshot of the live book first
///     ([snapshot]); it is recorded in the report.
///  2. A new book is built in a staging file from the server alone (the
///     server is the authority for official records, ledgers and stock).
///  3. The live book is compared with it: official records the server no
///     longer has are listed (never re-posted: their numbers may since have
///     gone to other documents) and reported to the server, which flags
///     reused numbers and raises its series past the lost ones.
///  4. Work the server never had is carried across: unsent drafts and
///     master edits, and offline till sales awaiting confirmation. Unsent
///     edits to a document the server now holds as official are not
///     carried; they are listed.
///  5. The rebuilt book's ledger is checked for consistency.
///  6. Only then may [switchOver] put it in place, archiving the live book
///     (nothing is deleted). Every step before the switch leaves the live
///     book untouched, so a failed or interrupted recovery is simply run
///     again.
class TeamHistoryRecovery {
  TeamHistoryRecovery({
    required this.live,
    required this.session,
    required this.localDeviceId,
    required this.factory,
    this.client,
  });

  final Database live;
  final TeamSession session;
  final String localDeviceId;
  final DatabaseFactory factory;
  final http.Client? client;

  /// Official doctypes: the posting sources (Team-posted and local) and the
  /// till's receipts.
  static final officialDocTypes = {
    ...LedgerDerivation.postingSources,
    'POS Invoice',
  };

  static const _unsent = ['pending', 'pushing', 'failed'];

  Future<PreparedTeamRecovery> prepare({
    required TeamHistoryDiverged divergence,
    required String recoveryId,
    required String stagingPath,
    Future<String?> Function()? snapshot,
    void Function(String step)? onStep,
  }) async {
    onStep?.call('Saving an encrypted copy of this device’s books…');
    final snapshotPath = await snapshot?.call();

    onStep?.call('Downloading the books from the Team server…');
    final cursor = _MemoryCursor();
    final history = MemoryTeamHistoryStore();
    await _buildServerBook(stagingPath, cursor, history);

    final staging = await factory.openDatabase(stagingPath);
    try {
      final report = TeamRecoveryReport(
        recoveryId: recoveryId,
        divergence: divergence,
        serverHead: history.verifiedValue?.version ?? 0,
      )..snapshotPath = snapshotPath;

      onStep?.call('Comparing this device with the server…');
      final tillSales = await _pendingTillSales(staging);
      await _findLost(staging, report, tillSales);

      onStep?.call('Keeping work the server never received…');
      await _carry(staging, report, tillSales);

      if (report.lost.isNotEmpty) {
        onStep?.call('Telling the server which records were lost…');
        await _reportLost(report);
      }

      onStep?.call('Checking the recovered books…');
      report.integrityProblems.addAll(await integrityProblems(staging));

      return PreparedTeamRecovery(
        report: report,
        stagingPath: stagingPath,
        cursor: cursor.value,
        checkpoint: history.verifiedValue,
      );
    } finally {
      await staging.close();
    }
  }

  /// Puts the prepared book in place (call with the live database CLOSED),
  /// archives the old one with the report beside it, and clears the
  /// device's recovery mark. Returns the archive path.
  static Future<String> switchOver({
    required PreparedTeamRecovery prepared,
    required String liveDatabasePath,
    required String archiveDirectory,
    required DatabaseFactory factory,
    required String companyId,
    required TeamSyncCursorStore cursorStore,
    required TeamHistoryStore historyStore,
  }) async {
    if (!prepared.report.canSwitch) {
      throw StateError('The recovered books failed their checks: '
          '${prepared.report.integrityProblems.join('; ')}');
    }
    final archived = await SoloToTeamRunner.switchToTeamBook(
      liveDatabasePath: liveDatabasePath,
      teamBookPath: prepared.stagingPath,
      archiveDirectory: archiveDirectory,
      factory: factory,
    );
    File(p.join(archiveDirectory, 'recovery-report.json')).writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(prepared.report.toJson()));
    await cursorStore.save(companyId, prepared.cursor);
    await historyStore.reset(companyId);
    final c = prepared.checkpoint;
    if (c != null) await historyStore.setVerified(companyId, c);
    DiagnosticLog.instance.record(
        'team-recovery',
        'Recovered from a restored server: ${prepared.report.lost.length} lost, '
            '${prepared.report.carried.length} carried, '
            '${prepared.report.pendingTillSales.length} till sales pending');
    return archived;
  }

  // ----------------------------------------------------------- building

  Future<void> _buildServerBook(
      String path, TeamSyncCursorStore cursor, TeamHistoryStore history) async {
    for (final suffix in ['', '-wal', '-shm', '-journal']) {
      final f = File('$path$suffix');
      if (f.existsSync()) f.deleteSync(); // our own staging file, rebuilt
    }
    Directory(p.dirname(path)).createSync(recursive: true);
    final book = await MercantisDatabase.open(factory: factory, path: path);
    try {
      final registry = MetadataRegistry(book.db);
      await AppInstaller(database: book.db, registry: registry)
          .install(HubManifest.build());
      await runTeamSync(
        session: session,
        database: book.db,
        registry: registry,
        // Not this device's id: the sync skips a device's own echoes, and
        // here every record must come from the server, this device's
        // included.
        localDeviceId: '$localDeviceId~recovery',
        client: client,
        cursorStore: cursor,
        historyStore: history,
      );
    } finally {
      await book.close();
    }
  }

  // ---------------------------------------------------------- comparing

  /// Till sales this device completed offline that the server has not
  /// confirmed: they are this device's to send, not lost.
  ///
  /// A receipt can lack its official number here although the server
  /// confirmed it (the confirmation succeeded, then the till lost the
  /// connection before pulling the official rows). The server's book in
  /// [staging] then holds the confirmed receipt, and that version is kept:
  /// carrying the provisional local copy over it would leave the receipt
  /// looking unconfirmed for good, because the recovered cursor is already
  /// past the confirmation.
  Future<Set<String>> _pendingTillSales(Database staging) async {
    final rows = await live.rawQuery(
      'SELECT d.id, d.payload FROM documents d WHERE d.doctype = ? '
      'AND d.docstatus = 1 AND EXISTS (SELECT 1 FROM sync_queue q '
      'WHERE q.document_id = d.id AND q.doctype = ? AND q.type = ? '
      'AND q.device_id = ?)',
      [
        'POS Invoice',
        'POS Invoice',
        MutationType.submitDocument.name,
        localDeviceId,
      ],
    );
    final pending = <String>{};
    for (final r in rows) {
      if ('${_payload(r)['official_number'] ?? ''}'.isNotEmpty) continue;
      final id = '${r['id']}';
      final theirs = await staging.query('documents',
          columns: ['docstatus', 'payload'], where: 'id = ?', whereArgs: [id]);
      final confirmed = theirs.isNotEmpty &&
          (theirs.first['docstatus'] as int? ?? 0) >= 1 &&
          '${_payload(theirs.first)['official_number'] ?? ''}'.isNotEmpty;
      if (!confirmed) pending.add(id);
    }
    return pending;
  }

  Future<void> _findLost(Database staging, TeamRecoveryReport report,
      Set<String> tillSales) async {
    final types = officialDocTypes.toList();
    final rows = await live.rawQuery(
      'SELECT id, doctype, docstatus, payload FROM documents '
      'WHERE docstatus >= 1 AND doctype IN '
      '(${List.filled(types.length, '?').join(', ')}) ORDER BY created_at',
      types,
    );
    for (final r in rows) {
      final id = '${r['id']}';
      if (tillSales.contains(id)) continue;
      final there = await staging.query('documents',
          columns: ['docstatus'], where: 'id = ?', whereArgs: [id]);
      final serverStatus =
          there.isEmpty ? null : (there.first['docstatus'] as int? ?? 0);
      final localStatus = r['docstatus'] as int? ?? 0;
      String? kind;
      if (serverStatus == null || serverStatus == 0) {
        kind = 'posted';
      } else if (localStatus == 2 && serverStatus == 1) {
        kind = 'cancellation';
      }
      if (kind == null) continue;
      final payload = _payload(r);
      final number = '${payload['official_number'] ?? ''}'.trim();
      report.lost.add(LostOfficialRecord(
        docType: '${r['doctype']}',
        documentId: id,
        kind: kind,
        number: number.isEmpty ? null : number,
        postingDate: _str(payload['posting_date']),
        total: _num(payload['base_grand_total'] ??
            payload['grand_total'] ??
            payload['paid_amount'] ??
            payload['total_amount']),
        party: _str(
            payload['customer'] ?? payload['supplier'] ?? payload['party']),
      ));
    }
  }

  // ----------------------------------------------------------- carrying

  Future<void> _carry(Database staging, TeamRecoveryReport report,
      Set<String> tillSales) async {
    final derived = teamServerDerivedDocTypes.toList();
    final queued = await live.rawQuery(
      'SELECT DISTINCT document_id, doctype FROM sync_queue WHERE status IN '
      '(${List.filled(_unsent.length, '?').join(', ')}) AND doctype NOT IN '
      '(${List.filled(derived.length, '?').join(', ')})',
      [..._unsent, ...derived],
    );
    final ids = <String, String>{
      for (final q in queued) '${q['document_id']}': '${q['doctype']}',
      for (final t in tillSales) t: 'POS Invoice',
    };
    for (final entry in ids.entries) {
      final id = entry.key;
      final label = '${entry.value} $id';
      final mine =
          await live.query('documents', where: 'id = ?', whereArgs: [id]);
      final theirs =
          await staging.query('documents', where: 'id = ?', whereArgs: [id]);
      final isTillSale = tillSales.contains(id);
      if (!isTillSale &&
          theirs.isNotEmpty &&
          (theirs.first['docstatus'] as int? ?? 0) >= 1) {
        report.notCarried.add('$label: it is now an official document on the '
            'server, so the unsent edit on this device was not applied');
        continue;
      }
      if (!isTillSale &&
          mine.isNotEmpty &&
          (mine.first['docstatus'] as int? ?? 0) >= 1) {
        // An official record with an unsent change: already listed as lost
        // or present on the server; nothing to carry.
        continue;
      }
      await staging.transaction((txn) async {
        if (mine.isNotEmpty) {
          await txn.insert('documents', mine.first,
              conflictAlgorithm: ConflictAlgorithm.replace);
          await txn.delete('document_children',
              where: 'parent_id = ?', whereArgs: [id]);
          for (final c in await live.query('document_children',
              where: 'parent_id = ?', whereArgs: [id])) {
            await txn.insert('document_children', c,
                conflictAlgorithm: ConflictAlgorithm.replace);
          }
          for (final a in await live.query('attachments',
              where: 'document_id = ?', whereArgs: [id])) {
            await txn.insert('attachments', a,
                conflictAlgorithm: ConflictAlgorithm.replace);
          }
        }
        // A till sale keeps its whole queue (its submit row is how the next
        // sync knows it was sold here); anything else only its unsent rows.
        final rows = isTillSale
            ? await live
                .query('sync_queue', where: 'document_id = ?', whereArgs: [id])
            : await live.query('sync_queue',
                where: 'document_id = ? AND status IN '
                    '(${List.filled(_unsent.length, '?').join(', ')})',
                whereArgs: [id, ..._unsent]);
        for (final q in rows) {
          final row = Map<String, Object?>.from(q);
          // An interrupted push is simply pending again.
          if (row['status'] == 'pushing') row['status'] = 'pending';
          await txn.insert('sync_queue', row,
              conflictAlgorithm: ConflictAlgorithm.replace);
        }
      });
      (isTillSale ? report.pendingTillSales : report.carried).add(label);
    }

    // Drafts and records this device had already sent, which the restore
    // took off the server: sent again as new, so nothing is silently lost.
    final skip = [...SoloToTeamConversion.neverPublished];
    final drafts = await live.rawQuery(
      'SELECT * FROM documents WHERE docstatus = 0 AND doctype NOT IN '
      '(${List.filled(skip.length, '?').join(', ')})',
      skip,
    );
    for (final doc in drafts) {
      final id = '${doc['id']}';
      if (ids.containsKey(id)) continue;
      final theirs = await staging.query('documents',
          columns: ['id'], where: 'id = ?', whereArgs: [id]);
      if (theirs.isNotEmpty) continue;
      final children = await live.query('document_children',
          where: 'parent_id = ?', whereArgs: [id], orderBy: 'row_index ASC');
      final byTable = <String, List<Map<String, dynamic>>>{};
      for (final c in children) {
        byTable
            .putIfAbsent('${c['table_name']}', () => [])
            .add(Map<String, dynamic>.from(c));
      }
      final now = DateTime.now();
      final row = {...doc, 'sync_state': SyncState.local.name};
      await staging.transaction((txn) async {
        await txn.insert('documents', row,
            conflictAlgorithm: ConflictAlgorithm.replace);
        for (final c in children) {
          await txn.insert('document_children', c,
              conflictAlgorithm: ConflictAlgorithm.replace);
        }
        for (final a in await live
            .query('attachments', where: 'document_id = ?', whereArgs: [id])) {
          await txn.insert('attachments', a,
              conflictAlgorithm: ConflictAlgorithm.replace);
        }
        await txn.insert(
          'sync_queue',
          MutationRecord(
            id: 'recover-${report.recoveryId}-$id',
            type: MutationType.createDocument,
            docType: '${doc['doctype']}',
            documentId: id,
            payload: {...row, '__children': byTable},
            deviceId: localDeviceId,
            userId: session.userId,
            localTimestamp: now,
            status: MutationStatus.pending,
          ).toDbRow(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      });
      report.carried.add('${doc['doctype']} $id (sent again: the restored '
          'server no longer had it)');
    }
  }

  // ---------------------------------------------------------- reporting

  Future<void> _reportLost(TeamRecoveryReport report) async {
    final posting = TeamPostingClient(
      baseUrl: session.baseUrl,
      companyId: session.companyId,
      deviceToken: session.deviceToken,
      client: client,
      history: MemoryTeamHistoryStore(),
    );
    try {
      final answer = await posting.reportLostHistory({
        'recovery_id': report.recoveryId,
        'lost': [
          for (final l in report.lost)
            {
              'doctype': l.docType,
              'document_id': l.documentId,
              'number': l.number,
              'posting_date': l.postingDate,
              'total': l.total,
            },
        ],
      });
      report.lostReported = true;
      for (final r in (answer['number_reused'] as List? ?? const [])) {
        if (r is Map) report.numberReused.add(Map<String, Object?>.from(r));
      }
      for (final r in (answer['numbering_floors'] as List? ?? const [])) {
        if (r is Map) report.numberingFloors.add(Map<String, Object?>.from(r));
      }
    } on CloudHttpException catch (e) {
      if (e.statusCode == 403) {
        report.reportProblem = 'Only an owner, admin or accountant can send '
            'this list to the server. Ask one of them to recover a device, or '
            'send them recovery-report.json from this device.';
      } else if (e.statusCode == 404) {
        report.reportProblem =
            'This Team server cannot receive the list (it needs an update).';
      } else {
        rethrow;
      }
    } finally {
      if (client == null) posting.close();
    }
  }

  // ----------------------------------------------------------- checking

  /// Consistency of a book built from the server: the trial balance
  /// balances, stock agrees with the inventory accounts, and customer and
  /// supplier balances agree with the receivable and payable ledger.
  static Future<List<String>> integrityProblems(Database book) async {
    final f = await SoloToTeamConversion(book).figures();
    final problems = <String>[];
    final tb = f.trialBalance.values.fold<num>(0, (a, b) => a + b);
    if (tb.abs() >= 0.005) {
      problems.add('The trial balance is out by ${tb.toStringAsFixed(2)}');
    }
    final byAccount = <String, num>{};
    for (final s in f.stock) {
      byAccount[s.account] = (byAccount[s.account] ?? 0) + s.value;
    }
    for (final e in byAccount.entries) {
      final ledger = f.trialBalance[e.key] ?? 0;
      if ((ledger - e.value).abs() >= 0.01) {
        problems.add('Stock on ${e.key} is worth ${e.value.toStringAsFixed(2)} '
            'but the account shows ${ledger.toStringAsFixed(2)}');
      }
    }
    final ar = f.customerBalances.values.fold<num>(0, (a, b) => a + b);
    if ((ar - f.receivables).abs() >= 0.01) {
      problems.add('Customer balances total ${ar.toStringAsFixed(2)} but the '
          'ledger shows ${f.receivables.toStringAsFixed(2)}');
    }
    final ap = f.supplierBalances.values.fold<num>(0, (a, b) => a + b);
    if ((ap - f.payables).abs() >= 0.01) {
      problems.add('Supplier balances total ${ap.toStringAsFixed(2)} but the '
          'ledger shows ${f.payables.toStringAsFixed(2)}');
    }
    return problems;
  }

  static Map<String, dynamic> _payload(Map<String, Object?> row) {
    try {
      final v = jsonDecode('${row['payload']}');
      return v is Map<String, dynamic> ? v : {};
    } catch (_) {
      return {};
    }
  }

  static String? _str(Object? v) {
    final s = '${v ?? ''}'.trim();
    return s.isEmpty ? null : s;
  }

  static num? _num(Object? v) =>
      v is num ? v : (v == null ? null : num.tryParse('$v'));
}

class _MemoryCursor implements TeamSyncCursorStore {
  int value = 0;
  @override
  Future<int> load(String companyId) async => value;
  @override
  Future<void> save(String companyId, int cursor) async => value = cursor;
}
