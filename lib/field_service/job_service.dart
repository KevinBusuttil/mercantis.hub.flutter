import 'package:mercantis_core/mercantis_core.dart';

import '../ledger/ledger_values.dart';

const _systemRoles = {'System Manager'};

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
        Document(id: '', docType: 'Job', payload: {
          'subject': request.payload['subject'],
          'customer': customer,
          'service_request': request.id,
          'priority': request.payload['priority'],
          'address': request.payload['address'],
          'description': request.payload['description'],
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
