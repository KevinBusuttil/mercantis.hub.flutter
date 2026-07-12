import 'package:mercantis_core/mercantis_core.dart';

import '../ledger/ledger_values.dart';

const _systemRoles = {'System Manager'};

/// The technician's day (V1-4): [technician]'s jobs touching [today]
/// (ISO date), soonest first. Cancelled jobs never show; completed ones do
/// — the tech sees what's done. Pure, so the rules are unit-testable.
List<Document> techTodayJobs(
  List<Document> jobs, {
  required String technician,
  required String today,
}) {
  final mine = [
    for (final j in jobs)
      if ('${j.payload['status']}' != 'Cancelled' &&
          asNonEmpty(j.payload['technician']) == technician &&
          ('${j.payload['starts_at']}').startsWith(today))
        j,
  ]..sort((a, b) =>
      '${a.payload['starts_at']}'.compareTo('${b.payload['starts_at']}'));
  return mine;
}

/// V1 Field Service: intake→job conversion and dispatch (Phase 2,
/// increment 1). Dispatching books a real S1 Appointment on the
/// technician, so double-booking is impossible by construction and jobs
/// share the Schedule board with everything else.
class JobService {
  JobService(this._engine, {Set<String> roles = _systemRoles})
      : _roles = roles;

  final DocumentEngine _engine;
  final Set<String> _roles;

  /// Converts an Open Service Request into a Draft Job, carrying the
  /// intake details over and stamping both sides of the link.
  Future<Document> jobFromRequest(String requestId) async {
    final request = await _engine.fetch('Service Request', requestId);
    if (request == null) {
      throw StateError('Service Request $requestId not found.');
    }
    final existing = asNonEmpty(request.payload['job']);
    if (existing != null) {
      throw StateError(
          'Request $requestId is already converted to $existing.');
    }
    final customer = asNonEmpty(request.payload['customer']);
    if (customer == null) {
      throw StateError(
          'Request $requestId has no customer — set one before converting.');
    }

    final job = await _engine.save(
        Document(id: '', docType: 'Job', company: request.company,
            payload: {
          'subject': request.payload['subject'],
          'customer': customer,
          'service_request': request.id,
          'priority': request.payload['priority'],
          'address': request.payload['address'],
          'description': request.payload['description'],
          if (asNonEmpty(request.payload['equipment']) != null)
            'equipment': request.payload['equipment'],
          if (asNum(request.payload['meter_reading']) != 0)
            'meter_reading': request.payload['meter_reading'],
          'status': 'Draft',
        }),
        _roles);

    request.payload['job'] = job.id;
    request.payload['status'] = 'Converted';
    await _engine.save(request, _roles);
    return job;
  }

  /// Dispatch: assign the technician and time window, booking (or moving)
  /// the job's calendar appointment. The S1 conflict interceptor rejects a
  /// double-booked technician — the error carries the clashing booking.
  Future<Document> scheduleJob(
    String jobId, {
    required String technician,
    required DateTime startsAt,
    required DateTime endsAt,
  }) async {
    final job = await _engine.fetch('Job', jobId);
    if (job == null) throw StateError('Job $jobId not found.');
    if ('${job.payload['status']}' == 'Cancelled' ||
        '${job.payload['status']}' == 'Completed') {
      throw StateError(
          'Job $jobId is ${job.payload['status']} — reopen it to reschedule.');
    }

    // Book or move the appointment FIRST: if the slot clashes, the
    // interceptor throws here and the job is left untouched.
    final appointmentId = asNonEmpty(job.payload['appointment']);
    final appointment = appointmentId == null
        ? null
        : await _engine.fetch('Appointment', appointmentId);
    final booking = appointment ??
        Document(id: '', docType: 'Appointment', payload: {});
    booking.company ??= job.company;
    booking.payload
      ..['subject'] = '${job.id}: ${job.payload['subject']}'
      ..['resource'] = technician
      ..['customer'] = job.payload['customer']
      ..['starts_at'] = startsAt.toIso8601String()
      ..['ends_at'] = endsAt.toIso8601String()
      ..['location'] = job.payload['address']
      ..['status'] = 'Scheduled';
    final savedBooking = await _engine.save(booking, _roles);

    job.payload
      ..['technician'] = technician
      ..['starts_at'] = startsAt.toIso8601String()
      ..['ends_at'] = endsAt.toIso8601String()
      ..['appointment'] = savedBooking.id
      ..['status'] = 'Scheduled';
    return _engine.save(job, _roles);
  }

  /// V1-2 — the job makes money: drafts a Sales Invoice from the job's
  /// materials and labour. Material lines keep their van warehouse and set
  /// `update_stock`, so submitting the invoice issues the parts from stock
  /// and posts COGS through the existing perpetual-inventory derivation.
  /// Blank rates are left blank on purpose: S8 pricing resolves them
  /// (customer price list → company list → standard rate) on save. The job
  /// is stamped with the invoice and completed — its calendar booking too.
  Future<Document> invoiceForJob(String jobId, {String? postingDate}) async {
    final job = await _engine.fetch('Job', jobId);
    if (job == null) throw StateError('Job $jobId not found.');
    if ('${job.payload['status']}' == 'Cancelled') {
      throw StateError('Job $jobId is cancelled — nothing to bill.');
    }
    final existing = asNonEmpty(job.payload['sales_invoice']);
    if (existing != null) {
      throw StateError('Job $jobId is already invoiced as $existing.');
    }
    final customer = asNonEmpty(job.payload['customer']);
    if (customer == null) {
      throw StateError('Job $jobId has no customer to invoice.');
    }
    final materials = job.children['materials'] ?? const <ChildRow>[];
    final labour = job.children['labour'] ?? const <ChildRow>[];
    if (materials.isEmpty && labour.isEmpty) {
      throw StateError(
          'Job $jobId has no materials or labour — nothing to bill.');
    }

    final lines = <Map<String, dynamic>>[];
    var updateStock = false;
    String? setWarehouse;
    for (final m in materials) {
      final item = asNonEmpty(m.payload['item']);
      if (item == null) continue;
      final itemDoc = await _engine.fetch('Item', item);
      final isStock = '${itemDoc?.payload['item_type']}' == 'Stock';
      final warehouse = asNonEmpty(m.payload['warehouse']);
      if (isStock) {
        updateStock = true;
        setWarehouse ??= warehouse;
      }
      lines.add({
        'item': item,
        'qty': asNum(m.payload['qty']) == 0 ? 1 : m.payload['qty'],
        if (asNum(m.payload['rate']) > 0) 'rate': m.payload['rate'],
        if (warehouse != null) 'warehouse': warehouse,
        if (asNonEmpty(m.payload['note']) != null)
          'description': m.payload['note'],
      });
    }
    for (final l in labour) {
      final hours = asNum(l.payload['hours']);
      if (hours <= 0) continue;
      final item = asNonEmpty(l.payload['labour_item']);
      if (item == null) {
        throw StateError(
            'Labour line "${l.payload['description'] ?? ''}" has no labour '
            'item — billing needs one (a service Item such as "Labour").');
      }
      lines.add({
        'item': item,
        'qty': hours,
        if (asNum(l.payload['rate']) > 0) 'rate': l.payload['rate'],
        'description': asNonEmpty(l.payload['description']) ??
            '${job.id}: labour',
      });
    }
    if (lines.isEmpty) {
      throw StateError('Job $jobId has no billable lines.');
    }

    final invoice = Document(id: '', docType: 'Sales Invoice',
        company: job.company, payload: {
      'customer': customer,
      'posting_date': asNonEmpty(postingDate) ??
          DateTime.now().toIso8601String().split('T').first,
      if (updateStock) 'update_stock': 1,
      if (updateStock && setWarehouse != null) 'set_warehouse': setWarehouse,
    });
    invoice.children['items'] = [
      for (var i = 0; i < lines.length; i++)
        ChildRow(
          id: '', parentId: '', parentDocType: 'Sales Invoice',
          tableName: 'items', rowIndex: i, payload: lines[i],
        ),
    ];
    final draft = await _engine.save(invoice, _roles);

    job.payload['sales_invoice'] = draft.id;
    await _engine.save(job, _roles);
    // Completed via the status helper so the calendar booking follows.
    await setJobStatus(jobId, 'Completed');
    return draft;
  }

  /// V1-4 — the on-site finish: store the customer sign-off (S3 proof)
  /// and invoice the job. A job with nothing billable still completes —
  /// proof recorded, no invoice. Returns the draft invoice, or null when
  /// there was nothing to bill.
  Future<Document?> completeJob(
    String jobId, {
    String? signature,
    String? photoPath,
    String? note,
  }) async {
    final job = await _engine.fetch('Job', jobId);
    if (job == null) throw StateError('Job $jobId not found.');
    if (signature != null && signature.isNotEmpty) {
      job.payload['completion_signature'] = signature;
    }
    if (photoPath != null && photoPath.isNotEmpty) {
      job.payload['completion_photo'] = photoPath;
    }
    if (note != null && note.isNotEmpty) {
      job.payload['completion_note'] = note;
    }
    await _engine.save(job, _roles);

    try {
      return await invoiceForJob(jobId);
    } on StateError catch (e) {
      if ('$e'.contains('nothing to bill') ||
          '$e'.contains('no billable lines')) {
        await setJobStatus(jobId, 'Completed');
        return null;
      }
      rethrow;
    }
  }

  /// Status transitions that keep the calendar honest: cancelling a job
  /// cancels its booking (freeing the technician's slot); starting work
  /// confirms it.
  Future<Document> setJobStatus(String jobId, String status) async {
    final job = await _engine.fetch('Job', jobId);
    if (job == null) throw StateError('Job $jobId not found.');
    job.payload['status'] = status;
    final saved = await _engine.save(job, _roles);

    final appointmentId = asNonEmpty(job.payload['appointment']);
    if (appointmentId != null) {
      final booking = await _engine.fetch('Appointment', appointmentId);
      if (booking != null) {
        final bookingStatus = switch (status) {
          'Cancelled' => 'Cancelled',
          'On Hold' => 'Cancelled', // slot freed while the job waits
          'In Progress' => 'Confirmed',
          'Completed' => 'Completed',
          _ => null,
        };
        if (bookingStatus != null &&
            '${booking.payload['status']}' != bookingStatus) {
          booking.payload['status'] = bookingStatus;
          await _engine.save(booking, _roles);
        }
      }
    }
    return saved;
  }
}
