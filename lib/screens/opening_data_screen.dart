import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

import '../migration/opening_reconciliation.dart';
import '../migration/opening_take_on.dart';
import '../migration/take_on_templates.dart';
import '../team/team_session.dart';

bool get _isDesktop =>
    !kIsWeb && (Platform.isLinux || Platform.isMacOS || Platform.isWindows);

/// A loaded source file for one section.
class _Source {
  _Source(this.fileName, this.csv, this.headers);
  final String fileName;
  final String csv;
  final List<String> headers;
  Map<String, String> mapping = {};
}

/// Move from another system (M1.3): download the templates, load the files
/// from the old system, check them (nothing is written), import, and
/// reconcile the opening position against the old trial balance.
class OpeningDataScreen extends ConsumerStatefulWidget {
  const OpeningDataScreen({super.key});

  @override
  ConsumerState<OpeningDataScreen> createState() => _OpeningDataScreenState();
}

class _OpeningDataScreenState extends ConsumerState<OpeningDataScreen> {
  final _sources = <TakeOnSection, _Source>{};
  late final TextEditingController _date;
  TakeOnPlan? _plan;
  TakeOnResult? _result;
  OpeningReconciliation? _reconciliation;
  String? _busy;

  @override
  void initState() {
    super.initState();
    // Default: the last day of the previous month, the usual cut-over.
    final now = DateTime.now();
    final d = DateTime(now.year, now.month, 0);
    _date = TextEditingController(
        text: '${d.year}-${d.month.toString().padLeft(2, '0')}-'
            '${d.day.toString().padLeft(2, '0')}');
  }

  @override
  void dispose() {
    _date.dispose();
    super.dispose();
  }

  Map<TakeOnSection, TakeOnInput> get _inputs => {
        for (final e in _sources.entries)
          e.key: TakeOnInput(e.value.csv, mapping: e.value.mapping),
      };

  void _invalidate() {
    _plan = null;
    _result = null;
    _reconciliation = null;
  }

  Future<void> _run(String label, Future<void> Function() work) async {
    setState(() => _busy = label);
    try {
      await work();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$label failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _check() => _run('Checking', () async {
        final engine = await ref.read(documentEngineProvider.future);
        final plan = await OpeningTakeOn(engine)
            .plan(openingDate: _date.text.trim(), inputs: _inputs);
        setState(() {
          _plan = plan;
          _result = null;
          _reconciliation = null;
        });
      });

  Future<void> _import() async {
    final plan = _plan;
    if (plan == null) return;
    // Opening data posts locally; on a Team device that would bypass the
    // server's official posting. Team books take on through the server.
    if (ref.read(teamSessionProvider) != null) return;
    final blocked = [
      for (final s in plan.sections.values)
        if (s.provided && s.blocked) s.template.title,
    ];
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Import opening data?'),
        content: Text([
          'Atlas will create the records and post the opening balances as at '
              '${plan.openingDate}, through the normal ledger.',
          if (blocked.isNotEmpty)
            'These sections have rows to fix and will NOT be imported: '
                '${blocked.join(', ')}. You can import them later; nothing '
                'is posted twice.',
          'Make a backup first if this book already holds data you need.',
        ].join('\n\n')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Import')),
        ],
      ),
    );
    if (ok != true) return;
    await _run('Importing', () async {
      final engine = await ref.read(documentEngineProvider.future);
      final (after, result) = await OpeningTakeOn(engine)
          .commit(openingDate: _date.text.trim(), inputs: _inputs);
      final rec = await OpeningReconciliation.compute(engine, after);
      setState(() {
        _plan = after;
        _result = result;
        _reconciliation = rec;
      });
    });
  }

  Future<void> _reconcile() => _run('Reconciling', () async {
        final engine = await ref.read(documentEngineProvider.future);
        final plan = await OpeningTakeOn(engine)
            .plan(openingDate: _date.text.trim(), inputs: _inputs);
        final rec = await OpeningReconciliation.compute(engine, plan);
        setState(() {
          _plan = plan;
          _reconciliation = rec;
        });
      });

  Future<void> _saveText(String fileName, String text) async {
    final messenger = ScaffoldMessenger.of(context);
    // A byte-order mark so spreadsheet apps read accented names correctly.
    final bytes = Uint8List.fromList(utf8.encode('﻿$text'));
    try {
      final dest = await FilePicker.platform.saveFile(
        dialogTitle: 'Save $fileName',
        fileName: fileName,
        bytes: _isDesktop ? null : bytes,
      );
      if (dest == null) return;
      if (_isDesktop) await File(dest).writeAsBytes(bytes, flush: true);
      messenger.showSnackBar(SnackBar(content: Text('Saved $fileName')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not save: $e')));
    }
  }

  Future<void> _load(TakeOnTemplate t) async {
    final messenger = ScaffoldMessenger.of(context);
    final picked = await FilePicker.platform.pickFiles(
      dialogTitle: 'Choose the ${t.title.toLowerCase()} file',
      type: FileType.custom,
      allowedExtensions: const ['csv', 'txt'],
      withData: true,
    );
    final file = picked?.files.single;
    if (file == null) return;
    final bytes = file.bytes ??
        (file.path == null ? null : await File(file.path!).readAsBytes());
    if (bytes == null) return;
    final String text;
    try {
      text = utf8.decode(bytes);
    } on FormatException {
      messenger.showSnackBar(const SnackBar(
          content: Text('That file is not UTF-8 text. Save it from your '
              'spreadsheet as "CSV UTF-8" and choose it again.')));
      return;
    }
    List<String> headers;
    try {
      headers = CsvCodec.decode(
              text.startsWith('﻿') ? text.substring(1) : text)
          .headers;
    } catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text('That file is not valid CSV: $e')));
      return;
    }
    setState(() {
      final source = _Source(file.name, text, headers);
      source.mapping = OpeningTakeOn.autoMap(t, headers);
      _sources[t.section] = source;
      _invalidate();
    });
  }

  Future<void> _editMapping(TakeOnTemplate t) async {
    final source = _sources[t.section];
    if (source == null) return;
    final draft = Map<String, String>.from(source.mapping);
    final saved = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setLocal) => AlertDialog(
          title: Text('Columns: ${t.title}'),
          content: SizedBox(
            width: 480,
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final col in t.columns)
                  ListTile(
                    title: Text(col.label + (col.required ? ' *' : '')),
                    subtitle: Text(col.help),
                    trailing: DropdownButton<String?>(
                      value: draft[col.key],
                      hint: const Text('Not in file'),
                      items: [
                        const DropdownMenuItem<String?>(
                            value: null, child: Text('Not in file')),
                        for (final h in source.headers)
                          DropdownMenuItem<String?>(value: h, child: Text(h)),
                      ],
                      onChanged: (v) => setLocal(() {
                        if (v == null) {
                          draft.remove(col.key);
                        } else {
                          draft[col.key] = v;
                        }
                      }),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('Use these columns')),
          ],
        ),
      ),
    );
    if (saved == true) {
      setState(() {
        source.mapping = draft;
        _invalidate();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final plan = _plan;
    final teamConnected = ref.watch(teamSessionProvider) != null;
    return ResponsiveScaffold(
      title: 'Move from another system',
      leading: Navigator.of(context).canPop() ? const BackButton() : null,
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Bring your customers, suppliers, items, stock and opening '
            'balances over from your previous system. Download a template '
            'for each part you need, fill it from the old system\'s reports '
            '(or map its own export\'s columns), then Check. Checking writes '
            'nothing. Import is safe to repeat: rows already imported are '
            'recognised and never posted twice.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _date,
            decoration: const InputDecoration(
              labelText: 'Opening date (YYYY-MM-DD)',
              helperText: 'Balances are as at the end of this day. Enter '
                  'later transactions in Atlas normally.',
            ),
            onChanged: (_) => setState(_invalidate),
          ),
          const SizedBox(height: 16),
          if (teamConnected)
            Card(
              color: theme.colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                    'This device is connected to Atlas Team. Opening data '
                    'for Team books is posted on the Team server, so Import '
                    'is off here. You can still Check and Reconcile files.',
                    style: TextStyle(
                        color: theme.colorScheme.onErrorContainer)),
              ),
            ),
          if (plan != null && plan.problems.isNotEmpty)
            Card(
              color: theme.colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(plan.problems.join('\n'),
                    style: TextStyle(
                        color: theme.colorScheme.onErrorContainer)),
              ),
            ),
          for (final t in TakeOnTemplate.all) _sectionCard(t, theme),
          const SizedBox(height: 16),
          if (_busy != null)
            Row(children: [
              const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: 12),
              Text('$_busy…'),
            ])
          else
            Wrap(spacing: 12, runSpacing: 8, children: [
              OutlinedButton.icon(
                onPressed: _sources.isEmpty ? null : _check,
                icon: const Icon(Icons.fact_check_outlined),
                label: const Text('Check'),
              ),
              FilledButton.icon(
                onPressed: teamConnected ||
                        plan == null ||
                        plan.problems.isNotEmpty
                    ? null
                    : _import,
                icon: const Icon(Icons.file_download_done_outlined),
                label: const Text('Import'),
              ),
              OutlinedButton.icon(
                onPressed: _sources.isEmpty ? null : _reconcile,
                icon: const Icon(Icons.balance_outlined),
                label: const Text('Reconcile'),
              ),
            ]),
          if (_result != null) _resultCard(_result!, theme),
          if (_reconciliation != null)
            _reconciliationCard(_reconciliation!, theme),
        ],
      ),
    );
  }

  Widget _sectionCard(TakeOnTemplate t, ThemeData theme) {
    final source = _sources[t.section];
    final sp = _plan?[t.section];
    final chips = <Widget>[];
    if (sp != null && sp.provided) {
      void chip(TakeOnRowStatus s, String label, [Color? color]) {
        final n = sp.count(s);
        if (n > 0) {
          chips.add(Chip(
              label: Text('$n $label'),
              backgroundColor: color,
              visualDensity: VisualDensity.compact));
        }
      }

      chip(TakeOnRowStatus.create, 'new');
      chip(TakeOnRowStatus.unchanged, 'already imported');
      chip(TakeOnRowStatus.resume, 'to finish posting');
      chip(TakeOnRowStatus.control, 'checked against detail');
      chip(TakeOnRowStatus.skipped, 'zero');
      chip(TakeOnRowStatus.conflict, 'conflicts',
          theme.colorScheme.errorContainer);
      chip(TakeOnRowStatus.rejected, 'rejected',
          theme.colorScheme.errorContainer);
    }
    final issues = [
      ...?sp?.problems,
      for (final r in sp?.notAccepted.take(5) ?? const <TakeOnRow>[])
        'Line ${r.line}: ${r.problems.join(' ')}',
      if ((sp?.notAccepted.length ?? 0) > 5)
        '…and ${sp!.notAccepted.length - 5} more in the rejected rows file.',
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                  child: Text(t.title, style: theme.textTheme.titleMedium)),
              if (sp != null && sp.provided)
                Icon(
                  sp.blocked || sp.notAccepted.isNotEmpty
                      ? Icons.error_outline
                      : Icons.check_circle_outline,
                  color: sp.blocked || sp.notAccepted.isNotEmpty
                      ? theme.colorScheme.error
                      : theme.colorScheme.primary,
                ),
            ]),
            const SizedBox(height: 4),
            Text(t.purpose, style: theme.textTheme.bodySmall),
            if (source != null) ...[
              const SizedBox(height: 4),
              Text('File: ${source.fileName}',
                  style: theme.textTheme.bodySmall),
            ],
            if (chips.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 4, children: chips),
            ],
            if (issues.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(issues.join('\n'),
                  style: TextStyle(color: theme.colorScheme.error)),
            ],
            if (sp != null && sp.blocked)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                    'This part posts to the ledger, so it imports only when '
                    'every row is right.',
                    style: theme.textTheme.bodySmall),
              ),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 4, children: [
              TextButton.icon(
                onPressed: () => _saveText(t.fileName, t.csv()),
                icon: const Icon(Icons.download_outlined),
                label: const Text('Template'),
              ),
              TextButton.icon(
                onPressed: _busy != null ? null : () => _load(t),
                icon: const Icon(Icons.upload_file_outlined),
                label: Text(source == null ? 'Choose file' : 'Replace file'),
              ),
              if (source != null)
                TextButton.icon(
                  onPressed: () => _editMapping(t),
                  icon: const Icon(Icons.view_column_outlined),
                  label: const Text('Columns'),
                ),
              if (source != null)
                TextButton.icon(
                  onPressed: () => setState(() {
                    _sources.remove(t.section);
                    _invalidate();
                  }),
                  icon: const Icon(Icons.close),
                  label: const Text('Remove'),
                ),
              if (sp != null && sp.notAccepted.isNotEmpty)
                TextButton.icon(
                  onPressed: () => _saveText(
                      t.fileName.replaceFirst('.csv', '-rejected.csv'),
                      sp.rejectedCsv()),
                  icon: const Icon(Icons.report_outlined),
                  label: const Text('Rejected rows'),
                ),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _resultCard(TakeOnResult result, ThemeData theme) {
    String counts(Map<TakeOnSection, int> m) => [
          for (final e in m.entries) '${TakeOnTemplate.of(e.key).title}: ${e.value}',
        ].join(', ');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Import', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(result.created.isEmpty
                ? 'Nothing new to create.'
                : 'Created: ${counts(result.created)}.'),
            if (result.posted.isNotEmpty)
              Text('Finished posting: ${counts(result.posted)}.'),
            if (result.errors.isNotEmpty)
              Text(result.errors.join('\n'),
                  style: TextStyle(color: theme.colorScheme.error)),
          ],
        ),
      ),
    );
  }

  Widget _reconciliationCard(OpeningReconciliation rec, ThemeData theme) {
    const titles = {
      ReconciliationArea.trialBalance: 'Trial balance',
      ReconciliationArea.receivables: 'Customers (receivables)',
      ReconciliationArea.payables: 'Suppliers (payables)',
      ReconciliationArea.stock: 'Stock',
      ReconciliationArea.bankCash: 'Bank and cash',
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Opening position at ${rec.openingDate}',
                style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              rec.reconciled
                  ? 'Everything agrees with the previous system to the cent.'
                  : '${rec.exceptions.length} difference(s) to resolve. Atlas '
                      'has not adjusted anything; find each one in the old '
                      'system or correct it in Atlas.',
              style: TextStyle(
                  color: rec.reconciled
                      ? theme.colorScheme.primary
                      : theme.colorScheme.error),
            ),
            for (final area in ReconciliationArea.values)
              if (rec.area(area).isNotEmpty)
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  initiallyExpanded:
                      rec.area(area).any((l) => !l.matches),
                  title: Text(titles[area]!),
                  subtitle: Text(() {
                    final (e, a) = rec.totals(area);
                    final n = rec.area(area).where((l) => !l.matches).length;
                    return 'Previous ${formatCents(e)} · Atlas ${formatCents(a)}'
                        '${n == 0 ? ' · agrees' : ' · $n difference(s)'}';
                  }()),
                  children: [
                    for (final l in rec.area(area))
                      ListTile(
                        dense: true,
                        leading: Icon(
                            l.matches ? Icons.check : Icons.error_outline,
                            color: l.matches
                                ? theme.colorScheme.primary
                                : theme.colorScheme.error),
                        title: Text(l.label),
                        subtitle: Text([
                          'Previous ${formatCents(l.expectedCents)}'
                              '${l.expectedQty != null ? ' (${l.expectedQty} units)' : ''}',
                          'Atlas ${formatCents(l.actualCents)}'
                              '${l.actualQty != null ? ' (${l.actualQty} units)' : ''}',
                          if (l.differenceCents != 0)
                            'difference ${formatCents(l.differenceCents)}',
                          if (l.note != null) l.note!,
                        ].join(' · ')),
                        onTap: () => _drillDown(l),
                      ),
                  ],
                ),
          ],
        ),
      ),
    );
  }

  Future<void> _drillDown(ReconciliationLine l) => showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(l.label),
          content: SizedBox(
            width: 420,
            child: l.vouchers.isEmpty
                ? const Text('No Atlas entries make up this figure.')
                : ListView(shrinkWrap: true, children: [
                    for (final v in l.vouchers)
                      ListTile(dense: true, title: Text(v)),
                  ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c),
                child: const Text('Close')),
          ],
        ),
      );
}
