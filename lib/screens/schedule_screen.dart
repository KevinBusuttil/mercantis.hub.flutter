import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

import '../ledger/ledger_values.dart';
import '../scheduling/resource_calendar.dart';
import '../scheduling/scheduling_service.dart';

const _systemRoles = {'System Manager'};

/// The scheduling data the screen needs in one load: enabled resources and
/// every live appointment (filtered per view in the widget — small-business
/// volumes make that fine, and it keeps invalidation trivial).
final _scheduleDataProvider = FutureProvider.autoDispose<
    ({List<Document> resources, List<Document> appointments})>((ref) async {
  final engine = await ref.watch(documentEngineProvider.future);
  final resources =
      await engine.list('Schedulable Resource', userRoles: _systemRoles);
  final appointments =
      await engine.list('Appointment', userRoles: _systemRoles);
  return (
    resources: [
      for (final r in resources)
        if (r.payload['enabled'] == null || isTrue(r.payload['enabled'])) r,
    ],
    appointments: appointments,
  );
});

/// Day/week schedule board (S1b): resource lanes per day, or a week for one
/// resource. Tap an empty slot to book (conflict checking runs on save);
/// tap a booking for status changes and the S8-priced invoice hook.
class ScheduleScreen extends ConsumerStatefulWidget {
  const ScheduleScreen({super.key});

  @override
  ConsumerState<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends ConsumerState<ScheduleScreen> {
  DateTime _anchor = DateTime.now();
  bool _weekMode = false;
  String? _weekResource;

  DateTime get _day => DateTime(_anchor.year, _anchor.month, _anchor.day);
  DateTime get _weekStart =>
      _day.subtract(Duration(days: _day.weekday - 1)); // Monday

  static const _statusColors = {
    'Scheduled': Colors.indigo,
    'Confirmed': Colors.teal,
    'Completed': Colors.blueGrey,
  };

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(_scheduleDataProvider);
    return ResponsiveScaffold(
      title: 'Schedule',
      leading: Navigator.of(context).canPop() ? const BackButton() : null,
      padBody: false,
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (data) => Column(
          children: [
            _header(data.resources),
            const Divider(height: 1),
            Expanded(child: _calendar(data)),
          ],
        ),
      ),
    );
  }

  Widget _header(List<Document> resources) {
    final label = _weekMode
        ? 'Week of ${_iso(_weekStart)}'
        : _iso(_day);
    return Padding(
      padding: const EdgeInsets.all(MercantisSpacing.sm),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: MercantisSpacing.sm,
        runSpacing: MercantisSpacing.sm,
        children: [
          IconButton(
            onPressed: () => setState(() => _anchor =
                _anchor.subtract(Duration(days: _weekMode ? 7 : 1))),
            icon: const Icon(Icons.chevron_left),
          ),
          Text(label, style: Theme.of(context).textTheme.titleMedium),
          IconButton(
            onPressed: () => setState(() =>
                _anchor = _anchor.add(Duration(days: _weekMode ? 7 : 1))),
            icon: const Icon(Icons.chevron_right),
          ),
          TextButton(
            onPressed: () => setState(() => _anchor = DateTime.now()),
            child: const Text('Today'),
          ),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Day')),
              ButtonSegment(value: true, label: Text('Week')),
            ],
            selected: {_weekMode},
            onSelectionChanged: (s) =>
                setState(() => _weekMode = s.first),
          ),
          if (_weekMode)
            DropdownButton<String>(
              value: _weekResource ??
                  (resources.isEmpty ? null : resources.first.id),
              hint: const Text('Resource'),
              items: [
                for (final r in resources)
                  DropdownMenuItem(
                    value: r.id,
                    child: Text('${r.payload['resource_name']}'),
                  ),
              ],
              onChanged: (v) => setState(() => _weekResource = v),
            ),
        ],
      ),
    );
  }

  Widget _calendar(
      ({List<Document> resources, List<Document> appointments}) data) {
    final lanes = <CalendarLane>[];
    final entries = <CalendarEntry>[];

    bool live(Document a) => !{'Cancelled', 'No Show'}
        .contains('${a.payload['status']}');

    CalendarEntry? entryFor(Document a, String laneId) {
      final start = DateTime.tryParse('${a.payload['starts_at']}');
      final end = DateTime.tryParse('${a.payload['ends_at']}');
      if (start == null || end == null) return null;
      return CalendarEntry(
        id: a.id,
        laneId: laneId,
        start: start,
        end: end,
        title: '${a.payload['subject']}',
        subtitle: asNonEmpty(a.payload['customer']),
        color: _statusColors['${a.payload['status']}'],
      );
    }

    if (!_weekMode) {
      for (final r in data.resources) {
        lanes.add(CalendarLane(
          id: r.id,
          label: '${r.payload['resource_name']}',
          date: _day,
        ));
      }
      for (final a in data.appointments) {
        if (!live(a)) continue;
        final start = DateTime.tryParse('${a.payload['starts_at']}');
        if (start == null || !_sameDay(start, _day)) continue;
        final entry = entryFor(a, '${a.payload['resource']}');
        if (entry != null) entries.add(entry);
      }
    } else {
      final resource = _weekResource ??
          (data.resources.isEmpty ? null : data.resources.first.id);
      for (var i = 0; i < 7; i++) {
        final date = _weekStart.add(Duration(days: i));
        lanes.add(CalendarLane(
          id: _iso(date),
          label:
              '${const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][i]} '
              '${date.day}',
          date: date,
        ));
      }
      for (final a in data.appointments) {
        if (!live(a)) continue;
        if ('${a.payload['resource']}' != resource) continue;
        final start = DateTime.tryParse('${a.payload['starts_at']}');
        if (start == null) continue;
        final laneId = _iso(DateTime(start.year, start.month, start.day));
        if (!lanes.any((l) => l.id == laneId)) continue;
        final entry = entryFor(a, laneId);
        if (entry != null) entries.add(entry);
      }
    }

    return ResourceCalendar(
      lanes: lanes,
      entries: entries,
      onEntryTap: (entry) => _openAppointment(entry.id),
      onSlotTap: (lane, slotStart) {
        final resource = _weekMode
            ? (_weekResource ??
                (data.resources.isEmpty ? null : data.resources.first.id))
            : lane.id;
        if (resource != null) _book(resource, slotStart);
      },
    );
  }

  Future<void> _book(String resource, DateTime slotStart) async {
    final engine = await ref.read(documentEngineProvider.future);
    final customers = await engine.list('Customer', userRoles: _systemRoles);
    final items = await engine.list('Item', userRoles: _systemRoles);
    if (!mounted) return;

    final subjectCtrl = TextEditingController();
    String? customer;
    String? item;
    var minutes = 60;
    final booked = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setDialogState) => AlertDialog(
          title: Text('Book ${_iso(slotStart)} '
              '${_hhmm(slotStart)}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: subjectCtrl,
                  autofocus: true,
                  decoration: const InputDecoration(
                      labelText: 'Subject', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: customer,
                  decoration: const InputDecoration(
                      labelText: 'Customer (optional)',
                      border: OutlineInputBorder()),
                  items: [
                    for (final cu in customers)
                      DropdownMenuItem(
                          value: cu.id,
                          child: Text('${cu.payload['customer_name']}')),
                  ],
                  onChanged: (v) => setDialogState(() => customer = v),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: item,
                  decoration: const InputDecoration(
                      labelText: 'Service (optional)',
                      border: OutlineInputBorder()),
                  items: [
                    for (final it in items)
                      DropdownMenuItem(
                          value: it.id,
                          child: Text('${it.payload['item_name']}')),
                  ],
                  onChanged: (v) => setDialogState(() => item = v),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  initialValue: minutes,
                  decoration: const InputDecoration(
                      labelText: 'Duration', border: OutlineInputBorder()),
                  items: const [
                    DropdownMenuItem(value: 30, child: Text('30 minutes')),
                    DropdownMenuItem(value: 60, child: Text('1 hour')),
                    DropdownMenuItem(value: 90, child: Text('1.5 hours')),
                    DropdownMenuItem(value: 120, child: Text('2 hours')),
                  ],
                  onChanged: (v) => setDialogState(() => minutes = v ?? 60),
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
                child: const Text('Book')),
          ],
        ),
      ),
    );
    if (booked != true || !mounted) return;

    try {
      await engine.save(
          Document(id: '', docType: 'Appointment', payload: {
            'subject': subjectCtrl.text.trim().isEmpty
                ? 'Booking'
                : subjectCtrl.text.trim(),
            'resource': resource,
            'starts_at': slotStart.toIso8601String(),
            'ends_at':
                slotStart.add(Duration(minutes: minutes)).toIso8601String(),
            'status': 'Scheduled',
            if (customer != null) 'customer': customer,
            if (item != null) 'service_item': item,
          }),
          _systemRoles);
      ref.invalidate(_scheduleDataProvider);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(_message(e))));
    }
  }

  Future<void> _openAppointment(String id) async {
    final engine = await ref.read(documentEngineProvider.future);
    final appointment = await engine.fetch('Appointment', id);
    if (appointment == null || !mounted) return;
    final scheduling = SchedulingService(engine);

    Future<void> setStatus(String status) async {
      appointment.payload['status'] = status;
      await engine.save(appointment, _systemRoles);
      ref.invalidate(_scheduleDataProvider);
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
              Text('${appointment.payload['subject']}',
                  style: Theme.of(c).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text('${appointment.payload['starts_at']}'
                  ' → ${appointment.payload['ends_at']}'),
              if (asNonEmpty(appointment.payload['customer']) != null)
                Text('Customer: ${appointment.payload['customer']}'),
              Text('Status: ${appointment.payload['status']}'),
              if (asNonEmpty(appointment.payload['sales_invoice']) != null)
                Text('Invoiced as '
                    '${appointment.payload['sales_invoice']}'),
              const SizedBox(height: MercantisSpacing.md),
              Wrap(
                spacing: MercantisSpacing.sm,
                runSpacing: MercantisSpacing.sm,
                children: [
                  FilledButton.tonal(
                    onPressed: () async {
                      Navigator.pop(c);
                      await setStatus('Confirmed');
                    },
                    child: const Text('Confirm'),
                  ),
                  if (asNonEmpty(appointment.payload['sales_invoice']) ==
                      null)
                    FilledButton(
                      onPressed: () async {
                        Navigator.pop(c);
                        try {
                          final draft =
                              await scheduling.invoiceFor(appointment.id);
                          ref.invalidate(_scheduleDataProvider);
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                  content: Text(
                                      'Draft invoice ${draft.id} created')));
                        } catch (e) {
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(_message(e))));
                        }
                      },
                      child: const Text('Complete & invoice'),
                    ),
                  OutlinedButton(
                    onPressed: () async {
                      Navigator.pop(c);
                      await setStatus('Cancelled');
                    },
                    child: const Text('Cancel booking'),
                  ),
                  OutlinedButton(
                    onPressed: () async {
                      Navigator.pop(c);
                      await setStatus('No Show');
                    },
                    child: const Text('No show'),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.pop(c);
                      Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => GenericFormView(
                          docTypeName: 'Appointment',
                          documentName: appointment.id,
                        ),
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

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static String _iso(DateTime d) =>
      d.toIso8601String().split('T').first;

  static String _hhmm(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  static String _message(Object e) {
    final text = '$e';
    return text.startsWith('Bad state: ')
        ? text.substring('Bad state: '.length)
        : text;
  }
}
