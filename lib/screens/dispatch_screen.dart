import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

import '../field_service/job_service.dart';
import '../ledger/ledger_values.dart';
import '../scheduling/resource_calendar.dart';

const _systemRoles = {'System Manager'};

/// Everything the dispatcher needs in one load: the open request queue,
/// jobs waiting for a slot, the technicians, and the day's bookings.
class DispatchData {
  const DispatchData({
    required this.openRequests,
    required this.unscheduledJobs,
    required this.technicians,
    required this.appointments,
    required this.jobsByAppointment,
  });

  final List<Document> openRequests;
  final List<Document> unscheduledJobs;
  final List<Document> technicians;
  final List<Document> appointments;

  /// Reverse index: appointment id → the Job booked as it.
  final Map<String, Document> jobsByAppointment;
}

final dispatchDataProvider =
    FutureProvider.autoDispose<DispatchData>((ref) async {
  final engine = await ref.watch(documentEngineProvider.future);
  final requests =
      await engine.list('Service Request', userRoles: _systemRoles);
  final jobs = await engine.list('Job', userRoles: _systemRoles);
  final resources =
      await engine.list('Schedulable Resource', userRoles: _systemRoles);
  final appointments =
      await engine.list('Appointment', userRoles: _systemRoles);

  const priorityOrder = {'Urgent': 0, 'High': 1, 'Medium': 2, 'Low': 3};
  final open = [
    for (final r in requests)
      if ('${r.payload['status']}' == 'Open') r,
  ]..sort((a, b) => (priorityOrder['${a.payload['priority']}'] ?? 9)
      .compareTo(priorityOrder['${b.payload['priority']}'] ?? 9));

  return DispatchData(
    openRequests: open,
    unscheduledJobs: [
      for (final j in jobs)
        if ('${j.payload['status']}' == 'Draft') j,
    ],
    technicians: [
      for (final r in resources)
        if (r.payload['enabled'] == null || isTrue(r.payload['enabled'])) r,
    ],
    appointments: appointments,
    jobsByAppointment: {
      for (final j in jobs)
        if (asNonEmpty(j.payload['appointment']) != null)
          j.payload['appointment'] as String: j,
    },
  );
});

/// V1-3 dispatch board: convert the phone queue into jobs, drop jobs onto
/// technicians' lanes, and drive each job to invoiced — all on the same
/// conflict-checked calendar the rest of the app books through.
class DispatchScreen extends ConsumerStatefulWidget {
  const DispatchScreen({super.key});

  @override
  ConsumerState<DispatchScreen> createState() => _DispatchScreenState();
}

class _DispatchScreenState extends ConsumerState<DispatchScreen> {
  DateTime _day = DateTime.now();

  DateTime get _dayStart => DateTime(_day.year, _day.month, _day.day);

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

  Future<void> _convert(Document request) async {
    try {
      final job = await (await _jobs).jobFromRequest(request.id);
      _toast('Created ${job.id} — it\'s in "Waiting for a slot"');
    } catch (e) {
      _toast(e);
    } finally {
      ref.invalidate(dispatchDataProvider);
    }
  }

  Future<void> _dispatchDialog(Document job,
      {String? technician, DateTime? slot}) async {
    final data = ref.read(dispatchDataProvider).valueOrNull;
    final technicians = data?.technicians ?? const <Document>[];
    if (technicians.isEmpty) {
      _toast('Add a Schedulable Resource (your technicians) first.');
      return;
    }
    var tech = technician ?? technicians.first.id;
    var start = slot ??
        DateTime(_day.year, _day.month, _day.day, 9);
    var minutes = 120;
    final booked = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setDialogState) => AlertDialog(
          title: Text('Dispatch ${job.id}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: tech,
                decoration: const InputDecoration(
                    labelText: 'Technician', border: OutlineInputBorder()),
                items: [
                  for (final t in technicians)
                    DropdownMenuItem(
                        value: t.id,
                        child: Text('${t.payload['resource_name']}')),
                ],
                onChanged: (v) =>
                    setDialogState(() => tech = v ?? tech),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () async {
                  final picked = await showTimePicker(
                    context: c,
                    initialTime: TimeOfDay.fromDateTime(start),
                  );
                  if (picked != null) {
                    setDialogState(() => start = DateTime(_day.year,
                        _day.month, _day.day, picked.hour, picked.minute));
                  }
                },
                icon: const Icon(Icons.schedule_outlined),
                label: Text('Starts '
                    '${start.hour.toString().padLeft(2, '0')}:'
                    '${start.minute.toString().padLeft(2, '0')}'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                initialValue: minutes,
                decoration: const InputDecoration(
                    labelText: 'Duration', border: OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(value: 60, child: Text('1 hour')),
                  DropdownMenuItem(value: 120, child: Text('2 hours')),
                  DropdownMenuItem(value: 240, child: Text('Half day')),
                  DropdownMenuItem(value: 480, child: Text('Full day')),
                ],
                onChanged: (v) =>
                    setDialogState(() => minutes = v ?? minutes),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('Dispatch')),
          ],
        ),
      ),
    );
    if (booked != true) return;
    try {
      await (await _jobs).scheduleJob(
        job.id,
        technician: tech,
        startsAt: start,
        endsAt: start.add(Duration(minutes: minutes)),
      );
    } catch (e) {
      _toast(e);
    } finally {
      ref.invalidate(dispatchDataProvider);
    }
  }

  Future<void> _jobSheet(Document job) async {
    Future<void> act(Future<void> Function(JobService) action) async {
      try {
        await action(await _jobs);
      } catch (e) {
        _toast(e);
      } finally {
        ref.invalidate(dispatchDataProvider);
      }
    }

    await showModalBottomSheet<void>(
      context: context,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(MercantisSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${job.id} — ${job.payload['subject']}',
                  style: Theme.of(c).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text('Customer: ${job.payload['customer']}'
                  ' · ${job.payload['status']}'),
              if (asNonEmpty(job.payload['address']) != null)
                Text('${job.payload['address']}'),
              const SizedBox(height: MercantisSpacing.md),
              Wrap(
                spacing: MercantisSpacing.sm,
                runSpacing: MercantisSpacing.sm,
                children: [
                  FilledButton.tonal(
                    onPressed: () async {
                      Navigator.pop(c);
                      await act((j) async =>
                          j.setJobStatus(job.id, 'In Progress'));
                    },
                    child: const Text('Start work'),
                  ),
                  FilledButton(
                    onPressed: () async {
                      Navigator.pop(c);
                      await act((j) async {
                        final draft = await j.invoiceForJob(job.id);
                        _toast('Draft invoice ${draft.id} created');
                      });
                    },
                    child: const Text('Complete & invoice'),
                  ),
                  OutlinedButton(
                    onPressed: () async {
                      Navigator.pop(c);
                      await act(
                          (j) async => j.setJobStatus(job.id, 'On Hold'));
                    },
                    child: const Text('Hold'),
                  ),
                  OutlinedButton(
                    onPressed: () async {
                      Navigator.pop(c);
                      await act(
                          (j) async => j.setJobStatus(job.id, 'Cancelled'));
                    },
                    child: const Text('Cancel job'),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.pop(c);
                      Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => GenericFormView(
                            docTypeName: 'Job', documentName: job.id),
                      ));
                    },
                    child: const Text('Open'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(dispatchDataProvider);
    return ResponsiveScaffold(
      title: 'Dispatch',
      leading: Navigator.of(context).canPop() ? const BackButton() : null,
      padBody: false,
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (data) => ListView(
          padding: const EdgeInsets.all(MercantisSpacing.lg),
          children: [
            if (data.openRequests.isNotEmpty) ...[
              AtlasSectionCard(
                name: 'Requests waiting (${data.openRequests.length})',
                child: Column(
                  children: [
                    for (final r in data.openRequests)
                      ListTile(
                        dense: true,
                        leading: Icon(
                          '${r.payload['priority']}' == 'Urgent'
                              ? Icons.priority_high
                              : Icons.call_received_outlined,
                        ),
                        title: Text('${r.payload['subject']}'),
                        subtitle: Text([
                          if (asNonEmpty(r.payload['customer']) != null)
                            '${r.payload['customer']}',
                          '${r.payload['priority']}',
                        ].join(' · ')),
                        trailing: FilledButton.tonal(
                          onPressed: () => _convert(r),
                          child: const Text('Make job'),
                        ),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => GenericFormView(
                                docTypeName: 'Service Request',
                                documentName: r.id),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: MercantisSpacing.md),
            ],
            if (data.unscheduledJobs.isNotEmpty) ...[
              AtlasSectionCard(
                name: 'Waiting for a slot (${data.unscheduledJobs.length})',
                child: Column(
                  children: [
                    for (final j in data.unscheduledJobs)
                      ListTile(
                        dense: true,
                        leading: const Icon(Icons.handyman_outlined),
                        title: Text('${j.id} — ${j.payload['subject']}'),
                        subtitle: Text('${j.payload['customer']}'),
                        trailing: FilledButton(
                          onPressed: () => _dispatchDialog(j),
                          child: const Text('Dispatch'),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: MercantisSpacing.md),
            ],
            Row(
              children: [
                IconButton(
                  onPressed: () => setState(() =>
                      _day = _day.subtract(const Duration(days: 1))),
                  icon: const Icon(Icons.chevron_left),
                ),
                Text(
                  _dayStart.toIso8601String().split('T').first,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                IconButton(
                  onPressed: () => setState(
                      () => _day = _day.add(const Duration(days: 1))),
                  icon: const Icon(Icons.chevron_right),
                ),
                TextButton(
                  onPressed: () => setState(() => _day = DateTime.now()),
                  child: const Text('Today'),
                ),
              ],
            ),
            SizedBox(
              height: 560,
              child: _board(data),
            ),
          ],
        ),
      ),
    );
  }

  Widget _board(DispatchData data) {
    final lanes = [
      for (final t in data.technicians)
        CalendarLane(
          id: t.id,
          label: '${t.payload['resource_name']}',
          date: _dayStart,
        ),
    ];
    final entries = <CalendarEntry>[];
    for (final a in data.appointments) {
      if ({'Cancelled', 'No Show'}.contains('${a.payload['status']}')) {
        continue;
      }
      final start = DateTime.tryParse('${a.payload['starts_at']}');
      final end = DateTime.tryParse('${a.payload['ends_at']}');
      if (start == null || end == null) continue;
      if (start.year != _dayStart.year ||
          start.month != _dayStart.month ||
          start.day != _dayStart.day) {
        continue;
      }
      final job = data.jobsByAppointment[a.id];
      entries.add(CalendarEntry(
        id: a.id,
        laneId: '${a.payload['resource']}',
        start: start,
        end: end,
        title: '${a.payload['subject']}',
        subtitle: asNonEmpty(a.payload['customer']),
        color: job == null
            ? Colors.blueGrey // a plain appointment holding the slot
            : switch ('${job.payload['status']}') {
                'In Progress' => Colors.teal,
                'Completed' => Colors.grey,
                _ => Colors.indigo,
              },
      ));
    }
    return ResourceCalendar(
      lanes: lanes,
      entries: entries,
      onEntryTap: (entry) {
        final data = ref.read(dispatchDataProvider).valueOrNull;
        final job = data?.jobsByAppointment[entry.id];
        if (job != null) _jobSheet(job);
      },
      onSlotTap: (lane, slotStart) async {
        // Tapping an empty lane slot dispatches the oldest waiting job
        // into it — the fastest dispatch path.
        final data = ref.read(dispatchDataProvider).valueOrNull;
        final waiting = data?.unscheduledJobs ?? const <Document>[];
        if (waiting.isEmpty) {
          _toast('No jobs waiting — convert a request first.');
          return;
        }
        await _dispatchDialog(waiting.first,
            technician: lane.id, slot: slotStart);
      },
    );
  }
}
