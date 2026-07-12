import 'package:mercantis_core/mercantis_core.dart';

/// V6 Construction (Phase 5, final vertical). The one genuinely new
/// mechanism the trade needs is PROGRESS BILLING WITH RETENTION: each
/// interim application certifies a cumulative percentage of the contract
/// value, bills the delta since last time LESS retention (a percentage
/// of each application, capped at a percentage of the contract), and
/// the held retention releases as a final invoice at practical
/// completion. Everything else — the invoice, VAT, settlement, the
/// optional Project for costs/timesheets — is the existing machinery.
///
/// Retention is deliberately a MEMO on the contract (billed = certified
/// − retained; the release bills the rest), not a GL split: nothing is
/// income until invoiced, which is the conservative SMB treatment.
abstract final class ConstructionModule {
  static const _module = 'Construction';

  static List<DocType> docTypes() =>
      [_contract(), _contractValuation()];

  static DocType _contract() => const DocType(
        id: 'Construction Contract',
        name: 'Construction Contract',
        module: _module,
        namingRule: 'CC-.YYYY.-.####',
        fields: [
          FieldDefinition(key: 'contract_name', label: 'Contract', type: FieldType.data, required: true),
          FieldDefinition(key: 'customer', label: 'Employer / Client', type: FieldType.link, linkDocType: 'Customer', options: 'Customer', required: true),
          // The optional cost side: timesheets and tasks live on a Project.
          FieldDefinition(key: 'project', label: 'Project (costs)', type: FieldType.link, linkDocType: 'Project', options: 'Project'),
          FieldDefinition(
            key: 'status',
            label: 'Status',
            type: FieldType.select,
            options: 'Draft\nActive\nPractically Complete\nClosed',
            defaultValue: 'Draft',
          ),
          FieldDefinition(key: 'contract_value', label: 'Contract Value (ex VAT)', type: FieldType.currency, required: true),
          FieldDefinition(key: 'retention_percent', label: 'Retention % per Application', type: FieldType.float, defaultValue: '10'),
          FieldDefinition(key: 'retention_cap_percent', label: 'Retention Cap (% of Contract)', type: FieldType.float, defaultValue: '5'),
          // What the invoices bill.
          FieldDefinition(key: 'billing_item', label: 'Billing Item', type: FieldType.link, linkDocType: 'Item', options: 'Item', required: true),
          FieldDefinition(key: 'retention_item', label: 'Retention Release Item', type: FieldType.link, linkDocType: 'Item', options: 'Item'),
          FieldDefinition(key: 'tax_code', label: 'Tax Code', type: FieldType.link, linkDocType: 'Tax Code', options: 'Tax Code'),
          FieldDefinition(key: 'valuations', label: 'Valuations', type: FieldType.table, tableDocType: 'Contract Valuation', options: 'Contract Valuation'),
          // Stamped by the retention release.
          FieldDefinition(key: 'retention_released', label: 'Retention Released', type: FieldType.currency, readOnly: true),
          FieldDefinition(key: 'release_invoice', label: 'Release Invoice', type: FieldType.link, linkDocType: 'Sales Invoice', options: 'Sales Invoice', readOnly: true),
          FieldDefinition(key: 'notes', label: 'Notes', type: FieldType.smallText),
        ],
      );

  /// One interim application: the certified cumulative position and what
  /// it billed. The row is the audit record — gross, retained, net, and
  /// the invoice that posted.
  static DocType _contractValuation() => const DocType(
        id: 'Contract Valuation',
        name: 'Contract Valuation',
        module: _module,
        isChild: true,
        fields: [
          FieldDefinition(key: 'valuation_no', label: 'No', type: FieldType.integer, required: true),
          FieldDefinition(key: 'valuation_date', label: 'Date', type: FieldType.date, required: true),
          FieldDefinition(key: 'cumulative_percent', label: 'Cumulative %', type: FieldType.float, required: true),
          FieldDefinition(key: 'gross_this_time', label: 'Gross This Application', type: FieldType.currency, required: true),
          FieldDefinition(key: 'retention_this_time', label: 'Retention Held', type: FieldType.currency),
          FieldDefinition(key: 'net_this_time', label: 'Net Billed', type: FieldType.currency, required: true),
          FieldDefinition(key: 'sales_invoice', label: 'Invoice', type: FieldType.link, linkDocType: 'Sales Invoice', options: 'Sales Invoice', readOnly: true),
        ],
      );
}
