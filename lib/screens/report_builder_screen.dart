import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

import '../reports/report_builder.dart';

/// DocTypes a report can be built over (no child tables / singletons), sorted.
final _builderDocTypesProvider = FutureProvider<List<DocType>>((ref) async {
  final registry = await ref.watch(metadataRegistryProvider.future);
  final all = await registry.all();
  return all.where((d) => !d.isChild && !d.isSingleton).toList()
    ..sort((a, b) => a.name.compareTo(b.name));
});

const _layoutTypes = {
  FieldType.sectionBreak,
  FieldType.columnBreak,
  FieldType.heading,
  FieldType.table,
  FieldType.tableMultiSelect,
};
const _numericTypes = {
  FieldType.integer,
  FieldType.float,
  FieldType.currency,
  FieldType.percent,
};

/// HU3 — a visual report builder over the C7 saved-report engine: pick a
/// DocType, a field to group by and an aggregate, then run it to see the
/// grouped table + a bar chart.
class ReportBuilderScreen extends ConsumerStatefulWidget {
  const ReportBuilderScreen({super.key});

  @override
  ConsumerState<ReportBuilderScreen> createState() =>
      _ReportBuilderScreenState();
}

class _ReportBuilderScreenState extends ConsumerState<ReportBuilderScreen> {
  String? _docType;
  String? _groupBy;
  String? _valueField;
  SavedReportAggregateFunction _fn = SavedReportAggregateFunction.count;
  ReportResult? _result;
  String? _error;
  bool _running = false;

  bool get _needsValueField => _fn != SavedReportAggregateFunction.count;

  Future<void> _run() async {
    final docType = _docType, groupBy = _groupBy;
    if (docType == null || groupBy == null) return;
    if (_needsValueField && _valueField == null) {
      setState(() => _error = 'Pick a value field for ${_fn.name}.');
      return;
    }
    setState(() {
      _running = true;
      _error = null;
    });
    try {
      final engine = await ref.read(savedReportEngineProvider.future);
      final user = ref.read(currentUserProvider);
      final def = buildGroupedReport(
        name: '$docType by $groupBy',
        sourceDocType: docType,
        groupBy: groupBy,
        fn: _fn,
        valueField: _valueField,
        ownerUserId: user.id,
      );
      final result = await engine.execute(def, userRoles: user.roles);
      if (!mounted) return;
      setState(() {
        _result = result;
        _running = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is SavedReportException ? e.message : '$e';
        _running = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final docTypesAsync = ref.watch(_builderDocTypesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Report builder')),
      body: docTypesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Failed to load: $e')),
        data: (docTypes) {
          DocType? selected;
          for (final d in docTypes) {
            if (d.id == _docType) {
              selected = d;
              break;
            }
          }
          final groupFields = selected == null
              ? const <FieldDefinition>[]
              : selected.fields
                  .where((f) => !_layoutTypes.contains(f.type))
                  .toList();
          final numericFields = selected == null
              ? const <FieldDefinition>[]
              : selected.fields
                  .where((f) => _numericTypes.contains(f.type))
                  .toList();

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              DropdownButtonFormField<String>(
                initialValue: _docType,
                isExpanded: true,
                decoration: const InputDecoration(
                    labelText: 'Document type', border: OutlineInputBorder()),
                items: [
                  for (final d in docTypes)
                    DropdownMenuItem(value: d.id, child: Text(d.name)),
                ],
                onChanged: (v) => setState(() {
                  _docType = v;
                  _groupBy = null;
                  _valueField = null;
                  _result = null;
                }),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _groupBy,
                isExpanded: true,
                decoration: const InputDecoration(
                    labelText: 'Group by', border: OutlineInputBorder()),
                items: [
                  for (final f in groupFields)
                    DropdownMenuItem(value: f.key, child: Text(f.label)),
                ],
                onChanged: selected == null
                    ? null
                    : (v) => setState(() => _groupBy = v),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<SavedReportAggregateFunction>(
                      initialValue: _fn,
                      isExpanded: true,
                      decoration: const InputDecoration(
                          labelText: 'Aggregate',
                          border: OutlineInputBorder()),
                      items: [
                        for (final f in SavedReportAggregateFunction.values)
                          DropdownMenuItem(value: f, child: Text(f.name)),
                      ],
                      onChanged: (v) => setState(() => _fn =
                          v ?? SavedReportAggregateFunction.count),
                    ),
                  ),
                  if (_needsValueField) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _valueField,
                        isExpanded: true,
                        decoration: const InputDecoration(
                            labelText: 'Of field',
                            border: OutlineInputBorder()),
                        items: [
                          for (final f in numericFields)
                            DropdownMenuItem(
                                value: f.key, child: Text(f.label)),
                        ],
                        onChanged: (v) => setState(() => _valueField = v),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: (_running || _docType == null || _groupBy == null)
                    ? null
                    : _run,
                icon: _running
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.play_arrow),
                label: const Text('Run report'),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(_error!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
                ),
              if (_result != null) ...[
                const Divider(height: 32),
                _ResultTable(result: _result!),
                if (_result!.chart != null) ...[
                  const SizedBox(height: 24),
                  _BarChart(chart: _result!.chart!),
                ],
              ],
            ],
          );
        },
      ),
    );
  }
}

class _ResultTable extends StatelessWidget {
  const _ResultTable({required this.result});
  final ReportResult result;

  @override
  Widget build(BuildContext context) {
    if (result.isEmpty) {
      return const Text('No rows matched.');
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: [
          for (final c in result.columns) DataColumn(label: Text(c.label)),
        ],
        rows: [
          for (final row in result.rows)
            DataRow(cells: [for (final cell in row) DataCell(Text(cell ?? ''))]),
        ],
      ),
    );
  }
}

class _BarChart extends StatelessWidget {
  const _BarChart({required this.chart});
  final ReportChart chart;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    var maxVal = 0.0;
    for (final v in chart.values) {
      final d = (v ?? 0).toDouble().abs();
      if (d > maxVal) maxVal = d;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${chart.valueLabel} by ${chart.categoryLabel}',
            style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        for (var i = 0; i < chart.categories.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                SizedBox(
                    width: 120,
                    child: Text(chart.categories[i],
                        overflow: TextOverflow.ellipsis)),
                Expanded(
                  child: LinearProgressIndicator(
                    value: maxVal == 0
                        ? 0
                        : (chart.values[i] ?? 0).toDouble().abs() / maxVal,
                    minHeight: 14,
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                    width: 72,
                    child: Text('${chart.values[i] ?? 0}',
                        textAlign: TextAlign.right)),
              ],
            ),
          ),
      ],
    );
  }
}
