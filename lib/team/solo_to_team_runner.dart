import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:mercantis_core/mercantis_core.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common/sqlite_api.dart';

import '../manifest/hub_manifest.dart';
import '../support/diagnostic_log.dart';
import 'solo_to_team.dart';
import 'team_account_client.dart';
import 'team_posting_service.dart';
import 'team_session.dart';
import 'team_sync_runner.dart';

/// The Team book did not match the Solo figures, so this device was not
/// switched over. The Solo book is untouched.
class ConversionMismatch implements Exception {
  ConversionMismatch(this.problems);
  final List<String> problems;
  @override
  String toString() =>
      'The Team books do not match the Solo books (${problems.length} '
      'difference${problems.length == 1 ? '' : 's'}): ${problems.take(5).join('; ')}';
}

/// What a completed (not yet switched) conversion produced.
class ConversionOutcome {
  const ConversionOutcome({
    required this.package,
    required this.serverResponse,
    required this.teamBookPath,
    required this.published,
  });
  final SoloTeamPackage package;
  final Map<String, dynamic> serverResponse;

  /// The reconciled Team book, ready to take the Solo book's place.
  final String teamBookPath;
  final int published;

  /// "Sales Invoice: Solo's last SINV-.2026.-0002, Team continues at
  /// SINV-00003" lines from the server.
  List<String> get numberingLines => [
        for (final n in (serverResponse['numbering'] as List? ?? const []))
          if (n is Map)
            '${n['doctype']}: Solo\'s last ${n['solo_last_issued']}, Team '
                'continues at ${n['team_next_number']}',
      ];
}

/// Where an unfinished move stands (no secrets: the Team credentials are in
/// the keychain under [TeamSessionStore.pendingMigration]).
class SoloToTeamProgress {
  const SoloToTeamProgress({
    required this.migrationId,
    required this.cutoverDate,
    required this.companyId,
    required this.stage,
    this.archivePath,
  });

  final String migrationId;
  final String cutoverDate;
  final String companyId;

  /// created → imported → built → switched.
  final String stage;
  final String? archivePath;

  static const _key = 'atlas.solo_to_team.progress';

  Map<String, Object?> toJson() => {
        'migration_id': migrationId,
        'cutover_date': cutoverDate,
        'company_id': companyId,
        'stage': stage,
        if (archivePath != null) 'archive_path': archivePath,
      };

  SoloToTeamProgress at(String newStage, {String? archive}) =>
      SoloToTeamProgress(
        migrationId: migrationId,
        cutoverDate: cutoverDate,
        companyId: companyId,
        stage: newStage,
        archivePath: archive ?? archivePath,
      );

  static Future<SoloToTeamProgress?> load() async {
    final raw = (await SharedPreferences.getInstance()).getString(_key);
    if (raw == null) return null;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      return SoloToTeamProgress(
        migrationId: '${j['migration_id']}',
        cutoverDate: '${j['cutover_date']}',
        companyId: '${j['company_id']}',
        stage: '${j['stage']}',
        archivePath: j['archive_path'] as String?,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> save() async => (await SharedPreferences.getInstance())
      .setString(_key, jsonEncode(toJson()));

  static Future<void> clear() async =>
      (await SharedPreferences.getInstance()).remove(_key);
}

/// Runs a conversion against the Team server (see [SoloToTeamConversion]
/// for the why). Every step is safe to repeat with the same migration id:
/// published mutations have deterministic ids, the take-on is idempotent on
/// the migration id, and the Team book is rebuilt from scratch.
class SoloToTeamRunner {
  SoloToTeamRunner({
    required this.solo,
    required this.localDeviceId,
    required this.factory,
    this.client,
    TeamSyncCursorStore? cursorStore,
  }) : cursorStore = cursorStore ?? TeamSyncCursorStore();

  final Database solo;
  final String localDeviceId;
  final DatabaseFactory factory;
  final http.Client? client;
  final TeamSyncCursorStore cursorStore;

  static const pushBatch = 200;

  /// Publishes, imports, builds the Team book at [teamBookPath] and
  /// reconciles it. Throws [ConversionMismatch] (Team book kept for support,
  /// Solo book untouched) or the server's refusal.
  Future<ConversionOutcome> run({
    required TeamSession session,
    required String migrationId,
    required String cutoverDate,
    required String teamBookPath,
    Map<String, Object?> source = const {},
    void Function(String step)? onStep,
  }) async {
    final conversion = SoloToTeamConversion(solo);
    final soloFigures = await conversion.figures();
    onStep?.call('Preparing the opening position…');
    final package = await conversion.buildPackage(
        migrationId: migrationId, cutoverDate: cutoverDate, source: source);
    final published = [
      ...await conversion.masterMutations(
          migrationId: migrationId,
          deviceId: localDeviceId,
          userId: session.userId),
      conversion.openingDraft(package,
          deviceId: localDeviceId, userId: session.userId),
    ];

    onStep?.call('Sending accounts, customers, suppliers and items…');
    final adapter = TeamAccountClient.adapterFor(session, client: client);
    try {
      for (var i = 0; i < published.length; i += pushBatch) {
        await adapter.push(
            published.sublist(i, (i + pushBatch).clamp(0, published.length)));
      }
    } finally {
      adapter.close();
    }

    onStep?.call('Posting the opening balances on the Team server…');
    final posting = TeamPostingClient(
      baseUrl: session.baseUrl,
      companyId: session.companyId,
      deviceToken: session.deviceToken,
      client: client,
    );
    final Map<String, dynamic> response;
    try {
      response = await posting.importSoloOpening(package.toJson());
    } finally {
      if (client == null) posting.close();
    }
    await _carrySettings(session);

    onStep?.call('Building the Team books on this device…');
    await _buildTeamBook(session, teamBookPath, published);

    onStep?.call('Checking every balance against the Solo books…');
    final team = await factory.openDatabase(teamBookPath);
    try {
      final problems = await SoloToTeamConversion.reconcile(soloFigures, team);
      if (problems.isNotEmpty) throw ConversionMismatch(problems);
    } finally {
      await team.close();
    }
    return ConversionOutcome(
      package: package,
      serverResponse: response,
      teamBookPath: teamBookPath,
      published: published.length,
    );
  }

  /// The Solo lock date and posting accounts become the Team company's, so
  /// Team posts to the same accounts and keeps closed periods closed.
  Future<void> _carrySettings(TeamSession session) async {
    final rows = await solo.query('documents',
        where: 'doctype = ?', whereArgs: ['Company'], limit: 1);
    if (rows.isEmpty) return;
    final c = jsonDecode('${rows.first['payload']}') as Map<String, dynamic>;
    const keys = [
      'books_lock_date',
      'default_receivable_account',
      'default_payable_account',
      'default_income_account',
      'default_cash_account',
      'default_inventory_account',
      'default_cogs_account',
      'default_grni_account',
      'default_stock_adjustment_account',
    ];
    final patch = <String, dynamic>{
      for (final k in keys)
        if ('${c[k] ?? ''}'.trim().isNotEmpty) k: '${c[k]}'.trim(),
      if (c['allow_negative_stock'] != null)
        'allow_negative_stock': c['allow_negative_stock'] == true ||
            '${c['allow_negative_stock']}' == '1',
    };
    if (patch.isEmpty) return;
    final account = TeamAccountClient(baseUrl: session.baseUrl, client: client);
    await account.patchSettings(
        companyId: session.companyId,
        authToken: session.userToken,
        settings: patch);
  }

  Future<void> _buildTeamBook(
      TeamSession session, String path, List<MutationRecord> published) async {
    for (final suffix in ['', '-wal', '-shm', '-journal']) {
      final f = File('$path$suffix');
      if (f.existsSync()) f.deleteSync(); // our own staging file, rebuilt
    }
    Directory(p.dirname(path)).createSync(recursive: true);
    final team = await MercantisDatabase.open(factory: factory, path: path);
    try {
      final registry = MetadataRegistry(team.db);
      await AppInstaller(database: team.db, registry: registry)
          .install(HubManifest.build());
      await SoloToTeamConversion.seedTeamBook(team.db, published);
      await cursorStore.save(session.companyId, 0);
      await runTeamSync(
        session: session,
        database: team.db,
        registry: registry,
        localDeviceId: localDeviceId,
        client: client,
        cursorStore: cursorStore,
      );
    } finally {
      await team.close();
    }
  }

  /// Puts the reconciled Team book in the Solo book's place. Call with the
  /// live database CLOSED. The Solo book is first copied (with its WAL) to
  /// [archiveDirectory] and the copy checked, then the Team book is renamed
  /// over the live file in one step, so a crash at any point leaves either
  /// the Solo book or the Team book live, never neither. Nothing is deleted.
  static Future<String> switchToTeamBook({
    required String liveDatabasePath,
    required String teamBookPath,
    required String archiveDirectory,
    required DatabaseFactory factory,
  }) async {
    Directory(archiveDirectory).createSync(recursive: true);
    final archived = p.join(archiveDirectory, p.basename(liveDatabasePath));
    for (final suffix in ['', '-wal', '-shm']) {
      final f = File('$liveDatabasePath$suffix');
      if (f.existsSync()) f.copySync('$archived$suffix');
    }
    // The archive must open and pass its integrity check before the live
    // file is replaced.
    final check = await factory.openDatabase(archived);
    try {
      final r = await check.rawQuery('PRAGMA quick_check');
      if (r.isEmpty || '${r.first.values.first}' != 'ok') {
        throw StateError(
            'The Solo archive copy failed its check; nothing was switched.');
      }
      await check.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
    } finally {
      await check.close();
    }
    // The live WAL belongs to the Solo book: it must not be replayed into
    // the Team book. The archive now holds it.
    for (final suffix in ['-wal', '-shm']) {
      final f = File('$liveDatabasePath$suffix');
      if (f.existsSync()) f.renameSync('$archived.live$suffix');
    }
    try {
      File(teamBookPath).renameSync(liveDatabasePath);
    } on FileSystemException {
      // Windows will not rename over an open-able existing file: move the
      // Solo file aside (it is archived already) and retry.
      File(liveDatabasePath).renameSync('$liveDatabasePath.solo-before-team');
      File(teamBookPath).renameSync(liveDatabasePath);
    }
    DiagnosticLog.instance.record('solo-to-team',
        'Switched to the Team book; Solo archived at $archived');
    return archived;
  }
}

/// How many official Solo documents this book holds. Connecting such a
/// book to Team directly would wedge its sync, so the Team screen offers the
/// conversion instead.
Future<int> soloHistoryCount(Database db) async {
  final types = SoloToTeamConversion.historyDocTypes.toList();
  final r = await db.rawQuery(
    'SELECT COUNT(*) AS n FROM documents WHERE docstatus >= 1 '
    'AND doctype IN (${List.filled(types.length, '?').join(', ')})',
    types,
  );
  return (r.first['n'] as int?) ?? 0;
}
