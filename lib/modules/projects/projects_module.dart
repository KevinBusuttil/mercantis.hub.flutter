import 'package:mercantis_core/mercantis_core.dart';

/// Projects / jobs for service businesses (Phase 6): a Project groups the
/// work, Tasks track what needs doing, Timesheets capture billable (and
/// internal) hours. Billable expenses reuse the Expense doctype via its
/// `project` link. `ProjectBilling` turns unbilled time + expenses into a
/// draft Sales Invoice; profitability reads invoiced-vs-cost per project.
abstract final class ProjectsModule {
  static const _module = 'Projects';

  static List<DocType> docTypes() => [
        _project(),
        _task(),
        _timesheet(),
      ];

  static DocType _project() => const DocType(
        id: 'Project',
        name: 'Project',
        module: _module,
        namingRule: 'PROJ-.YYYY.-.####',
        fields: [
          FieldDefinition(key: 'project_name', label: 'Project Name', type: FieldType.data, required: true),
          FieldDefinition(key: 'customer', label: 'Customer', type: FieldType.link, linkDocType: 'Customer', options: 'Customer'),
          FieldDefinition(
            key: 'status',
            label: 'Status',
            type: FieldType.select,
            options: 'Open\nOn Hold\nCompleted\nCancelled',
            defaultValue: 'Open',
          ),
          FieldDefinition(key: 'start_date', label: 'Start Date', type: FieldType.date),
          FieldDefinition(key: 'end_date', label: 'End Date', type: FieldType.date),
          FieldDefinition(key: 'quotation', label: 'From Quotation', type: FieldType.link, linkDocType: 'Quotation', options: 'Quotation', readOnly: true),
          FieldDefinition(key: 'default_billing_rate', label: 'Default Billing Rate (per hour)', type: FieldType.currency),
          FieldDefinition(key: 'notes', label: 'Notes', type: FieldType.longText),
        ],
      );

  static DocType _task() => const DocType(
        id: 'Task',
        name: 'Task',
        module: _module,
        namingRule: 'TASK-.YYYY.-.####',
        fields: [
          FieldDefinition(key: 'subject', label: 'Subject', type: FieldType.data, required: true),
          FieldDefinition(key: 'project', label: 'Project', type: FieldType.link, linkDocType: 'Project', options: 'Project'),
          FieldDefinition(
            key: 'status',
            label: 'Status',
            type: FieldType.select,
            options: 'Open\nWorking\nDone\nCancelled',
            defaultValue: 'Open',
          ),
          FieldDefinition(key: 'due_date', label: 'Due Date', type: FieldType.date),
          FieldDefinition(key: 'description', label: 'Description', type: FieldType.longText),
        ],
      );

  static DocType _timesheet() => const DocType(
        id: 'Timesheet',
        name: 'Timesheet',
        module: _module,
        namingRule: 'TS-.YYYY.-.####',
        fields: [
          FieldDefinition(key: 'project', label: 'Project', type: FieldType.link, linkDocType: 'Project', options: 'Project', required: true),
          FieldDefinition(key: 'task', label: 'Task', type: FieldType.link, linkDocType: 'Task', options: 'Task'),
          FieldDefinition(key: 'activity_date', label: 'Date', type: FieldType.date, required: true),
          FieldDefinition(key: 'hours', label: 'Hours', type: FieldType.float, required: true),
          FieldDefinition(key: 'description', label: 'Work Done', type: FieldType.data),
          FieldDefinition(key: 'billable', label: 'Billable', type: FieldType.check, defaultValue: '1'),
          // Blank falls back to the project's default billing rate.
          FieldDefinition(key: 'billing_rate', label: 'Billing Rate (per hour)', type: FieldType.currency),
          FieldDefinition(key: 'billed', label: 'Billed', type: FieldType.check, readOnly: true),
          FieldDefinition(key: 'sales_invoice', label: 'Billed On', type: FieldType.link, linkDocType: 'Sales Invoice', options: 'Sales Invoice', readOnly: true),
        ],
      );
}
