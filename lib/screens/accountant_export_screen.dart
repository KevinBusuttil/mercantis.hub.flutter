import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

import '../reports/accountant_export.dart';
import '../reports/aggregating_reports.dart';
import '../reports/report_providers.dart';

/// The financial statements the accountant export pack can include (HU1).
const _statementTitles = ['Trial Balance', 'AR Aging', 'AP Aging'];

/// Recomputes each statement fresh (so the pack never copies a stale, cached
/// report after mid-session document edits).
Future<ReportResult> _statement(
    HubAggregatingReports reports, int index, Set<String> roles) {
  switch (index) {
    case 0:
      return reports.trialBalance(userRoles: roles);
    case 1:
      return reports.arAging(userRoles: roles);
    default:
      return reports.apAging(userRoles: roles);
  }
}

/// HU1 — accountant export: tick the statements the accountant asked for and
/// build a single CSV pack to hand over (copy to clipboard).
class AccountantExportScreen extends ConsumerStatefulWidget {
  const AccountantExportScreen({super.key});

  @override
  ConsumerState<AccountantExportScreen> createState() =>
      _AccountantExportScreenState();
}

class _AccountantExportScreenState
    extends ConsumerState<AccountantExportScreen> {
  final Set<int> _selected = {0, 1, 2};
  String? _csv;
  bool _building = false;
  String? _error;

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
          result: await _statement(reports, i, roles),
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
      padBody: false,
      actions: [
        if (_csv != null)
          IconButton(
            icon: const Icon(Icons.copy_all_outlined),
            tooltip: 'Copy CSV',
            onPressed: _copy,
          ),
      ],
      body: ListView(
        padding: const EdgeInsets.all(MercantisSpacing.lg),
        children: [
          Text('Tick what your accountant asked for, then build the CSV pack.',
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
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: _copy,
                      icon: const Icon(Icons.copy_all_outlined),
                      label: const Text('Copy'),
                    ),
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
