import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mercantis_core/mercantis_core.dart' show CloudHttpException;
import 'package:mercantis_core_ui/mercantis_core_ui.dart';
import 'package:path/path.dart' as p;

import '../backup/app_restart.dart';
import '../backup/hub_backup.dart';
import '../numbering/numbering_recovery.dart';
import '../support/diagnostic_log.dart';
import '../support/storage_errors.dart';
import '../team/solo_to_team.dart';
import '../team/solo_to_team_runner.dart';
import '../team/team_account_client.dart';
import '../team/team_session.dart';
import 'backup_restore_screen.dart' show hubBackupProvider;

String _today() {
  final d = DateTime.now();
  return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

final _preflightProvider =
    FutureProvider.autoDispose<SoloTeamPreflight>((ref) async {
  final db = await ref.watch(mercantisDatabaseProvider.future);
  final holds = await NumberingRecovery.holds(db.db);
  return SoloToTeamConversion(db.db).preflight(
    cutoverDate: _today(),
    teamConnected: ref.watch(teamSessionProvider) != null,
    numberingHolds: {for (final h in holds) h.docType},
  );
});

/// C3: move this device's Solo books into a new Atlas Team company, once.
/// See [SoloToTeamConversion] for what happens and why.
class SoloToTeamScreen extends ConsumerStatefulWidget {
  const SoloToTeamScreen(
      {super.key, required this.serverUrl, required this.deviceName});

  final String serverUrl;
  final String deviceName;

  @override
  ConsumerState<SoloToTeamScreen> createState() => _SoloToTeamScreenState();
}

class _SoloToTeamScreenState extends ConsumerState<SoloToTeamScreen> {
  final _email = TextEditingController();
  final _name = TextEditingController();
  final _company = TextEditingController();
  final _pass = TextEditingController();
  final _pass2 = TextEditingController();
  final _typed = TextEditingController();
  String? _step;
  String? _error;
  List<String> _mismatches = const [];

  @override
  void dispose() {
    for (final c in [_email, _name, _company, _pass, _pass2, _typed]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _ready =>
      _email.text.trim().contains('@') &&
      _name.text.trim().isNotEmpty &&
      _company.text.trim().isNotEmpty &&
      _pass.text.length >= 10 &&
      _pass.text == _pass2.text &&
      _typed.text.trim() == 'MOVE';

  Future<void> _move() async {
    setState(() {
      _error = null;
      _mismatches = const [];
      _step = 'Making the safety backup…';
    });
    final pending = TeamSessionStore.pendingMigration();
    try {
      final db = await ref.read(mercantisDatabaseProvider.future);
      final dir = await ref.read(atlasDataDirectoryProvider.future);
      final deviceId = await ref.read(deviceIdProvider.future);

      // 1. Safety backup: encrypted and checked before anything leaves the
      //    device. Not optional.
      final backup = await ref.read(hubBackupProvider.future);
      final report = await backup.createBackup(
        database: db.db,
        passphrase: _pass.text,
        preferences: await HubBackup.readPreferences(),
      );
      await HubBackup.recordBackup(DateTime.now());

      // 2. The Team company (or the one an interrupted attempt created).
      var progress = await SoloToTeamProgress.load();
      var session = await pending.load();
      if (progress == null || session == null) {
        setState(() => _step = 'Creating the Team company…');
        session = await TeamAccountClient(baseUrl: widget.serverUrl.trim())
            .createAndConnect(
          companyName: _company.text.trim(),
          ownerEmail: _email.text.trim(),
          ownerName: _name.text.trim(),
          deviceName: widget.deviceName.trim(),
        );
        await pending.save(session);
        progress = SoloToTeamProgress(
          migrationId: _newMigrationId(),
          cutoverDate: _today(),
          companyId: session.companyId,
          stage: 'created',
        );
        await progress.save();
      }

      // 3–5. Publish, take-on, build and reconcile the Team book.
      final outcome = await SoloToTeamRunner(
        solo: db.db,
        localDeviceId: deviceId,
        factory: platformDatabaseFactory(),
      ).run(
        session: session,
        migrationId: progress.migrationId,
        cutoverDate: progress.cutoverDate,
        teamBookPath: p.join(dir, 'team-staging', atlasDatabaseFileName),
        source: {
          'app': 'Atlas Solo',
          'backup_file': p.basename(report.path),
        },
        onStep: (s) {
          if (mounted) setState(() => _step = s);
        },
      );
      await progress.at('built').save();
      if (!mounted) return;

      // 6. Switch: archive the Solo book, put the Team book in its place,
      //    connect. Everything else is stopped meanwhile.
      final archiveDir = p.join(dir, 'solo-archive', progress.migrationId);
      final teamSession = session;
      final built = progress;
      await AtlasRestartScope.restart(context,
          message: 'Switching this device to Atlas Team…',
          whileStopped: () async {
        await db.close();
        final archived = await SoloToTeamRunner.switchToTeamBook(
          liveDatabasePath: p.join(dir, atlasDatabaseFileName),
          teamBookPath: outcome.teamBookPath,
          archiveDirectory: archiveDir,
          factory: platformDatabaseFactory(),
        );
        await built.at('switched', archive: archived).save();
        await TeamSessionStore().save(teamSession);
        await pending.clear();
        return RestartNotice(
          success: true,
          title: 'Your books are on Atlas Team',
          body:
              'The Team company opens with your Solo balances, checked to the '
              'cent: every account, customer, supplier and stock line.\n\n'
              '${outcome.numberingLines.join('\n')}\n\n'
              'Your Solo books are kept unchanged on this device '
              '(${p.relative(archived, from: dir)}) and in the safety backup '
              '${p.basename(report.path)}. Keep the backup and its passphrase.',
        );
      });
    } on ConversionMismatch catch (e) {
      DiagnosticLog.instance.record('solo-to-team', e);
      setState(() {
        _step = null;
        _mismatches = e.problems;
        _error = 'The Team books did not match your Solo books, so this device '
            'was not switched. Your Solo books are unchanged. Send the support '
            'report from Help & diagnostics.';
      });
    } on CloudHttpException catch (e) {
      DiagnosticLog.instance.record('solo-to-team', e);
      setState(() {
        _step = null;
        _error = '${e.message}\n\nYour Solo books are unchanged. You can try '
            'again; Atlas continues where it stopped.';
      });
    } catch (e, s) {
      DiagnosticLog.instance.record('solo-to-team', e, s);
      setState(() {
        _step = null;
        _error = '${friendlyStorageError(e) ?? 'The move did not complete: $e'}'
            '\n\nYour Solo books are unchanged. You can try again; Atlas '
            'continues where it stopped.';
      });
    }
  }

  static String _newMigrationId() {
    final r = Random.secure();
    return 'mig-${List.generate(16, (_) => r.nextInt(16).toRadixString(16)).join()}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final async = ref.watch(_preflightProvider);
    return ResponsiveScaffold(
      title: 'Move to Atlas Team',
      leading: const BackButton(),
      padBody: false,
      body: ListView(
        padding: const EdgeInsets.all(MercantisSpacing.lg),
        children: [
          Text(
            'This moves your Solo books into a new Atlas Team company, once. '
            'Team starts from your balances today; your Solo invoices, bills '
            'and payments stay on this device in an archive and in a safety '
            'backup. Nothing is renumbered: Team continues after your last '
            'Solo numbers.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: MercantisSpacing.md),
          async.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text('Could not check the books: $e'),
            data: (pre) => _checks(theme, pre),
          ),
          if (async.valueOrNull?.canProceed == true) ...[
            const SizedBox(height: MercantisSpacing.md),
            _details(theme),
          ],
          if (_step != null)
            Padding(
              padding: const EdgeInsets.all(MercantisSpacing.lg),
              child: Column(children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 12),
                Text(_step!, textAlign: TextAlign.center),
                const Text('Keep Atlas open until this finishes.',
                    textAlign: TextAlign.center),
              ]),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: MercantisSpacing.md),
              child: Text(_error!,
                  style: TextStyle(color: theme.colorScheme.error)),
            ),
          for (final m in _mismatches.take(20))
            Text('• $m', style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }

  Widget _checks(ThemeData theme, SoloTeamPreflight pre) {
    return AtlasSectionCard(
      name: pre.canProceed ? 'Ready to move' : 'Fix these first',
      child: Column(children: [
        for (final c in pre.checks)
          ListTile(
            leading: Icon(
              c.blocking ? Icons.block : Icons.info_outline,
              color: c.blocking ? theme.colorScheme.error : null,
              semanticLabel: c.blocking ? 'Must fix' : 'Note',
            ),
            title: Text(c.message),
          ),
      ]),
    );
  }

  Widget _details(ThemeData theme) {
    final busy = _step != null;
    Widget field(TextEditingController c, String label,
            {bool obscure = false, String? helper}) =>
        Padding(
          padding: const EdgeInsets.only(bottom: MercantisSpacing.md),
          child: TextField(
            controller: c,
            enabled: !busy,
            obscureText: obscure,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
                labelText: label,
                helperText: helper,
                helperMaxLines: 3,
                border: const OutlineInputBorder()),
          ),
        );
    return AtlasSectionCard(
      name: 'The Team company',
      child: Padding(
        padding: const EdgeInsets.all(MercantisSpacing.md),
        child: Column(children: [
          field(_company, 'Company name'),
          field(_email, 'Your email (you become the owner)'),
          field(_name, 'Your name'),
          field(_pass, 'Safety backup passphrase',
              obscure: true,
              helper: 'At least 10 characters. Write it down away from this '
                  'device: without it nobody can open the backup.'),
          field(_pass2, 'Type the passphrase again', obscure: true),
          field(_typed, 'Type MOVE to confirm',
              helper: 'This can be done once per Team company.'),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: busy || !_ready ? null : _move,
              icon: const Icon(Icons.cloud_upload_outlined),
              label: const Text('Back up and move to Atlas Team'),
            ),
          ),
        ]),
      ),
    );
  }
}
