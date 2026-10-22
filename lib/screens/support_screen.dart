import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

import '../backup/hub_backup.dart';
import '../settings/hub_settings.dart';
import '../support/diagnostic_log.dart';
import '../support/support_diagnostics.dart';
import '../sync/company_sync.dart';
import 'backup_restore_screen.dart' show hubBackupProvider;

/// Builds the diagnostics bundle for this device from the live providers.
final supportDiagnosticsProvider =
    FutureProvider.autoDispose<DiagnosticsReport>((ref) async {
  final db = await ref.watch(mercantisDatabaseProvider.future);
  final dir = await ref.watch(atlasDataDirectoryProvider.future);
  final backup = await ref.watch(hubBackupProvider.future);
  String? deviceId;
  try {
    deviceId = await ref.watch(deviceIdProvider.future);
  } catch (_) {}
  return SupportDiagnostics.collect(
    database: db.db,
    dataDirectory: dir,
    settings: ref.read(hubSettingsProvider),
    sync: ref.read(companySyncProvider).valueOrNull,
    deviceId: deviceId,
    lastBackupAt: await HubBackup.lastBackupAt(),
    localBackupCount: backup.localBackups().length,
    events: DiagnosticLog.instance.events,
  );
});

/// Settings › Help & diagnostics: what support needs, shown to the customer
/// in full before anything leaves the device (plan M1.6, support readiness).
class SupportScreen extends ConsumerWidget {
  const SupportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final report = ref.watch(supportDiagnosticsProvider);
    return ResponsiveScaffold(
      title: 'Help & diagnostics',
      padBody: false,
      body: report.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(MercantisSpacing.lg),
            child: Text('Diagnostics could not be collected: '
                '${DiagnosticRedactor.redact('$e')}'),
          ),
        ),
        data: (r) => DiagnosticsReportView(
          report: r,
          onRefresh: () => ref.invalidate(supportDiagnosticsProvider),
          onClearErrors: () async {
            await DiagnosticLog.instance.clear();
            ref.invalidate(supportDiagnosticsProvider);
          },
        ),
      ),
    );
  }
}

/// The bundle, its privacy promise and the export actions. Also used by the
/// start-up error screen, where no providers are available.
class DiagnosticsReportView extends StatelessWidget {
  const DiagnosticsReportView({
    super.key,
    required this.report,
    this.onRefresh,
    this.onClearErrors,
  });

  final DiagnosticsReport report;
  final VoidCallback? onRefresh;
  final Future<void> Function()? onClearErrors;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = report.toText();
    return ListView(
      padding: const EdgeInsets.all(MercantisSpacing.lg),
      children: [
        Text('If Atlas is not behaving as expected, send this report to '
            'Atlas support with a short description of what happened.',
            style: theme.textTheme.bodyLarge),
        const SizedBox(height: 8),
        Semantics(
          container: true,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.verified_user_outlined,
                  color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                    'It contains version, device and status information and '
                    'record counts. It does not contain customer or supplier '
                    'names, amounts, documents, attachments or passwords. '
                    'Read it below before sending.',
                    style: theme.textTheme.bodyMedium),
              ),
            ],
          ),
        ),
        const SizedBox(height: MercantisSpacing.lg),
        Text('Diagnostic id: ${report.diagnosticId}',
            style: theme.textTheme.titleMedium),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: () => _save(context, text),
              icon: const Icon(Icons.save_alt),
              label: const Text('Save report'),
            ),
            OutlinedButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: text));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('Report copied. Paste it into your '
                          'message to support.')));
                }
              },
              icon: const Icon(Icons.copy),
              label: const Text('Copy report'),
            ),
            if (onRefresh != null)
              OutlinedButton.icon(
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh'),
              ),
            if (onClearErrors != null)
              TextButton.icon(
                onPressed: () => _confirmClear(context),
                icon: const Icon(Icons.delete_outline),
                label: const Text('Clear error history'),
              ),
          ],
        ),
        const SizedBox(height: MercantisSpacing.lg),
        AtlasSectionCard(
          name: 'Report contents',
          child: SelectableText(
            text,
            style: theme.textTheme.bodySmall
                ?.copyWith(fontFamily: 'monospace', height: 1.4),
          ),
        ),
      ],
    );
  }

  Future<void> _confirmClear(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Clear error history?'),
        content: const Text('The list of recent errors on this device is '
            'deleted. Your business records are not affected.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Keep')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Clear')),
        ],
      ),
    );
    if (ok == true) await onClearErrors?.call();
  }

  Future<void> _save(BuildContext context, String text) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final bytes = Uint8List.fromList(utf8.encode(text));
      final desktop = !kIsWeb &&
          (Platform.isLinux || Platform.isMacOS || Platform.isWindows);
      final dest = await FilePicker.platform.saveFile(
        dialogTitle: 'Save the diagnostics report',
        fileName: report.suggestedFileName,
        // Mobile: the system save sheet writes the bytes itself.
        bytes: desktop ? null : bytes,
      );
      if (dest == null) return;
      if (desktop) await File(dest).writeAsBytes(bytes, flush: true);
      messenger.showSnackBar(const SnackBar(content: Text('Report saved')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(
          content: Text('Could not save the report. Use Copy instead. '
              '(${DiagnosticRedactor.redact('$e')})')));
    }
  }
}
