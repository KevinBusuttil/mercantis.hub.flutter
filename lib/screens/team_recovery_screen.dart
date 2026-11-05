import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mercantis_core/mercantis_core.dart' show CloudHttpException;
import 'package:mercantis_core_ui/mercantis_core_ui.dart';
import 'package:path/path.dart' as p;

import '../backup/app_restart.dart';
import '../backup/hub_backup.dart';
import '../support/diagnostic_log.dart';
import '../support/storage_errors.dart';
import '../sync/company_sync.dart';
import '../team/team_history.dart';
import '../team/team_history_recovery.dart';
import '../team/team_session.dart';
import '../team/team_sync_runner.dart';
import 'backup_restore_screen.dart' show hubBackupProvider;

/// Whether this device is paused because the Team server was restored from
/// a backup (C4). Re-read whenever sync runs.
final teamHistoryDivergedProvider =
    FutureProvider.autoDispose<TeamHistoryDiverged?>((ref) async {
  final session = ref.watch(teamSessionProvider);
  ref.watch(companySyncProvider);
  if (session == null) return null;
  return PrefsTeamHistoryStore().diverged(session.companyId);
});

/// C4: recover this device after the Team server was restored from a
/// backup. See [TeamHistoryRecovery] for what happens and why.
class TeamRecoveryScreen extends ConsumerStatefulWidget {
  const TeamRecoveryScreen({super.key});

  @override
  ConsumerState<TeamRecoveryScreen> createState() => _TeamRecoveryScreenState();
}

class _TeamRecoveryScreenState extends ConsumerState<TeamRecoveryScreen> {
  final _pass = TextEditingController();
  final _pass2 = TextEditingController();
  String? _step;
  String? _error;
  PreparedTeamRecovery? _prepared;
  late final String _recoveryId = _newId();

  @override
  void dispose() {
    _pass.dispose();
    _pass2.dispose();
    super.dispose();
  }

  static String _newId() {
    final r = Random.secure();
    return 'rec-${List.generate(16, (_) => r.nextInt(16).toRadixString(16)).join()}';
  }

  bool get _ready => _pass.text.length >= 10 && _pass.text == _pass2.text;

  Future<void> _check(
      TeamSession session, TeamHistoryDiverged divergence) async {
    setState(() {
      _error = null;
      _prepared = null;
      _step = 'Starting…';
    });
    try {
      final db = await ref.read(mercantisDatabaseProvider.future);
      final dir = await ref.read(atlasDataDirectoryProvider.future);
      final deviceId = await ref.read(deviceIdProvider.future);
      final backup = await ref.read(hubBackupProvider.future);
      final folder = p.join(dir, 'team-recovery', _recoveryId);
      final prepared = await TeamHistoryRecovery(
        live: db.db,
        session: session,
        localDeviceId: deviceId,
        factory: platformDatabaseFactory(),
      ).prepare(
        divergence: divergence,
        recoveryId: _recoveryId,
        stagingPath: p.join(folder, 'staging', atlasDatabaseFileName),
        snapshot: () async {
          final report = await backup.createBackup(
            database: db.db,
            passphrase: _pass.text,
            outputPath: p.join(folder,
                HubBackup.suggestedFileName('before-recovery', DateTime.now())),
            preferences: await HubBackup.readPreferences(),
          );
          return report.path;
        },
        onStep: (s) {
          if (mounted) setState(() => _step = s);
        },
      );
      if (!mounted) return;
      setState(() {
        _step = null;
        _prepared = prepared;
      });
    } on CloudHttpException catch (e) {
      DiagnosticLog.instance.record('team-recovery', e);
      setState(() {
        _step = null;
        _error = '${e.message}\n\nNothing on this device changed. Try again '
            'when the connection is back.';
      });
    } catch (e, s) {
      DiagnosticLog.instance.record('team-recovery', e, s);
      setState(() {
        _step = null;
        _error =
            '${friendlyStorageError(e) ?? 'The check did not complete: $e'}'
            '\n\nNothing on this device changed. You can try again.';
      });
    }
  }

  Future<void> _switch(TeamSession session) async {
    final prepared = _prepared!;
    final db = await ref.read(mercantisDatabaseProvider.future);
    final dir = await ref.read(atlasDataDirectoryProvider.future);
    if (!mounted) return;
    final r = prepared.report;
    await AtlasRestartScope.restart(context,
        message: 'Switching to the Team server’s books…',
        whileStopped: () async {
      await db.close();
      final archive = await TeamHistoryRecovery.switchOver(
        prepared: prepared,
        liveDatabasePath: p.join(dir, atlasDatabaseFileName),
        archiveDirectory: p.join(dir, 'team-recovery', r.recoveryId, 'archive'),
        factory: platformDatabaseFactory(),
        companyId: session.companyId,
        cursorStore: TeamSyncCursorStore(),
        historyStore: PrefsTeamHistoryStore(),
      );
      return RestartNotice(
        success: true,
        title: 'This device is back in step with Atlas Team',
        body: [
          if (r.lost.isNotEmpty)
            '${r.lost.length} official record(s) the server lost are listed '
                'in the recovery report. Enter them again; their old numbers '
                'will not be reused.',
          if (r.carried.isNotEmpty)
            '${r.carried.length} draft(s) or edit(s) were kept and will be '
                'sent on the next sync.',
          if (r.pendingTillSales.isNotEmpty)
            '${r.pendingTillSales.length} till sale(s) will be confirmed on '
                'the next sync.',
          'The previous books are kept on this device '
              '(${p.relative(archive, from: dir)}) and in the encrypted copy '
              '${p.basename(r.snapshotPath ?? '')}.',
        ].join('\n\n'),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final session = ref.watch(teamSessionProvider);
    final divergence = ref.watch(teamHistoryDivergedProvider).valueOrNull;
    final busy = _step != null;
    return ResponsiveScaffold(
      title: 'Recover this device',
      leading: const BackButton(),
      padBody: false,
      body: ListView(
        padding: const EdgeInsets.all(MercantisSpacing.lg),
        children: [
          Text(
            'The Atlas Team server was restored from a backup. Anything '
            'entered on the server after that backup was taken is no longer '
            'there, so this device and the server no longer agree. Sync and '
            'Team posting are paused on this device until it recovers.\n\n'
            'Atlas Team backs up at least once a day, so up to a day of work '
            'can be affected. Nothing is deleted: this device keeps its '
            'current books in an archive and an encrypted copy, and lists '
            'every official record the server no longer has.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: MercantisSpacing.md),
          if (session == null || divergence == null)
            const Text('This device does not need recovering.')
          else ...[
            AtlasSectionCard(
              name: 'Encrypted copy of this device',
              child: Padding(
                padding: const EdgeInsets.all(MercantisSpacing.md),
                child: Column(children: [
                  TextField(
                    controller: _pass,
                    enabled: !busy && _prepared == null,
                    obscureText: true,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Passphrase for the copy',
                      helperText: 'At least 10 characters. Without it nobody '
                          'can open the copy.',
                      helperMaxLines: 2,
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: MercantisSpacing.md),
                  TextField(
                    controller: _pass2,
                    enabled: !busy && _prepared == null,
                    obscureText: true,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Type the passphrase again',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: MercantisSpacing.md),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: busy || !_ready || _prepared != null
                          ? null
                          : () => _check(session, divergence),
                      icon: const Icon(Icons.fact_check_outlined),
                      label: const Text('Copy, then compare with the server'),
                    ),
                  ),
                ]),
              ),
            ),
            if (_prepared != null) ...[
              const SizedBox(height: MercantisSpacing.md),
              TeamRecoveryReportCard(report: _prepared!.report),
              const SizedBox(height: MercantisSpacing.md),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _prepared!.report.canSwitch
                      ? () => _switch(session)
                      : null,
                  icon: const Icon(Icons.swap_horiz),
                  label: const Text('Switch to the server’s books'),
                ),
              ),
            ],
          ],
          if (_step != null)
            Padding(
              padding: const EdgeInsets.all(MercantisSpacing.lg),
              child: Column(children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 12),
                Text(_step!, textAlign: TextAlign.center),
              ]),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: MercantisSpacing.md),
              child: Text(_error!,
                  style: TextStyle(color: theme.colorScheme.error)),
            ),
        ],
      ),
    );
  }
}

class TeamRecoveryReportCard extends StatelessWidget {
  const TeamRecoveryReportCard({super.key, required this.report});
  final TeamRecoveryReport report;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget section(String title, List<String> lines, {bool alert = false}) =>
        Padding(
          padding: const EdgeInsets.only(bottom: MercantisSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: theme.textTheme.titleSmall?.copyWith(
                      color: alert ? theme.colorScheme.error : null)),
              for (final l in lines.take(50))
                Text('• $l', style: theme.textTheme.bodySmall),
              if (lines.length > 50)
                Text('…and ${lines.length - 50} more in the report file.',
                    style: theme.textTheme.bodySmall),
            ],
          ),
        );
    return AtlasSectionCard(
      name: 'What the comparison found',
      child: Padding(
        padding: const EdgeInsets.all(MercantisSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            section(
              report.lost.isEmpty
                  ? 'No official record was lost'
                  : 'Official records the server no longer has '
                      '(${report.lost.length}). Enter them again after the '
                      'switch:',
              [for (final l in report.lost) l.describe()],
              alert: report.lost.isNotEmpty,
            ),
            if (report.numberReused.isNotEmpty)
              section(
                'Numbers the server has since given to other documents. '
                'Tell your accountant:',
                [
                  for (final r in report.numberReused)
                    '${r['doctype']} ${r['number']}: was ${r['lost_document_id']}, '
                        'now ${r['server_document_id']}',
                ],
                alert: true,
              ),
            if (report.reportProblem != null)
              section('The list was not sent to the server',
                  [report.reportProblem!],
                  alert: true),
            if (report.lostReported && report.lost.isNotEmpty)
              section('Numbering', [
                'The server will not issue the lost numbers again.',
              ]),
            section(
              'Kept and sent on the next sync (${report.carried.length})',
              report.carried,
            ),
            if (report.pendingTillSales.isNotEmpty)
              section(
                'Till sales to confirm on the next sync '
                '(${report.pendingTillSales.length})',
                report.pendingTillSales,
              ),
            if (report.notCarried.isNotEmpty)
              section('Edits not kept (${report.notCarried.length})',
                  report.notCarried,
                  alert: true),
            if (report.integrityProblems.isNotEmpty)
              section(
                'The server’s books failed a check, so the switch is not '
                'offered. Send the support report from Help & diagnostics:',
                report.integrityProblems,
                alert: true,
              ),
          ],
        ),
      ),
    );
  }
}
