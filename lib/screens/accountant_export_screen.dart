import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mercantis_core/mercantis_core.dart';

import '../reports/accountant_export.dart';
import '../reports/report_providers.dart';

/// The financial statements the accountant export pack can include (HU1).
final _statements =
    <({String title, FutureProvider<ReportResult> provider})>[
  (title: 'Trial Balance', provider: trialBalanceProvider),
  (title: 'AR Aging', provider: arAgingProvider),
  (title: 'AP Aging', provider: apAgingProvider),
];

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
      final chosen = [
        for (var i = 0; i < _statements.length; i++)
          if (_selected.contains(i)) _statements[i],
      ];
      final parts = <ExportStatement>[];
      for (final s in chosen) {
        final result = await ref.read(s.provider.future);
        parts.add((title: s.title, result: result));
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Accountant export'),
        actions: [
          if (_csv != null)
            IconButton(
              icon: const Icon(Icons.copy_all_outlined),
              tooltip: 'Copy CSV',
              onPressed: _copy,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Statements', style: theme.textTheme.titleMedium),
          Text('Tick what your accountant asked for, then build the CSV pack.',
              style: theme.textTheme.bodySmall),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                for (var i = 0; i < _statements.length; i++)
                  CheckboxListTile(
                    title: Text(_statements[i].title),
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
          const SizedBox(height: 16),
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
              padding: const EdgeInsets.only(top: 12),
              child: Text(_error!,
                  style: TextStyle(color: theme.colorScheme.error)),
            ),
          if (_csv != null) ...[
            const Divider(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('CSV pack', style: theme.textTheme.titleMedium),
                TextButton.icon(
                  onPressed: _copy,
                  icon: const Icon(Icons.copy_all_outlined),
                  label: const Text('Copy'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                _csv!,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
