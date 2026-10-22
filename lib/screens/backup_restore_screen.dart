import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';
import 'package:path/path.dart' as p;

import '../backup/app_restart.dart';
import '../backup/hub_backup.dart';
import '../ledger/ledger_derivation_service.dart';
import '../team/team_session.dart';

/// The Hub's backup helper for this device's data folder.
final hubBackupProvider = FutureProvider<HubBackup>((ref) async {
  final dir = await ref.watch(atlasDataDirectoryProvider.future);
  return HubBackup(dataDirectory: dir, factory: platformDatabaseFactory());
});

/// What the screen shows about this device's backups.
final _backupStatusProvider = FutureProvider.autoDispose<
    ({DateTime? lastBackup, List<File> local, int owedPostings})>((ref) async {
  final backup = await ref.watch(hubBackupProvider.future);
  final ledger = await ref.watch(ledgerDerivationServiceProvider.future);
  return (
    lastBackup: await HubBackup.lastBackupAt(),
    local: backup.localBackups(),
    owedPostings: (await ledger.outstandingPostings()).length,
  );
});

String _date(DateTime d) {
  final l = d.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${l.year}-${two(l.month)}-${two(l.day)} ${two(l.hour)}:${two(l.minute)}';
}

String _size(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

bool get _isDesktop =>
    !kIsWeb && (Platform.isLinux || Platform.isMacOS || Platform.isWindows);

/// Backup & restore (M1.4): make an encrypted backup of the whole business,
/// keep a copy somewhere other than this device, and restore one onto this
/// or a new device.
class BackupRestoreScreen extends ConsumerStatefulWidget {
  const BackupRestoreScreen({super.key});

  @override
  ConsumerState<BackupRestoreScreen> createState() =>
      _BackupRestoreScreenState();
}

class _BackupRestoreScreenState extends ConsumerState<BackupRestoreScreen> {
  String? _busy;
  BackupReport? _lastReport;

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(_backupStatusProvider);
    final theme = Theme.of(context);
    return ResponsiveScaffold(
      title: 'Backup & restore',
      leading: Navigator.of(context).canPop() ? const BackButton() : null,
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_busy != null)
            Card(
              child: ListTile(
                leading: const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2)),
                title: Text(_busy!),
                subtitle: const Text('Keep Atlas open until this finishes.'),
              ),
            ),
          status.when(
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => Text('Could not read backup status: $e'),
            data: (s) => _statusCard(theme, s.lastBackup, s.owedPostings),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Back up', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  const Text(
                      'A backup is one encrypted file with all your records, '
                      'attachments and settings. You choose a recovery '
                      'passphrase; Atlas never stores it. Without it the '
                      'backup cannot be opened by anyone, including you.'),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _busy == null ? _backUp : null,
                    icon: const Icon(Icons.backup_outlined),
                    label: const Text('Back up now'),
                  ),
                  if (_lastReport != null) _reportTile(theme, _lastReport!),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          status.maybeWhen(
            data: (s) => s.local.isEmpty
                ? const SizedBox.shrink()
                : Card(
                    child: Column(children: [
                      const ListTile(
                        title: Text('Backups on this device'),
                        subtitle: Text('These are lost with the device. Save '
                            'a copy somewhere else as well.'),
                      ),
                      for (final f in s.local.take(5))
                        ListTile(
                          leading: const Icon(Icons.insert_drive_file_outlined),
                          title: Text(p.basename(f.path)),
                          subtitle: Text(
                              '${_date(f.statSync().modified)} · ${_size(f.lengthSync())}'),
                          trailing: IconButton(
                            tooltip: 'Save a copy elsewhere',
                            icon: const Icon(Icons.save_alt),
                            onPressed: () => _saveCopy(f.path),
                          ),
                        ),
                    ]),
                  ),
            orElse: () => const SizedBox.shrink(),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Restore', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  const Text(
                      'Restoring replaces everything on this device with the '
                      'backup. Atlas checks the whole file first and changes '
                      'nothing if it is damaged, made by a newer version, or '
                      'the passphrase is wrong.'),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _busy == null ? _restore : null,
                    icon: const Icon(Icons.settings_backup_restore),
                    label: const Text('Restore from a backup file…'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusCard(ThemeData theme, DateTime? last, int owed) {
    final stale = last == null ||
        DateTime.now().difference(last) > const Duration(days: 7);
    return Card(
      color: stale ? theme.colorScheme.errorContainer : null,
      child: Column(children: [
        ListTile(
          leading: Icon(stale ? Icons.warning_amber_rounded : Icons.verified),
          title: Text(last == null
              ? 'No backup has been made on this device'
              : 'Last backup ${_date(last)}'),
          subtitle: Text(stale
              ? 'If this device is lost or breaks, your books go with it. '
                  'Back up at least weekly and keep a copy off this device.'
              : 'Keep a copy somewhere other than this device.'),
        ),
        if (owed > 0)
          ListTile(
            leading: const Icon(Icons.sync_problem),
            title: Text('$owed document${owed == 1 ? '' : 's'} still '
                'owe${owed == 1 ? 's' : ''} ledger postings'),
            subtitle: const Text('Atlas retries these every time it starts. '
                'If this stays, contact support before relying on reports.'),
          ),
      ]),
    );
  }

  Widget _reportTile(ThemeData theme, BackupReport r) {
    final missing = r.missingAttachments;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Backup saved: ${p.basename(r.path)} (${_size(r.bytes)})',
            style: theme.textTheme.bodyMedium),
        if (missing.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '${missing.length} attachment${missing.length == 1 ? ' was' : 's were'} '
              'not included because the file is missing or damaged on this '
              'device: ${missing.take(3).map((m) => m.storagePath).join(', ')}'
              '${missing.length > 3 ? '…' : ''}',
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ),
        const SizedBox(height: 8),
        FilledButton.tonalIcon(
          onPressed: () => _saveCopy(r.path),
          icon: const Icon(Icons.save_alt),
          label: const Text('Save a copy to another place…'),
        ),
      ]),
    );
  }

  Future<String?> _askPassphrase({required bool confirm}) => showDialog<String>(
        context: context,
        builder: (_) => _PassphraseDialog(confirm: confirm),
      );

  Future<void> _backUp() async {
    final messenger = ScaffoldMessenger.of(context);
    final pass = await _askPassphrase(confirm: true);
    if (pass == null) return;
    setState(() => _busy = 'Making an encrypted backup…');
    try {
      final backup = await ref.read(hubBackupProvider.future);
      final db = await ref.read(mercantisDatabaseProvider.future);
      final report = await backup.createBackup(
        database: db.db,
        passphrase: pass,
        preferences: await HubBackup.readPreferences(),
      );
      await HubBackup.recordBackup(DateTime.now());
      if (!mounted) return;
      setState(() {
        _busy = null;
        _lastReport = report;
      });
      ref.invalidate(_backupStatusProvider);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = null);
      messenger.showSnackBar(SnackBar(
          content: Text(e is BackupException
              ? e.message
              : 'The backup did not complete and nothing was saved: $e')));
    }
  }

  Future<void> _saveCopy(String path) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final name = p.basename(path);
      if (_isDesktop) {
        final dest = await FilePicker.platform.saveFile(
          dialogTitle: 'Save a copy of the backup',
          fileName: name,
        );
        if (dest == null) return;
        await File(path).copy(dest);
        messenger.showSnackBar(SnackBar(content: Text('Copy saved to $dest')));
      } else {
        // Mobile: the system save sheet (Files, Drive, iCloud, USB…).
        final dest = await FilePicker.platform.saveFile(
          dialogTitle: 'Save a copy of the backup',
          fileName: name,
          bytes: await File(path).readAsBytes(),
        );
        if (dest == null) return;
        messenger.showSnackBar(const SnackBar(content: Text('Copy saved')));
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not save a copy: $e')));
    }
  }

  Future<void> _restore() async {
    final messenger = ScaffoldMessenger.of(context);
    if (ref.read(teamSessionProvider) != null) {
      messenger.showSnackBar(const SnackBar(
          content: Text('This device is connected to Atlas Team. Disconnect '
              'it first: Team books are restored on the Team server, not '
              'from a device backup.')));
      return;
    }
    final picked = await FilePicker.platform.pickFiles(dialogTitle: 'Choose a backup');
    final path = picked?.files.single.path;
    if (path == null) return;
    try {
      await AtlasBackupService.readHeader(path);
    } on BackupException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
      return;
    }
    final pass = await _askPassphrase(confirm: false);
    if (pass == null) return;

    setState(() => _busy = 'Checking the backup…');
    final backup = await ref.read(hubBackupProvider.future);
    StagedRestore staged;
    try {
      staged = await backup.stage(path, pass);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = null);
      messenger.showSnackBar(SnackBar(
          duration: const Duration(seconds: 8),
          content: Text(e is BackupException
              ? '${e.message} Nothing on this device was changed.'
              : 'The backup could not be read. Nothing was changed. ($e)')));
      return;
    }
    if (!mounted) return;
    setState(() => _busy = null);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => _ConfirmRestoreDialog(staged: staged),
    );
    if (confirmed != true) {
      staged.discard();
      return;
    }
    if (!mounted) return;

    final db = await ref.read(mercantisDatabaseProvider.future);
    if (!mounted) return;
    await AtlasRestartScope.restart(context, whileStopped: () async {
      await db.close();
      try {
        final outcome = await backup.commit(staged);
        await HubBackup.applyRestoredPreferences(staged);
        final created = DateTime.tryParse('${staged.manifest['created_at']}');
        return RestartNotice(
          success: true,
          title: 'Restore complete',
          body: 'Your books as of ${created == null ? 'the backup' : _date(created)} '
              'are on this device. Atlas checked every file and confirmed '
              'the trial balance, receivables, payables, stock and bank '
              'totals match the backup to the cent.'
              '${outcome.safetyCopyDirectory == null ? '' : ' The data that was replaced is kept as a safety copy until the next restore.'}'
              ' Folder sync is off; turn it on again in Settings if you use it.',
        );
      } on RestoreVerificationException catch (e) {
        return RestartNotice(
          success: false,
          title: 'Restore stopped, nothing changed',
          body: 'The restored data did not match the backup, so Atlas put '
              'your previous data back exactly as it was. '
              '${e.problems.take(3).join('; ')}',
        );
      } catch (e) {
        return RestartNotice(
          success: false,
          title: 'Restore stopped, nothing changed',
          body: 'Atlas put your previous data back exactly as it was. '
              'Details: $e',
        );
      }
    });
  }
}

class _PassphraseDialog extends StatefulWidget {
  const _PassphraseDialog({required this.confirm});
  final bool confirm;

  @override
  State<_PassphraseDialog> createState() => _PassphraseDialogState();
}

class _PassphraseDialogState extends State<_PassphraseDialog> {
  final _a = TextEditingController();
  final _b = TextEditingController();
  bool _hidden = true;
  String? _error;

  @override
  void dispose() {
    _a.dispose();
    _b.dispose();
    super.dispose();
  }

  void _submit() {
    final a = _a.text;
    if (widget.confirm) {
      try {
        BackupCipher.checkPassphrase(a);
      } on BackupException catch (e) {
        setState(() => _error = e.message);
        return;
      }
      if (a != _b.text) {
        setState(() => _error = 'The two passphrases do not match.');
        return;
      }
    } else if (a.isEmpty) {
      return;
    }
    Navigator.of(context).pop(a);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.confirm
          ? 'Choose a recovery passphrase'
          : 'Enter the recovery passphrase'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (widget.confirm)
            const Text(
                'Write it down and keep it apart from the backup file. Atlas '
                'does not store it and cannot recover it.'),
          TextField(
            controller: _a,
            obscureText: _hidden,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'Passphrase',
              suffixIcon: IconButton(
                tooltip: _hidden ? 'Show' : 'Hide',
                icon: Icon(_hidden ? Icons.visibility : Icons.visibility_off),
                onPressed: () => setState(() => _hidden = !_hidden),
              ),
            ),
            onSubmitted: (_) => widget.confirm ? null : _submit(),
          ),
          if (widget.confirm)
            TextField(
              controller: _b,
              obscureText: _hidden,
              decoration: const InputDecoration(labelText: 'Type it again'),
              onSubmitted: (_) => _submit(),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
        ]),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: const Text('Continue')),
      ],
    );
  }
}

class _ConfirmRestoreDialog extends StatefulWidget {
  const _ConfirmRestoreDialog({required this.staged});
  final StagedRestore staged;

  @override
  State<_ConfirmRestoreDialog> createState() => _ConfirmRestoreDialogState();
}

class _ConfirmRestoreDialogState extends State<_ConfirmRestoreDialog> {
  final _typed = TextEditingController();

  @override
  void dispose() {
    _typed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.staged.businessSummary;
    final m = widget.staged.manifest;
    final created = DateTime.tryParse('${m['created_at']}');
    final companies = (s['companies'] as List?)?.join(', ') ?? '';
    final counts = Map<String, Object?>.from(
        (s['submitted_counts'] as Map?) ?? const {});
    int n(String t) => (counts[t] as int?) ?? 0;
    final missing = widget.staged.missingAttachments.length;
    final ok = _typed.text.trim().toUpperCase() == 'REPLACE';
    return AlertDialog(
      title: const Text('Replace the data on this device?'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('The backup checked out: it is complete, unchanged and '
                'readable by this version of Atlas.'),
            const SizedBox(height: 12),
            _row('Business', companies.isEmpty ? '—' : companies),
            _row('Backup made',
                created == null ? 'unknown' : _date(created)),
            _row('Made by', '${m['app_version'] ?? 'unknown'}'),
            _row('Sales invoices', '${n('Sales Invoice')}'),
            _row('Purchase invoices', '${n('Purchase Invoice')}'),
            _row('Payments', '${n('Payment Entry')}'),
            _row('Attachments', '${s['attachments'] ?? 0}'),
            _row('Trial balance',
                'Dr ${s['gl_total_debit']} / Cr ${s['gl_total_credit']}'),
            _row('Receivables', '${s['receivables_outstanding']}'),
            _row('Payables', '${s['payables_outstanding']}'),
            _row('Stock value', '${s['stock_value']}'),
            _row('Bank and cash', '${s['bank_and_cash']}'),
            if (missing > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                    '$missing attachment${missing == 1 ? ' was' : 's were'} '
                    'already missing when this backup was made and will not '
                    'come back.',
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.error)),
              ),
            const SizedBox(height: 12),
            const Text(
                'Everything currently on this device is replaced. Anything '
                'recorded here after the backup was made will be gone from '
                'the books. Atlas keeps the replaced data as a safety copy '
                'until the next restore, and puts it back automatically if '
                'the restore is interrupted or does not verify.'),
            const SizedBox(height: 8),
            const Text(
                'Document numbers continue from the backup. If you issued '
                'invoices after it was made, note their numbers and re-enter '
                'them.'),
            const SizedBox(height: 12),
            TextField(
              controller: _typed,
              decoration:
                  const InputDecoration(labelText: 'Type REPLACE to continue'),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: ok ? () => Navigator.of(context).pop(true) : null,
          child: const Text('Restore'),
        ),
      ],
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 130, child: Text(label)),
            Expanded(child: Text(value, textAlign: TextAlign.end)),
          ],
        ),
      );
}
