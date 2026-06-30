import 'package:mercantis_core/mercantis_core.dart';

/// Compliance master data (H2 — ported from the Swift Hub
/// `ComplianceDocTypes`): the periodic tax return and its boxes.
///
///  * `Tax Filing` — a VAT/tax return for a period, with the headline totals
///    (output vs input tax, the net due/reclaimable, taxable bases) and a
///    status the operator advances Draft → Submitted → Filed.
///  * `Tax Filing Box` — one numbered line of the return, as the
///    `TaxReturnBuilder` fills it from the period's `Tax Transaction`s.
abstract final class ComplianceModule {
  static const _module = 'Compliance';

  static List<DocType> docTypes() => [
        _taxFiling(),
        _taxFilingBox(),
      ];

  static DocType _taxFiling() => const DocType(
        id: 'Tax Filing',
        name: 'Tax Filing',
        module: _module,
        namingRule: 'TAXF-.YYYY.-.####',
        fields: [
          FieldDefinition(key: 'title', label: 'Title', type: FieldType.data),
          FieldDefinition(key: 'tax_type', label: 'Tax Type', type: FieldType.select, options: 'VAT\nSalesTax\nWHT\nExciseDuty', defaultValue: 'VAT', required: true),
          FieldDefinition(key: 'from_date', label: 'From Date', type: FieldType.date, required: true),
          FieldDefinition(key: 'to_date', label: 'To Date', type: FieldType.date, required: true),
          FieldDefinition(
            key: 'filing_frequency',
            label: 'Frequency',
            type: FieldType.select,
            options: 'Monthly\nQuarterly\nAnnual',
            defaultValue: 'Quarterly',
          ),
          FieldDefinition(
            key: 'status',
            label: 'Status',
            type: FieldType.select,
            options: 'Draft\nSubmitted\nFiled',
            defaultValue: 'Draft',
          ),
          // Headline figures, filled by the builder from Tax Transactions.
          FieldDefinition(key: 'output_tax', label: 'Output Tax', type: FieldType.currency, readOnly: true, defaultValue: '0'),
          FieldDefinition(key: 'input_tax', label: 'Input Tax', type: FieldType.currency, readOnly: true, defaultValue: '0'),
          FieldDefinition(key: 'net_tax', label: 'Net Tax Due', type: FieldType.currency, readOnly: true, defaultValue: '0'),
          FieldDefinition(key: 'taxable_sales', label: 'Taxable Sales', type: FieldType.currency, readOnly: true, defaultValue: '0'),
          FieldDefinition(key: 'taxable_purchases', label: 'Taxable Purchases', type: FieldType.currency, readOnly: true, defaultValue: '0'),
          FieldDefinition(key: 'boxes', label: 'Return Boxes', type: FieldType.table, tableDocType: 'Tax Filing Box', options: 'Tax Filing Box'),
          FieldDefinition(key: 'filed_date', label: 'Filed On', type: FieldType.date),
          FieldDefinition(key: 'reference_no', label: 'Filing Reference', type: FieldType.data),
        ],
      );

  static DocType _taxFilingBox() => const DocType(
        id: 'Tax Filing Box',
        name: 'Tax Filing Box',
        module: _module,
        isChild: true,
        fields: [
          FieldDefinition(key: 'box_number', label: 'Box', type: FieldType.data),
          FieldDefinition(key: 'description', label: 'Description', type: FieldType.data),
          FieldDefinition(key: 'amount', label: 'Amount', type: FieldType.currency, defaultValue: '0'),
          // Whether this box is a tax figure (vs a taxable-base figure).
          FieldDefinition(key: 'is_tax', label: 'Is Tax', type: FieldType.check),
        ],
      );
}
