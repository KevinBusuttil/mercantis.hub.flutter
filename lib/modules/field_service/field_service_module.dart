import 'package:mercantis_core/mercantis_core.dart';

/// V1 Field Service & Trades (Phase 2): the intake→job spine.
///
/// A Service Request is the phone call ("boiler's dead"); a Job is the
/// scheduled, costed piece of work it becomes. Both are status-driven, not
/// submittable — like Appointments, they mutate constantly; money enters
/// the ledger only through the Sales Invoice a completed job raises
/// (increment V1-2). Technicians ARE Schedulable Resources, so dispatching
/// a job books a conflict-checked S1 Appointment and shows on the same
/// calendar as everything else.
abstract final class FieldServiceModule {
  static const _module = 'Field Service';

  static List<DocType> docTypes() => [
        _serviceRequest(),
        _job(),
        _jobChecklistItem(),
        _jobMaterial(),
        _jobLabour(),
      ];

  static DocType _serviceRequest() => const DocType(
        id: 'Service Request',
        name: 'Service Request',
        module: _module,
        namingRule: 'SRQ-.YYYY.-.####',
        fields: [
          FieldDefinition(key: 'subject', label: 'Subject', type: FieldType.data, required: true),
          FieldDefinition(key: 'customer', label: 'Customer', type: FieldType.link, linkDocType: 'Customer', options: 'Customer'),
          FieldDefinition(key: 'contact_name', label: 'Contact Name', type: FieldType.data),
          FieldDefinition(key: 'phone', label: 'Phone', type: FieldType.data),
          FieldDefinition(key: 'address', label: 'Site Address', type: FieldType.smallText),
          FieldDefinition(
            key: 'priority',
            label: 'Priority',
            type: FieldType.select,
            options: 'Low\nMedium\nHigh\nUrgent',
            defaultValue: 'Medium',
          ),
          FieldDefinition(key: 'description', label: 'Problem Description', type: FieldType.longText),
          FieldDefinition(key: 'requested_date', label: 'Requested Date', type: FieldType.date),
          FieldDefinition(
            key: 'status',
            label: 'Status',
            type: FieldType.select,
            options: 'Open\nConverted\nDeclined',
            defaultValue: 'Open',
          ),
          // Stamped by the request→job conversion; the intake's paper trail.
          FieldDefinition(key: 'job', label: 'Converted To Job', type: FieldType.link, linkDocType: 'Job', options: 'Job', readOnly: true),
        ],
      );

  static DocType _job() => const DocType(
        id: 'Job',
        name: 'Job',
        module: _module,
        namingRule: 'JOB-.YYYY.-.####',
        fields: [
          FieldDefinition(key: 'subject', label: 'Subject', type: FieldType.data, required: true),
          FieldDefinition(key: 'customer', label: 'Customer', type: FieldType.link, linkDocType: 'Customer', options: 'Customer', required: true),
          FieldDefinition(key: 'service_request', label: 'From Request', type: FieldType.link, linkDocType: 'Service Request', options: 'Service Request', readOnly: true),
          // The technician IS a Schedulable Resource (S1) — dispatching a
          // job books a conflict-checked appointment on them.
          FieldDefinition(key: 'technician', label: 'Technician', type: FieldType.link, linkDocType: 'Schedulable Resource', options: 'Schedulable Resource'),
          FieldDefinition(key: 'starts_at', label: 'Scheduled Start', type: FieldType.dateTime),
          FieldDefinition(key: 'ends_at', label: 'Scheduled End', type: FieldType.dateTime),
          FieldDefinition(key: 'appointment', label: 'Calendar Booking', type: FieldType.link, linkDocType: 'Appointment', options: 'Appointment', readOnly: true),
          FieldDefinition(
            key: 'status',
            label: 'Status',
            type: FieldType.select,
            options: 'Draft\nScheduled\nIn Progress\nOn Hold\nCompleted\nCancelled',
            defaultValue: 'Draft',
          ),
          FieldDefinition(
            key: 'priority',
            label: 'Priority',
            type: FieldType.select,
            options: 'Low\nMedium\nHigh\nUrgent',
            defaultValue: 'Medium',
          ),
          FieldDefinition(key: 'address', label: 'Site Address', type: FieldType.smallText),
          FieldDefinition(key: 'description', label: 'Work Description', type: FieldType.longText),
          FieldDefinition(key: 'checklist', label: 'Checklist', type: FieldType.table, tableDocType: 'Job Checklist Item', options: 'Job Checklist Item'),
          // Billed AND consumed from stock when the job invoices (V1-2).
          FieldDefinition(key: 'materials', label: 'Materials', type: FieldType.table, tableDocType: 'Job Material', options: 'Job Material'),
          FieldDefinition(key: 'labour', label: 'Labour', type: FieldType.table, tableDocType: 'Job Labour', options: 'Job Labour'),
          // Completion proof (S3 primitives, same as deliveries POD).
          FieldDefinition(key: 'completion_signature', label: 'Customer Sign-off', type: FieldType.signature),
          FieldDefinition(key: 'completion_photo', label: 'Completion Photo', type: FieldType.attachImage),
          FieldDefinition(key: 'completion_note', label: 'Completion Note', type: FieldType.smallText),
          FieldDefinition(key: 'sales_invoice', label: 'Invoiced As', type: FieldType.link, linkDocType: 'Sales Invoice', options: 'Sales Invoice', readOnly: true),
        ],
      );

  static DocType _jobChecklistItem() => const DocType(
        id: 'Job Checklist Item',
        name: 'Job Checklist Item',
        module: _module,
        isChild: true,
        fields: [
          FieldDefinition(key: 'task', label: 'Task', type: FieldType.data, required: true),
          FieldDefinition(key: 'done', label: 'Done', type: FieldType.check),
          FieldDefinition(key: 'note', label: 'Note', type: FieldType.data),
        ],
      );

  /// A part used on site: billed at `rate` (blank → S8 resolution on the
  /// invoice) and issued from `warehouse` (the van) when the job invoices.
  static DocType _jobMaterial() => const DocType(
        id: 'Job Material',
        name: 'Job Material',
        module: _module,
        isChild: true,
        fields: [
          FieldDefinition(key: 'item', label: 'Item', type: FieldType.link, linkDocType: 'Item', options: 'Item', required: true),
          FieldDefinition(key: 'qty', label: 'Quantity', type: FieldType.float, required: true, defaultValue: '1'),
          FieldDefinition(key: 'rate', label: 'Rate', type: FieldType.currency),
          FieldDefinition(key: 'warehouse', label: 'From Warehouse (Van)', type: FieldType.link, linkDocType: 'Warehouse', options: 'Warehouse'),
          FieldDefinition(key: 'note', label: 'Note', type: FieldType.data),
        ],
      );

  /// Time on site: billed as `hours × rate` through a labour service item.
  static DocType _jobLabour() => const DocType(
        id: 'Job Labour',
        name: 'Job Labour',
        module: _module,
        isChild: true,
        fields: [
          FieldDefinition(key: 'description', label: 'Description', type: FieldType.data),
          FieldDefinition(key: 'hours', label: 'Hours', type: FieldType.float, required: true, defaultValue: '1'),
          FieldDefinition(key: 'rate', label: 'Rate / Hour', type: FieldType.currency),
          FieldDefinition(key: 'labour_item', label: 'Labour Item', type: FieldType.link, linkDocType: 'Item', options: 'Item'),
        ],
      );
}
