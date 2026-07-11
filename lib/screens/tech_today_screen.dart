import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../deliveries/pod_capture.dart';
import '../field_service/job_service.dart';
import '../ledger/ledger_values.dart';

const _systemRoles = {'System Manager'};
const _techPrefKey = 'hub.tech_today.resource';

/// Which technician this device belongs to — persisted per device, like
/// the driver filter.
final selectedTechnicianProvider = StateProvider<String?>((ref) => null);

final _techTodayProvider = FutureProvider.autoDispose<
    ({List<Document> technicians, List<Document> jobs})>((ref) async {
  final engine = await ref.watch(documentEngineProvider.future);
  final tech = ref.watch(selectedTechnicianProvider);
  final resources =
      await engine.list('Schedulable Resource', userRoles: _systemRoles);
  final technicians = [
    for (final r in resources)
      if ('${r.payload['resource_type']}' == 'Person' &&
          (r.payload['enabled'] == null || isTrue(r.payload['enabled'])))
        r,
  ];
  if (tech == null) return (technicians: technicians, jobs: <Document>[]);
  final jobs = await engine.list('Job', userRoles: _systemRoles);
  return (
    technicians: technicians,
    jobs: techTodayJobs(
      jobs,
      technician: tech,
      today: DateTime.now().toIso8601String().split('T').first,
    ),
  );
});

/// V1-4: the technician's working screen — today's jobs in order, tick the
/// checklist, log parts and hours on site, then sign off and invoice in
/// one move (the S3 capture sheet, same as deliveries POD).
class TechTodayScreen extends ConsumerStatefulWidget {
  const TechTodayScreen({super.key});

  @override
  ConsumerState<TechTodayScreen> createState() => _TechTodayScreenState();
}

class _TechTodayScreenState extends ConsumerState<TechTodayScreen> {
  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((prefs) {
      final saved = prefs.getString(_techPrefKey);
      if (saved != null && saved.isNotEmpty && mounted) {
        ref.read(selectedTechnicianProvider.notifier).state = saved;
      }
    });
  }

  Future<JobService> get _jobs async =>
      JobService(await ref.read(documentEngineProvider.future));

  void _toast(Object message) {
    if (!mounted) return;
    final text = '$message';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(text.startsWith('Bad state: ')
            ? text.substring('Bad state: '.length)
            : text)));
  }

  Future<void> _selectTech(String? tech) async {
    ref.read(selectedTechnicianProvider.notifier).state = tech;
    final prefs = await SharedPreferences.getInstance();
    if (tech == null) {
      await prefs.remove(_techPrefKey);
    } else {
      await prefs.setString(_techPrefKey, tech);
    }
  }

  Future<void> _toggleChecklist(Document job, int index) async {
    final engine = await ref.read(documentEngineProvider.future);
    final fresh = await engine.fetch('Job', job.id);
    final rows = fresh?.children['checklist'];
    if (fresh == null || rows == null || index >= rows.length) return;
    rows[index].payload['done'] =
        isTrue(rows[index].payload['done']) ? 0 : 1;
    await engine.save(fresh, _systemRoles);
    ref.invalidate(_techTodayProvider);
  }

  Future<void> _addMaterial(Document job) async {
    final engine = await ref.read(documentEngineProvider.future);
    final items = await engine.list('Item', userRoles: _systemRoles);
    final warehouses =
        await engine.list('Warehouse', userRoles: _systemRoles);
    if (!mounted) return;
    String? item = items.isEmpty ? null : items.first.id;
    String? warehouse = warehouses.isEmpty ? null : warehouses.first.id;
    final qtyCtrl = TextEditingController(text: '1');
    final added = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setDialogState) => AlertDialog(
          title: const Text('Part used'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: item,
                decoration: const InputDecoration(
                    labelText: 'Item', border: OutlineInputBorder()),
                items: [
                  for (final i in items)
                    DropdownMenuItem(
                        value: i.id,
                        child: Text('${i.payload['item_name']}')),
                ],
                onChanged: (v) => setDialogState(() => item = v),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: qtyCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                    labelText: 'Quantity', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: warehouse,
                decoration: const InputDecoration(
                    labelText: 'From (van/warehouse)',
                    border: OutlineInputBorder()),
                items: [
                  for (final w in warehouses)
                    DropdownMenuItem(
                        value: w.id,
                        child: Text('${w.payload['warehouse_name']}')),
                ],
                onChanged: (v) => setDialogState(() => warehouse = v),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('Add')),
          ],
        ),
      ),
    );
    if (added != true || item == null) return;
    final fresh = await engine.fetch('Job', job.id);
    if (fresh == null) return;
    final rows = fresh.children['materials'] ?? <ChildRow>[];
    rows.add(ChildRow(
      id: '', parentId: fresh.id, parentDocType: 'Job',
      tableName: 'materials', rowIndex: rows.length,
      payload: {
        'item': item,
        'qty': num.tryParse(qtyCtrl.text.trim()) ?? 1,
        if (warehouse != null) 'warehouse': warehouse,
      },
    ));
    fresh.children['materials'] = rows;
    await engine.save(fresh, _systemRoles);
    ref.invalidate(_techTodayProvider);
  }

  Future<void> _addLabour(Document job) async {
    final engine = await ref.read(documentEngineProvider.future);
    final items = await engine.list('Item', userRoles: _systemRoles);
    final serviceItems = [
      for (final i in items)
        if ('${i.payload['item_type']}' == 'Service') i,
    ];
    if (!mounted) return;
    String? item = serviceItems.isEmpty ? null : serviceItems.first.id;
    final hoursCtrl = TextEditingController(text: '1');
    final rateCtrl = TextEditingController();
    final added = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setDialogState) => AlertDialog(
          title: const Text('Hours worked'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: hoursCtrl,
                autofocus: true,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                    labelText: 'Hours', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: rateCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                    labelText: 'Rate / hour (blank = price list)',
                    border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: item,
                decoration: const InputDecoration(
                    labelText: 'Billed as', border: OutlineInputBorder()),
                items: [
                  for (final i in serviceItems)
                    DropdownMenuItem(
                        value: i.id,
                        child: Text('${i.payload['item_name']}')),
                ],
                onChanged: (v) => setDialogState(() => item = v),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('Add')),
          ],
        ),
      ),
    );
    if (added != true) return;
    final fresh = await engine.fetch('Job', job.id);
    if (fresh == null) return;
    final rows = fresh.children['labour'] ?? <ChildRow>[];
    rows.add(ChildRow(
      id: '', parentId: fresh.id, parentDocType: 'Job',
      tableName: 'labour', rowIndex: rows.length,
      payload: {
        'hours': num.tryParse(hoursCtrl.text.trim()) ?? 1,
        if (num.tryParse(rateCtrl.text.trim()) != null)
          'rate': num.tryParse(rateCtrl.text.trim()),
        if (item != null) 'labour_item': item,
      },
    ));
    fresh.children['labour'] = rows;
    await engine.save(fresh, _systemRoles);
    ref.invalidate(_techTodayProvider);
  }

  Future<void> _signOff(Document job) async {
    final pod = await showPodCaptureSheet(context,
        customer: '${job.payload['customer']}');
    if (pod == null) return;
    try {
      final draft = await (await _jobs).completeJob(
        job.id,
        signature: pod.signature,
        photoPath: pod.photoPath,
        note: pod.note,
      );
      _toast(draft == null
          ? '${job.id} completed — nothing billable'
          : '${job.id} completed — draft invoice ${draft.id}');
    } catch (e) {
      _toast(e);
    } finally {
      ref.invalidate(_techTodayProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(_techTodayProvider);
    final selected = ref.watch(selectedTechnicianProvider);
    return ResponsiveScaffold(
      title: 'My day',
      leading: Navigator.of(context).canPop() ? const BackButton() : null,
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (data) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: DropdownButton<String?>(
                value: selected,
                hint: const Text('Who are you?'),
                underline: const SizedBox.shrink(),
                items: [
                  for (final t in data.technicians)
                    DropdownMenuItem<String?>(
                      value: t.id,
                      child: Text('${t.payload['resource_name']}'),
                    ),
                ],
                onChanged: _selectTech,
              ),
            ),
            Expanded(
              child: selected == null
                  ? const EmptyState(
                      title: 'Pick yourself above',
                      message:
                          'Your day shows once this device knows whose it is.',
                      icon: Icons.engineering_outlined,
                    )
                  : data.jobs.isEmpty
                      ? const EmptyState(
                          title: 'Nothing scheduled today',
                          message: 'Jobs dispatched to you appear here.',
                          icon: Icons.beach_access_outlined,
                        )
                      : ListView.separated(
                          itemCount: data.jobs.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: MercantisSpacing.sm),
                          itemBuilder: (context, i) =>
                              _jobCard(data.jobs[i]),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _jobCard(Document job) {
    final theme = Theme.of(context);
    final status = '${job.payload['status']}';
    final done = status == 'Completed';
    final checklist = job.children['checklist'] ?? const <ChildRow>[];
    final ticked =
        checklist.where((c) => isTrue(c.payload['done'])).length;
    final window = [
      '${job.payload['starts_at']}'.split('T').last.substring(0, 5),
      '${job.payload['ends_at']}'.split('T').last.substring(0, 5),
    ].join(' – ');

    return AtlasSectionCard(
      name: '$window · ${job.id}',
      child: Padding(
        padding: const EdgeInsets.all(MercantisSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${job.payload['subject']}',
                style: theme.textTheme.titleMedium),
            Text([
              '${job.payload['customer']}',
              if (asNonEmpty(job.payload['address']) != null)
                '${job.payload['address']}',
              status,
              if (checklist.isNotEmpty)
                'checklist $ticked/${checklist.length}',
            ].join(' · ')),
            if (checklist.isNotEmpty) ...[
              const SizedBox(height: MercantisSpacing.sm),
              for (var i = 0; i < checklist.length; i++)
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text('${checklist[i].payload['task']}'),
                  value: isTrue(checklist[i].payload['done']),
                  onChanged:
                      done ? null : (_) => _toggleChecklist(job, i),
                ),
            ],
            const SizedBox(height: MercantisSpacing.sm),
            if (!done)
              Wrap(
                spacing: MercantisSpacing.sm,
                runSpacing: MercantisSpacing.sm,
                children: [
                  if (status == 'Scheduled')
                    FilledButton.tonal(
                      onPressed: () async {
                        try {
                          await (await _jobs)
                              .setJobStatus(job.id, 'In Progress');
                        } catch (e) {
                          _toast(e);
                        } finally {
                          ref.invalidate(_techTodayProvider);
                        }
                      },
                      child: const Text('Start'),
                    ),
                  OutlinedButton.icon(
                    onPressed: () => _addMaterial(job),
                    icon: const Icon(Icons.plumbing_outlined, size: 18),
                    label: const Text('Part'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _addLabour(job),
                    icon: const Icon(Icons.timer_outlined, size: 18),
                    label: const Text('Hours'),
                  ),
                  FilledButton.icon(
                    onPressed: () => _signOff(job),
                    icon: const Icon(Icons.done_all_outlined, size: 18),
                    label: const Text('Sign off'),
                  ),
                ],
              )
            else
              Row(
                children: [
                  const StatusChip(
                      label: 'Completed',
                      tone: StatusTone.approved,
                      dense: true),
                  if (asNonEmpty(job.payload['sales_invoice']) != null)
                    Padding(
                      padding:
                          const EdgeInsets.only(left: MercantisSpacing.sm),
                      child: Text('Invoiced as '
                          '${job.payload['sales_invoice']}'),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
