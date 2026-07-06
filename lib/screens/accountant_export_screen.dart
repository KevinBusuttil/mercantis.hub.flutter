import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';
import 'package:path_provider/path_provider.dart';

import '../reports/accountant_export.dart';
import '../reports/aggregating_reports.dart';
import '../reports/report_providers.dart';

/// The statements the accountant export pack can include. The General Ledger
/// is the journal-lines file accounting software actually imports; the rest
/// are the summaries accountants ask for alongside it.
const _statementTitles = [
  'General Ledger (journal lines)',
  'Trial Balance',
  'Profit & Loss',
  'Balance Sheet',
  'AR Aging',
  'AP Aging',
];

/// Recomputes each statement fresh (so the pack never copies a stale, cached
/// report after mid-session document edits).
Future<ReportResult> _statement(HubAggregatingReports reports, int index,
    Set<String> roles, String? fromDate, String? toDate) {
  switch (index) {
    case 0:
      return reports.generalLedgerJournal(
          fromDate: fromDate, toDate: toDate, userRoles: roles);
    case 1:
      return reports.trialBalance(userRoles: roles);
    case 2:
      return reports.profitAndLoss(userRoles: roles);
    case 3:
      return reports.balanceSheet(userRoles: roles);
    case 4:
      return reports.arAging(userRoles: roles);
    default:
      return reports.apAging(userRoles: roles);
  }
}

/// HU1 / Phase 8 — accountant export: tick the statements the accountant
/// asked for, window the GL journal to the period, and hand the pack over as
/// a real CSV file (with clipboard as the quick fallback).
class AccountantExportScreen extends ConsumerStatefulWidget {
  const AccountantExportScreen({super.key});

  @override
  ConsumerState<AccountantExportScreen> createState() =>
      _AccountantExportScreenState();
}

class _AccountantExportScreenState
    extends ConsumerState<AccountantExportScreen> {
  final Set<int> _selected = {0, 1, 2, 3, 4, 5};
  final _fromController = TextEditingController();
  final _toController = TextEditingController();
  String? _csv;
  bool _building = false;
  String? _error;

  @override
  void dispose() {
    _fromController.dispose();
    _toController.dispose();
    super.dispose();
  }

  String? _isoOrNull(TextEditingController c) {
    final t = c.text.trim();
    return t.isEmpty ? null : t;
  }

  Future<void> _build() async {
    if (_selected.isEmpty) return;
    setState(() {
      _building = true;
      _error = null;
    });
    try {
      // Recompute each selected statement fresh from the store on every build.
      final reports = await ref.read(aggregatingReportsProvider.future);
      final roles = ref.read(currentUserProvider).roles;
      final parts = <ExportStatement>[];
      for (var i = 0; i < _statementTitles.length; i++) {
        if (!_selected.contains(i)) continue;
        parts.add((
          title: _statementTitles[i],
          result: await _statement(reports, i, roles,
              _isoOrNull(_fromController), _isoOrNull(_toController)),
        ));
      }
      if (!mounted) return;
      setState(() {
        _csv = buildAccountantExport(parts);
        _building = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _building = false;
      });
    }
  }

  /// Saves the pack as a CSV file the accountant can be sent — the desktop
  /// picker where available, the app documents folder otherwise.
  Future<void> _saveFile() async {
    final csv = _csv;
    if (csv == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final stamp = DateTime.now().toIso8601String().split('T').first;
    final suggested = 'atlas-export-$stamp.csv';
    try {
      String? path;
      if (!kIsWeb &&
          (Platform.isLinux || Platform.isMacOS || Platform.isWindows)) {
        path = await FilePicker.platform.saveFile(
          dialogTitle: 'Save accountant export',
          fileName: suggested,
          type: FileType.custom,
          allowedExtensions: const ['csv'],
        );
        if (path == null) return; // user cancelled
      } else {
        final dir = await getApplicationDocumentsDirectory();
        path = '${dir.path}/$suggested';
      }
      await File(path).writeAsString(csv);
      messenger.showSnackBar(SnackBar(content: Text('Saved to $path')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not save: $e')));
    }
  }

  Future<void> _copy() async {
    final csv = _csv;
    if (csv == null) return;
    await Clipboard.setData(ClipboardData(text: csv));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Export pack copied to clipboard')));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ResponsiveScaffold(
      title: 'Accountant export',
      // Surface a back affordance when reached via a push (no AppBar here).
      leading: Navigator.of(context).canPop() ? const BackButton() : null,
      padBody: false,
      actions: [
        if (_csv != null) ...[
          IconButton(
            icon: const Icon(Icons.save_alt_outlined),
            tooltip: 'Save CSV file',
            onPressed: _saveFile,
          ),
          IconButton(
            icon: const Icon(Icons.copy_all_outlined),
            tooltip: 'Copy CSV',
            onPressed: _copy,
          ),
        ],
      ],
      body: ListView(
        padding: const EdgeInsets.all(MercantisSpacing.lg),
        children: [
          Text('Tick what your accountant asked for, then build the pack and '
              'save it as a CSV file.',
              style: theme.textTheme.bodySmall),
          const SizedBox(height: MercantisSpacing.sm),
          AtlasSectionCard(
            name: 'Statements',
            child: Column(
              children: [
                for (var i = 0; i < _statementTitles.length; i++)
                  CheckboxListTile(
                    title: Text(_statementTitles[i]),
                    value: _selected.contains(i),
                    onChanged: _building
                        ? null
                        : (on) => setState(() {
                              if (on == true) {
                                _selected.add(i);
                              } else {
                                _selected.remove(i);
                              }
                              _csv = null;
                            }),
                  ),
              ],
            ),
          ),
          const SizedBox(height: MercantisSpacing.md),
          AtlasSectionCard(
            name: 'Journal period (optional)',
            child: Padding(
              padding: const EdgeInsets.all(MercantisSpacing.md),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _fromController,
                      decoration: const InputDecoration(
                        labelText: 'From (YYYY-MM-DD)',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => setState(() => _csv = null),
                    ),
                  ),
                  const SizedBox(width: MercantisSpacing.md),
                  Expanded(
                    child: TextField(
                      controller: _toController,
                      decoration: const InputDecoration(
                        labelText: 'To (YYYY-MM-DD)',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => setState(() => _csv = null),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: MercantisSpacing.lg),
          FilledButton.icon(
            onPressed: (_building || _selected.isEmpty) ? null : _build,
            icon: _building
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.description_outlined),
            label: const Text('Build export pack'),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: MercantisSpacing.md),
              child: Text(_error!,
                  style: TextStyle(color: theme.colorScheme.error)),
            ),
          if (_csv != null) ...[
            const SizedBox(height: MercantisSpacing.lg),
            AtlasSectionCard(
              name: 'CSV pack',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton.icon(
                        onPressed: _saveFile,
                        icon: const Icon(Icons.save_alt_outlined),
                        label: const Text('Save file'),
                      ),
                      TextButton.icon(
                        onPressed: _copy,
                        icon: const Icon(Icons.copy_all_outlined),
                        label: const Text('Copy'),
                      ),
                    ],
                  ),
                  const SizedBox(height: MercantisSpacing.sm),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(MercantisSpacing.md),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: MercantisRadius.rSm,
                    ),
                    child: SelectableText(
                      _csv!,
                      style:
                          const TextStyle(fontFamily: 'monospace', fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
