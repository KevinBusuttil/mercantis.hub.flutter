import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

import '../numbering/numbering_series.dart';

/// Inspect and manage the document naming series. Lists every counter-bearing
/// series with the number it will mint next, and lets you set that number (to
/// continue a legacy sequence or reset at year start).
class NumberingSeriesScreen extends ConsumerWidget {
  const NumberingSeriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(numberingSeriesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Numbering series')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (rows) {
          if (rows.isEmpty) {
            return const EmptyState(
              title: 'No numbering series',
              message: 'No DocTypes define a counter-based naming series.',
              icon: Icons.tag,
            );
          }
          return ListView(
            padding: const EdgeInsets.all(MercantisSpacing.xl),
            children: [
              Text(
                'Each series sequences independently for the current year. '
                'Setting the next number affects only future documents.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: MercantisSpacing.lg),
              ErpDataTable(
                columns: const [
                  ErpDataColumn(label: 'Document', flex: 4),
                  ErpDataColumn(label: 'Series', flex: 4),
                  ErpDataColumn(label: 'Next #', flex: 2, numeric: true),
                  ErpDataColumn(label: 'Next id', flex: 4),
                  ErpDataColumn(label: '', flex: 2),
                ],
                rows: [
                  for (final r in rows)
                    ErpDataRow(
                      onTap: () => _edit(context, ref, r),
                      cells: [
                        Text(r.docType),
                        Text(r.seriesKey,
                            style: const TextStyle(
                                fontFeatures: [FontFeature.tabularFigures()])),
                        Text('${r.nextNumber}'),
                        Text(r.sample,
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                        TextButton(
                          onPressed: () => _edit(context, ref, r),
                          child: const Text('Set'),
                        ),
                      ],
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _edit(
      BuildContext context, WidgetRef ref, NumberingSeriesRow row) {
    return showDialog<void>(
      context: context,
      builder: (_) => _SetNextNumberDialog(row: row),
    );
  }
}

class _SetNextNumberDialog extends ConsumerStatefulWidget {
  const _SetNextNumberDialog({required this.row});
  final NumberingSeriesRow row;

  @override
  ConsumerState<_SetNextNumberDialog> createState() =>
      _SetNextNumberDialogState();
}

class _SetNextNumberDialogState extends ConsumerState<_SetNextNumberDialog> {
  late final TextEditingController _value =
      TextEditingController(text: '${widget.row.nextNumber}');
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final n = int.tryParse(_value.text.trim());
    if (n == null || n < 1) {
      setState(() => _error = 'Enter a whole number of 1 or more.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(numberingSeriesControllerProvider)
          .setNextNumber(widget.row.seriesKey, n);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${widget.row.docType} next number set to $n')));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final row = widget.row;
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text('${row.docType} numbering'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Series ${row.seriesKey}', style: theme.textTheme.bodySmall),
          const SizedBox(height: 12),
          TextField(
            controller: _value,
            enabled: !_busy,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'Next number',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'The next document will be numbered accordingly. Lowering this '
            'below an already-issued number can create duplicates.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_error!,
                  style: TextStyle(color: theme.colorScheme.error)),
            ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel')),
        FilledButton(
            onPressed: _busy ? null : _submit, child: const Text('Set number')),
      ],
    );
  }
}
