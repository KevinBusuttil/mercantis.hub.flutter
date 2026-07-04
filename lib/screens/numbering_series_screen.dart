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

    return ResponsiveScaffold(
      title: 'Numbering series',
      // The list / states manage their own padding.
      padBody: false,
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
              // The raw "Next #" and the "Next id" sample were redundant (the
              // sample is the series with the next number already substituted
              // in), which cramped every column on a phone. Show just the id
              // sample; the whole row taps through to set the number, so the
              // "Set" button becomes a trailing chevron. Wider panes get the
              // Series column back for reference.
              LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 560;
                  return ErpDataTable(
                    columns: [
                      const ErpDataColumn(label: 'Document', flex: 4),
                      if (wide) const ErpDataColumn(label: 'Series', flex: 4),
                      const ErpDataColumn(label: 'Next id', flex: 5),
                      const ErpDataColumn(label: '', width: 40, numeric: true),
                    ],
                    rows: [
                      for (final r in rows)
                        ErpDataRow(
                          onTap: () => _edit(context, ref, r),
                          cells: [
                            Text(r.docType),
                            if (wide)
                              Text(r.seriesKey,
                                  style: const TextStyle(fontFeatures: [
                                    FontFeature.tabularFigures()
                                  ])),
                            Text(r.sample,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600)),
                            Icon(Icons.chevron_right,
                                size: 18,
                                color: theme.colorScheme.onSurfaceVariant),
                          ],
                        ),
                    ],
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _edit(
      BuildContext context, WidgetRef ref, NumberingSeriesRow row) {
    return showAtlasBottomSheet<void>(
      context,
      // Small fixed form — a plain modal / desktop dialog, not a draggable sheet.
      draggable: false,
      builder: (_, __) => _SetNextNumberSheet(row: row),
    );
  }
}

class _SetNextNumberSheet extends ConsumerStatefulWidget {
  const _SetNextNumberSheet({required this.row});
  final NumberingSeriesRow row;

  @override
  ConsumerState<_SetNextNumberSheet> createState() =>
      _SetNextNumberSheetState();
}

class _SetNextNumberSheetState extends ConsumerState<_SetNextNumberSheet> {
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
    return AtlasBottomSheet(
      showHandle: false,
      title: '${row.docType} numbering',
      subtitle: 'Series ${row.seriesKey}',
      body: Padding(
        padding: const EdgeInsets.all(MercantisSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
            const SizedBox(height: MercantisSpacing.sm),
            Text(
              'The next document will be numbered accordingly. Lowering this '
              'below an already-issued number can create duplicates.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: MercantisSpacing.md),
                child: Text(_error!,
                    style: TextStyle(color: theme.colorScheme.error)),
              ),
          ],
        ),
      ),
      footer: AtlasBottomActionBar(
        primaryLabel: 'Set number',
        onPrimary: _submit,
        secondaryLabel: 'Cancel',
        onSecondary: () => Navigator.of(context).pop(),
        busy: _busy,
      ),
    );
  }
}
