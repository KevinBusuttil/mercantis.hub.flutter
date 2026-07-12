import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

import '../booking/booking_service.dart';
import '../ledger/ledger_values.dart';
import '../scheduling/scheduling_service.dart';

const _systemRoles = {'System Manager'};

/// Everything the front desk needs in one load.
class BookingData {
  const BookingData({
    required this.resources,
    required this.services,
    required this.customers,
    required this.today,
  });

  final List<Document> resources;
  final List<Document> services;
  final List<Document> customers;

  /// Today's appointments, soonest first.
  final List<Document> today;

  String resourceName(String id) {
    for (final r in resources) {
      if (r.id == id) return '${r.payload['resource_name']}';
    }
    return id;
  }
}

final bookingDataProvider =
    FutureProvider.autoDispose<BookingData>((ref) async {
  final engine = await ref.watch(documentEngineProvider.future);
  final resources = [
    for (final r in await engine.list('Schedulable Resource',
        userRoles: _systemRoles))
      if (r.payload['enabled'] == null || isTrue(r.payload['enabled'])) r,
  ];
  final items = await engine.list('Item', userRoles: _systemRoles);
  final services = [
    for (final i in items)
      if ('${i.payload['item_type']}' == 'Service') i,
  ];
  final customers =
      await engine.list('Customer', userRoles: _systemRoles);
  final today = await SchedulingService(engine).forDay(DateTime.now());
  return BookingData(
    resources: resources,
    services: services.isEmpty ? items : services,
    customers: customers,
    today: today,
  );
});

/// P4-2: the front-desk booking flow — service, staff, slot, customer
/// and deposit in one form (the S1 interceptor rejects clashes at save),
/// with today's bookings below completing straight to a settled invoice.
class BookingScreen extends ConsumerStatefulWidget {
  const BookingScreen({super.key});

  @override
  ConsumerState<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends ConsumerState<BookingScreen> {
  String? _service;
  String? _resource;
  String? _customer;
  DateTime _date = DateTime.now();
  int _startMinutes = 9 * 60;
  int _durationMinutes = 60;
  final _depositCtrl = TextEditingController(text: '0.00');

  Future<BookingService> get _booking async =>
      BookingService(await ref.read(documentEngineProvider.future));

  void _toast(Object message) {
    if (!mounted) return;
    final text = '$message';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(text.startsWith('Bad state: ')
            ? text.substring('Bad state: '.length)
            : text)));
  }

  String _clock(int minutes) =>
      '${(minutes ~/ 60).toString().padLeft(2, '0')}:'
      '${(minutes % 60).toString().padLeft(2, '0')}';

  Future<void> _book() async {
    final service = _service;
    final resource = _resource;
    final customer = _customer;
    if (service == null || resource == null || customer == null) {
      _toast('Pick a service, a staff member and a customer.');
      return;
    }
    final startsAt = DateTime(_date.year, _date.month, _date.day,
        _startMinutes ~/ 60, _startMinutes % 60);
    try {
      final apt = await (await _booking).book(
        resource: resource,
        customer: customer,
        serviceItem: service,
        startsAt: startsAt,
        endsAt: startsAt.add(Duration(minutes: _durationMinutes)),
        depositAmount: num.tryParse(_depositCtrl.text.trim()) ?? 0,
      );
      _toast('Booked ${apt.id}');
    } catch (e) {
      _toast(e);
    } finally {
      ref.invalidate(bookingDataProvider);
    }
  }

  Future<void> _complete(Document apt) async {
    try {
      final invoice = await (await _booking).completeBooking(apt.id);
      _toast('Invoiced as ${invoice.id}');
    } catch (e) {
      _toast(e);
    } finally {
      ref.invalidate(bookingDataProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(bookingDataProvider);
    return ResponsiveScaffold(
      title: 'Book an appointment',
      leading: Navigator.of(context).canPop() ? const BackButton() : null,
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (data) => ListView(
          padding: const EdgeInsets.all(MercantisSpacing.lg),
          children: [
            _bookingForm(data),
            const SizedBox(height: MercantisSpacing.lg),
            Text('Today', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: MercantisSpacing.sm),
            if (data.today.isEmpty)
              const Text('No bookings today.')
            else
              for (final apt in data.today) _todayRow(apt, data),
          ],
        ),
      ),
    );
  }

  Widget _bookingForm(BookingData data) {
    return AtlasSectionCard(
      name: 'New booking',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<String>(
            initialValue: _service,
            decoration: const InputDecoration(
                labelText: 'Service', border: OutlineInputBorder()),
            items: [
              for (final s in data.services)
                DropdownMenuItem(
                    value: s.id,
                    child: Text('${s.payload['item_name']}')),
            ],
            onChanged: (v) => setState(() => _service = v),
          ),
          const SizedBox(height: MercantisSpacing.sm),
          DropdownButtonFormField<String>(
            initialValue: _resource,
            decoration: const InputDecoration(
                labelText: 'Staff / resource',
                border: OutlineInputBorder()),
            items: [
              for (final r in data.resources)
                DropdownMenuItem(
                    value: r.id,
                    child: Text('${r.payload['resource_name']}')),
            ],
            onChanged: (v) => setState(() => _resource = v),
          ),
          const SizedBox(height: MercantisSpacing.sm),
          DropdownButtonFormField<String>(
            initialValue: _customer,
            decoration: const InputDecoration(
                labelText: 'Customer', border: OutlineInputBorder()),
            items: [
              for (final c in data.customers)
                DropdownMenuItem(
                    value: c.id,
                    child: Text('${c.payload['customer_name']}')),
            ],
            onChanged: (v) => setState(() => _customer = v),
          ),
          const SizedBox(height: MercantisSpacing.sm),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.today_outlined, size: 18),
                  label:
                      Text(_date.toIso8601String().split('T').first),
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _date,
                      firstDate: DateTime.now()
                          .subtract(const Duration(days: 1)),
                      lastDate:
                          DateTime.now().add(const Duration(days: 365)),
                    );
                    if (picked != null) setState(() => _date = picked);
                  },
                ),
              ),
              const SizedBox(width: MercantisSpacing.sm),
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: _startMinutes,
                  decoration: const InputDecoration(
                      labelText: 'Starts', border: OutlineInputBorder()),
                  items: [
                    for (var m = 8 * 60; m <= 19 * 60 + 30; m += 30)
                      DropdownMenuItem(value: m, child: Text(_clock(m))),
                  ],
                  onChanged: (v) =>
                      setState(() => _startMinutes = v ?? _startMinutes),
                ),
              ),
              const SizedBox(width: MercantisSpacing.sm),
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: _durationMinutes,
                  decoration: const InputDecoration(
                      labelText: 'Length', border: OutlineInputBorder()),
                  items: const [
                    DropdownMenuItem(value: 30, child: Text('30 min')),
                    DropdownMenuItem(value: 45, child: Text('45 min')),
                    DropdownMenuItem(value: 60, child: Text('1 h')),
                    DropdownMenuItem(value: 90, child: Text('1.5 h')),
                    DropdownMenuItem(value: 120, child: Text('2 h')),
                  ],
                  onChanged: (v) => setState(
                      () => _durationMinutes = v ?? _durationMinutes),
                ),
              ),
            ],
          ),
          const SizedBox(height: MercantisSpacing.sm),
          TextField(
            controller: _depositCtrl,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
                labelText: 'Deposit taken now (0 for none)',
                border: OutlineInputBorder()),
          ),
          const SizedBox(height: MercantisSpacing.md),
          FilledButton.icon(
            onPressed: _book,
            icon: const Icon(Icons.event_available_outlined),
            label: const Text('Book'),
          ),
        ],
      ),
    );
  }

  Widget _todayRow(Document apt, BookingData data) {
    final theme = Theme.of(context);
    final starts = DateTime.tryParse('${apt.payload['starts_at']}');
    final ends = DateTime.tryParse('${apt.payload['ends_at']}');
    final status = '${apt.payload['status']}';
    final open = status == 'Scheduled' || status == 'Confirmed';
    String hm(DateTime? t) => t == null
        ? '—'
        : '${t.hour.toString().padLeft(2, '0')}:'
            '${t.minute.toString().padLeft(2, '0')}';
    return Padding(
      padding: const EdgeInsets.only(bottom: MercantisSpacing.sm),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    '${hm(starts)}–${hm(ends)}  '
                    '${apt.payload['subject']} · '
                    '${data.resourceName('${apt.payload['resource']}')}',
                    style: theme.textTheme.bodyMedium),
                Text(
                    status +
                        (asNonEmpty(apt.payload['deposit']) != null
                            ? ' · deposit ${apt.payload['deposit']}'
                            : ''),
                    style: theme.textTheme.labelSmall),
              ],
            ),
          ),
          if (open)
            FilledButton.tonal(
              onPressed: () => _complete(apt),
              child: const Text('Complete & invoice'),
            ),
        ],
      ),
    );
  }
}
