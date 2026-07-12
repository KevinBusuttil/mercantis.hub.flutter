import 'package:mercantis_core/mercantis_core.dart';

import '../ledger/ledger_values.dart';

const _systemRoles = {'System Manager'};

/// A booking clash: [existing] already occupies (part of) the requested
/// window on the same resource.
class ScheduleConflict {
  const ScheduleConflict(this.existing);

  final Document existing;

  @override
  String toString() =>
      '${existing.id} (${existing.payload['subject']}) occupies '
      '${existing.payload['starts_at']} – ${existing.payload['ends_at']}';
}

/// S1 scheduling core: conflict checking and the booking→invoice hook.
/// Interval logic is half-open — an appointment ending 10:00 does NOT clash
/// with one starting 10:00 (back-to-back bookings are the normal case).
class SchedulingService {
  SchedulingService(this._engine);

  final DocumentEngine _engine;

  /// Live statuses that occupy the resource. Cancelled and no-show slots
  /// are free again.
  static const _blocking = {'Scheduled', 'Confirmed', 'Completed'};

  /// Appointments on [resource] overlapping [startsAt, endsAt), excluding
  /// [excludeId] (the appointment being edited itself).
  Future<List<ScheduleConflict>> conflicts({
    required String resource,
    required DateTime startsAt,
    required DateTime endsAt,
    String? excludeId,
  }) async {
    final appointments = await _engine.list('Appointment',
        filters: {'resource': resource}, userRoles: _systemRoles);
    final found = <ScheduleConflict>[];
    for (final a in appointments) {
      if (a.id == excludeId) continue;
      if (!_blocking.contains('${a.payload['status']}')) continue;
      if (isTrue(a.payload['allow_overlap'])) continue;
      final s = DateTime.tryParse('${a.payload['starts_at']}');
      final e = DateTime.tryParse('${a.payload['ends_at']}');
      if (s == null || e == null) continue;
      if (s.isBefore(endsAt) && startsAt.isBefore(e)) {
        found.add(ScheduleConflict(a));
      }
    }
    found.sort((a, b) => '${a.existing.payload['starts_at']}'
        .compareTo('${b.existing.payload['starts_at']}'));
    return found;
  }

  /// All appointments intersecting [day] (any resource), for the calendar.
  Future<List<Document>> forDay(DateTime day) async {
    final dayStart = DateTime(day.year, day.month, day.day);
    final dayEnd = dayStart.add(const Duration(days: 1));
    final appointments =
        await _engine.list('Appointment', userRoles: _systemRoles);
    final rows = <Document>[
      for (final a in appointments)
        if (_intersects(a, dayStart, dayEnd)) a,
    ];
    rows.sort((a, b) =>
        '${a.payload['starts_at']}'.compareTo('${b.payload['starts_at']}'));
    return rows;
  }

  bool _intersects(Document a, DateTime from, DateTime to) {
    final s = DateTime.tryParse('${a.payload['starts_at']}');
    final e = DateTime.tryParse('${a.payload['ends_at']}');
    if (s == null || e == null) return false;
    return s.isBefore(to) && from.isBefore(e);
  }

  /// The booking→invoice hook: drafts a Sales Invoice for the appointment's
  /// service item and stamps it back onto the appointment. The rate is left
  /// blank on purpose — S8 price resolution fills it from the customer's
  /// price list (or standard rate) on save. Returns the draft for review;
  /// nothing posts until someone submits it.
  Future<Document> invoiceFor(String appointmentId,
      {Set<String> roles = _systemRoles}) async {
    final appointment = await _engine.fetch('Appointment', appointmentId);
    if (appointment == null) {
      throw StateError('Appointment $appointmentId not found.');
    }
    final existing = asNonEmpty(appointment.payload['sales_invoice']);
    if (existing != null) {
      throw StateError(
          'Appointment $appointmentId is already invoiced as $existing.');
    }
    final customer = asNonEmpty(appointment.payload['customer']);
    if (customer == null) {
      throw StateError(
          'Appointment $appointmentId has no customer to invoice.');
    }
    final item = asNonEmpty(appointment.payload['service_item']);
    if (item == null) {
      throw StateError(
          'Appointment $appointmentId has no service item to bill.');
    }

    final startsAt = '${appointment.payload['starts_at']}';
    // The appointment's company rides onto the invoice — multi-company
    // books must not fall to the defaults interceptor's first company.
    final invoice = Document(id: '', docType: 'Sales Invoice',
        company: appointment.company, payload: {
      'customer': customer,
      'posting_date': DateTime.now().toIso8601String().split('T').first,
    });
    invoice.children['items'] = [
      ChildRow(
        id: '', parentId: '', parentDocType: 'Sales Invoice',
        tableName: 'items', rowIndex: 0,
        payload: {
          'item': item,
          'qty': asNum(appointment.payload['qty']) == 0
              ? 1
              : appointment.payload['qty'],
          'description':
              '${appointment.payload['subject']} — $startsAt',
        },
      ),
    ];
    final draft = await _engine.save(invoice, roles);

    appointment.payload['sales_invoice'] = draft.id;
    if ('${appointment.payload['status']}' != 'Completed') {
      appointment.payload['status'] = 'Completed';
    }
    await _engine.save(appointment, roles);
    return draft;
  }
}

/// Blocks double-booking at save time: a live appointment may not overlap
/// another live appointment on the same resource unless it opts into
/// overlap. Rescheduling an existing appointment excludes itself from the
/// check.
class AppointmentConflictInterceptor extends DocumentInterceptor {
  const AppointmentConflictInterceptor();

  @override
  Future<void> beforeSave(
      DocumentEngine engine, Document doc, DocType docType,
      {required bool isNew}) async {
    if (docType.id != 'Appointment') return;
    if (isTrue(doc.payload['allow_overlap'])) return;
    if (!SchedulingService._blocking
        .contains('${doc.payload['status']}')) {
      return; // cancelling / no-showing frees the slot, never blocks
    }
    final resource = asNonEmpty(doc.payload['resource']);
    final startsAt = DateTime.tryParse('${doc.payload['starts_at']}');
    final endsAt = DateTime.tryParse('${doc.payload['ends_at']}');
    if (resource == null || startsAt == null || endsAt == null) return;
    if (!endsAt.isAfter(startsAt)) {
      throw StateError('An appointment must end after it starts.');
    }
    final clashes = await SchedulingService(engine).conflicts(
      resource: resource,
      startsAt: startsAt,
      endsAt: endsAt,
      excludeId: doc.id.isEmpty ? null : doc.id,
    );
    if (clashes.isNotEmpty) {
      throw StateError(
          '$resource is already booked: ${clashes.first}. '
          'Pick another slot or set Allow Overlap.');
    }
  }
}
