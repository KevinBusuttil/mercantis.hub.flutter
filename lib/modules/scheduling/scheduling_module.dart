import 'package:mercantis_core/mercantis_core.dart';

/// S1 scheduling core (Phase 1): bookable resources and the appointments
/// that occupy them. Appointments are deliberately NOT submittable — they
/// get rescheduled and cancelled constantly, so their lifecycle is a plain
/// status field; money enters the ledger only through the invoice a
/// completed appointment raises (SchedulingService.invoiceFor).
abstract final class SchedulingModule {
  static const _module = 'Scheduling';

  static List<DocType> docTypes() => [
        _schedulableResource(),
        _appointment(),
      ];

  /// Anything bookable: a person, a room, a vehicle, a machine. One
  /// appointment per resource per time slot (unless the appointment
  /// explicitly allows overlap — e.g. group classes).
  static DocType _schedulableResource() => const DocType(
        id: 'Schedulable Resource',
        name: 'Schedulable Resource',
        module: _module,
        fields: [
          FieldDefinition(key: 'resource_name', label: 'Resource Name', type: FieldType.data, required: true),
          FieldDefinition(
            key: 'resource_type',
            label: 'Type',
            type: FieldType.select,
            options: 'Person\nRoom\nVehicle\nEquipment',
            defaultValue: 'Person',
            required: true,
          ),
          FieldDefinition(key: 'enabled', label: 'Enabled', type: FieldType.check, defaultValue: '1'),
          // Working window, informational for the calendar (bookings outside
          // it are allowed but flagged by the UI, not blocked).
          FieldDefinition(key: 'workday_start', label: 'Workday Starts', type: FieldType.time),
          FieldDefinition(key: 'workday_end', label: 'Workday Ends', type: FieldType.time),
          FieldDefinition(key: 'notes', label: 'Notes', type: FieldType.smallText),
        ],
      );

  static DocType _appointment() => const DocType(
        id: 'Appointment',
        name: 'Appointment',
        module: _module,
        namingRule: 'APT-.YYYY.-.####',
        fields: [
          // Data-protection guidance (Clinic Pack §6.1, but sound for any
          // trade): the subject names the SERVICE, never the reason for
          // the visit — an appointment book can itself be sensitive data.
          FieldDefinition(key: 'subject', label: 'Subject', type: FieldType.data, required: true, description: 'Name the service (e.g. "Consultation") — keep the reason for the visit out of the diary.'),
          FieldDefinition(key: 'resource', label: 'Resource', type: FieldType.link, linkDocType: 'Schedulable Resource', options: 'Schedulable Resource', required: true),
          FieldDefinition(key: 'customer', label: 'Customer', type: FieldType.link, linkDocType: 'Customer', options: 'Customer'),
          FieldDefinition(key: 'starts_at', label: 'Starts', type: FieldType.dateTime, required: true),
          FieldDefinition(key: 'ends_at', label: 'Ends', type: FieldType.dateTime, required: true),
          FieldDefinition(
            key: 'status',
            label: 'Status',
            type: FieldType.select,
            options: 'Scheduled\nConfirmed\nCompleted\nCancelled\nNo Show',
            defaultValue: 'Scheduled',
            required: true,
          ),
          // What gets billed when the appointment completes; rate resolves
          // through S8 pricing on the drafted invoice.
          FieldDefinition(key: 'service_item', label: 'Service Item', type: FieldType.link, linkDocType: 'Item', options: 'Item'),
          FieldDefinition(key: 'qty', label: 'Quantity', type: FieldType.float, defaultValue: '1'),
          // Group bookings: set to let this appointment share the slot.
          FieldDefinition(key: 'allow_overlap', label: 'Allow Overlap', type: FieldType.check),
          FieldDefinition(key: 'location', label: 'Location', type: FieldType.data),
          FieldDefinition(key: 'notes', label: 'Notes', type: FieldType.smallText),
          // Stamped by the booking→invoice hook; the appointment's paper trail.
          FieldDefinition(key: 'sales_invoice', label: 'Invoiced As', type: FieldType.link, linkDocType: 'Sales Invoice', options: 'Sales Invoice', readOnly: true),
          // Phase 4: the S4 deposit taken at booking, auto-applied when
          // the appointment completes to invoice.
          FieldDefinition(key: 'deposit', label: 'Booking Deposit', type: FieldType.link, linkDocType: 'Customer Deposit', options: 'Customer Deposit', readOnly: true),
          // B-3: stamped when a visit reminder went out for this
          // appointment, so due-reminder queries never nag twice.
          FieldDefinition(key: 'reminder_sent_at', label: 'Reminder Sent', type: FieldType.dateTime, readOnly: true),
        ],
      );
}
