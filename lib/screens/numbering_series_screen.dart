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
      // Opened from Settings via Navigator.push — ResponsiveScaffold has no
      // AppBar, so surface a back affordance when the route can pop.
      leading: Navigator.of(context).canPop() ? const BackButton() : null,
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
              const _NumberingPolicyBanner(),
              const SizedBox(height: MercantisSpacing.lg),
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
                            Text(r.onHold ? '${r.sample} (on hold)' : r.sample,
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
              'The next document will be numbered accordingly. The number '
              'can only move forward: a number already issued is never '
              'issued again. The change is recorded in the audit log.',
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


/// The numbering policy in force: normal, on hold after a restore (with the
/// two recovery decisions), or a recovery series.
class _NumberingPolicyBanner extends ConsumerWidget {
  const _NumberingPolicyBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final policy = ref.watch(numberingPolicyProvider);
    return policy.when(
      loading: () => const SizedBox.shrink(),
      error: (e, _) => Text('Could not read the numbering policy: $e'),
      data: (p) {
        if (p.holds.isNotEmpty) {
          return Card(
            color: theme.colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(MercantisSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('New invoices, receipts and payments are on hold',
                      style: theme.textTheme.titleMedium),
                  const SizedBox(height: MercantisSpacing.sm),
                  const Text(
                      'These books were restored from a backup, and nothing '
                      'on this device shows which numbers were issued after '
                      'it was made. Issuing them again would give two '
                      'documents the same number. Check your records (the '
                      'last invoice you sent, the last receipt printed), then '
                      'choose one:'),
                  const SizedBox(height: MercantisSpacing.md),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    FilledButton(
                      onPressed: () => showAtlasBottomSheet<void>(context,
                          draggable: false,
                          builder: (_, __) => const _ConfirmLastIssuedSheet()),
                      child: const Text('Confirm the last numbers issued…'),
                    ),
                    OutlinedButton(
                      onPressed: () => _startRecoverySeries(context, ref),
                      child: const Text('Start a recovery series…'),
                    ),
                  ]),
                ],
              ),
            ),
          );
        }
        if (p.segment != null) {
          return Card(
            child: ListTile(
              leading: const Icon(Icons.info_outline),
              title: Text('Recovery series ${p.segment} in use'),
              subtitle: Text('Official documents continue as, for example, '
                  'SINV-…-${p.segment}-0001 after a restore whose last '
                  'numbers could not be verified. The decision is in the '
                  'audit log.'),
            ),
          );
        }
        return Text(
          'Normal numbering. A number already issued is never issued again, '
          'including after restoring a backup.',
          style: theme.textTheme.bodySmall,
        );
      },
    );
  }

  Future<void> _startRecoverySeries(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Start a recovery series?'),
        content: const Text(
            'Official documents (invoices, credit notes, receipts, payments '
            'and the rest) will continue in a separate series, for example '
            'SINV-2026-R1-0001, so they cannot clash with numbers issued '
            'after the backup.\n\nOnly do this if a separate series is '
            'acceptable to your tax authority and accountant. Some '
            'jurisdictions require one unbroken sequence; there, confirm the '
            'last numbers issued instead.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Start recovery series')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final segment =
        await ref.read(numberingSeriesControllerProvider).startRecoverySeries();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Recovery series $segment started.')));
  }
}

/// Decision 1 after an unverifiable restore: the operator states the last
/// number issued in each official series.
class _ConfirmLastIssuedSheet extends ConsumerStatefulWidget {
  const _ConfirmLastIssuedSheet();

  @override
  ConsumerState<_ConfirmLastIssuedSheet> createState() =>
      _ConfirmLastIssuedSheetState();
}

class _ConfirmLastIssuedSheetState
    extends ConsumerState<_ConfirmLastIssuedSheet> {
  final _fields = <String, TextEditingController>{};
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit(List<NumberingSeriesRow> rows) async {
    final last = <String, int>{};
    for (final r in rows) {
      final n = int.tryParse(_fields[r.seriesKey]!.text.trim());
      if (n == null || n < 0) {
        setState(() => _error = 'Enter a number for ${r.docType}.');
        return;
      }
      last[r.seriesKey] = n;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(numberingSeriesControllerProvider).confirmLastIssued(last);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Numbering confirmed. New documents can be issued.')));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e is ArgumentError ? '${e.message}' : '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = ref.watch(numberingSeriesProvider).valueOrNull ?? const [];
    final official = [
      for (final r in rows)
        if (r.official) r,
    ];
    for (final r in official) {
      _fields.putIfAbsent(r.seriesKey,
          () => TextEditingController(text: '${r.nextNumber - 1}'));
    }
    return AtlasBottomSheet(
      showHandle: false,
      title: 'Last numbers issued',
      subtitle: 'From your own records, not from this device',
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(MercantisSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Each box shows the last number in the restored '
                'books. Change it if you issued more after the backup. It '
                'cannot be lower. You confirm this in your name, and it is '
                'recorded in the audit log.'),
            const SizedBox(height: MercantisSpacing.md),
            for (final r in official)
              Padding(
                padding: const EdgeInsets.only(bottom: MercantisSpacing.sm),
                child: TextField(
                  controller: _fields[r.seriesKey],
                  enabled: !_busy,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    labelText: '${r.docType} (${r.seriesKey}…)',
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
            if (_error != null)
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          ],
        ),
      ),
      footer: AtlasBottomActionBar(
        primaryLabel: 'Confirm',
        onPrimary: () => _submit(official),
        secondaryLabel: 'Cancel',
        onSecondary: () => Navigator.of(context).pop(),
        busy: _busy,
      ),
    );
  }
}
