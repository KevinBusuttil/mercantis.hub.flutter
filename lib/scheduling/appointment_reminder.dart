import 'package:mercantis_core/mercantis_core.dart';

import '../ledger/ledger_values.dart';

const _weekdays = [
  'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday',
  'Sunday',
];
const _months = [
  'January', 'February', 'March', 'April', 'May', 'June', 'July',
  'August', 'September', 'October', 'November', 'December',
];

/// Builds the visit-reminder message for an upcoming appointment
/// (Clinic Pack B-3; the payment reminder is the pattern). Neutral by
/// design (§6.1): the SERVICE name and the slot — never the reason for
/// the visit, which must not travel in messages either. Pure text so it
/// can be copied into any channel (email, WhatsApp, SMS) until in-app
/// sending lands.
String buildAppointmentReminder({
  required String customerName,
  required String subject,
  required DateTime startsAt,
  String? location,
  String? companyName,
}) {
  final when = '${_weekdays[startsAt.weekday - 1]} '
      '${startsAt.day} ${_months[startsAt.month - 1]} ${startsAt.year} '
      'at ${startsAt.hour.toString().padLeft(2, '0')}:'
      '${startsAt.minute.toString().padLeft(2, '0')}';
  final where = location == null || location.trim().isEmpty
      ? ''
      : ', $location';
  final from = companyName == null ? '' : '\n\n$companyName';
  return 'Hi $customerName,\n\n'
      'A reminder of your upcoming appointment: $subject on $when$where. '
      'If you can no longer make it, please let us know as early as you '
      'can so the slot can be offered to someone else.\n\n'
      'See you then!$from';
}

/// Finds the appointments whose reminder should go out now, and stamps
/// them sent. Sending itself stays with the operator (copy → any
/// channel); the stamp is what keeps the due list honest.
class AppointmentReminderService {
  AppointmentReminderService(this.engine,
      {this.roles = const {'System Manager'}});

  final DocumentEngine engine;
  final Set<String> roles;

  static bool _open(Document a) {
    final status = '${a.payload['status']}';
    return status == 'Scheduled' || status == 'Confirmed';
  }

  /// Open appointments starting within [lead] of [asOf] — not yet begun,
  /// reminder not yet sent — soonest first.
  Future<List<Document>> dueReminders(DateTime asOf,
      {Duration lead = const Duration(hours: 48)}) async {
    final until = asOf.add(lead);
    final all = await engine.list('Appointment', userRoles: roles);
    final due = <(DateTime, Document)>[];
    for (final a in all) {
      if (!_open(a)) continue;
      if (asNonEmpty(a.payload['reminder_sent_at']) != null) continue;
      final starts = DateTime.tryParse('${a.payload['starts_at']}');
      if (starts == null) continue;
      if (!starts.isAfter(asOf) || starts.isAfter(until)) continue;
      due.add((starts, a));
    }
    due.sort((x, y) => x.$1.compareTo(y.$1));
    return [for (final d in due) d.$2];
  }

  /// Records that a reminder went out for [appointmentId].
  Future<void> markSent(String appointmentId, {DateTime? at}) async {
    final apt = await engine.fetch('Appointment', appointmentId);
    if (apt == null) return;
    apt.payload['reminder_sent_at'] =
        (at ?? DateTime.now()).toIso8601String();
    await engine.save(apt, roles);
  }
}
