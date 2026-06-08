import 'package:mercantis_core/mercantis_core.dart';

import '../common/line_items.dart';

abstract final class SellingModule {
  static const _module = 'Selling';

  static List<DocType> docTypes() => [
        _quotation(),
        _salesOrder(),
        _salesInvoice(),
        // Line-item child tables referenced by the documents above.
        lineItemDocType(id: 'Quotation Item', module: _module),
        lineItemDocType(id: 'Sales Order Item', module: _module),
        lineItemDocType(id: 'Sales Invoice Item', module: _module),
      ];

  static DocType _quotation() => const DocType(
        id: 'Quotation',
        name: 'Quotation',
        module: _module,
        isSubmittable: true,
        namingRule: 'QTN-.YYYY.-.####',
        workflowId: 'wf-quotation',
        fields: [
          FieldDefinition(key: 'customer', label: 'Customer', type: FieldType.link, linkDocType: 'Customer', options: 'Customer', required: true),
          FieldDefinition(key: 'transaction_date', label: 'Date', type: FieldType.date, required: true),
          FieldDefinition(key: 'valid_till', label: 'Valid Till', type: FieldType.date),
          FieldDefinition(key: 'currency', label: 'Currency', type: FieldType.link, linkDocType: 'Currency', options: 'Currency'),
          FieldDefinition(key: 'items', label: 'Items', type: FieldType.table, tableDocType: 'Quotation Item', options: 'Quotation Item'),
          FieldDefinition(key: 'total', label: 'Total', type: FieldType.currency, readOnly: true),
          FieldDefinition(key: 'grand_total', label: 'Grand Total', type: FieldType.currency, readOnly: true),
          FieldDefinition(key: 'terms', label: 'Terms and Conditions', type: FieldType.longText),
          FieldDefinition(key: 'note', label: 'Internal Note', type: FieldType.smallText),
        ],
      );

  static DocType _salesOrder() => const DocType(
        id: 'Sales Order',
        name: 'Sales Order',
        module: _module,
        isSubmittable: true,
        namingRule: 'SO-.YYYY.-.####',
        workflowId: 'wf-sales-order',
        fields: [
          FieldDefinition(key: 'customer', label: 'Customer', type: FieldType.link, linkDocType: 'Customer', options: 'Customer', required: true),
          FieldDefinition(key: 'transaction_date', label: 'Date', type: FieldType.date, required: true),
          FieldDefinition(key: 'delivery_date', label: 'Delivery Date', type: FieldType.date),
          FieldDefinition(key: 'currency', label: 'Currency', type: FieldType.link, linkDocType: 'Currency', options: 'Currency'),
          FieldDefinition(key: 'items', label: 'Items', type: FieldType.table, tableDocType: 'Sales Order Item', options: 'Sales Order Item'),
          FieldDefinition(key: 'total', label: 'Total', type: FieldType.currency, readOnly: true),
          FieldDefinition(key: 'grand_total', label: 'Grand Total', type: FieldType.currency, readOnly: true),
          FieldDefinition(key: 'terms', label: 'Terms and Conditions', type: FieldType.longText),
        ],
      );

  static DocType _salesInvoice() => const DocType(
        id: 'Sales Invoice',
        name: 'Sales Invoice',
        module: _module,
        isSubmittable: true,
        namingRule: 'SINV-.YYYY.-.####',
        workflowId: 'wf-sales-invoice',
        fields: [
          FieldDefinition(key: 'customer', label: 'Customer', type: FieldType.link, linkDocType: 'Customer', options: 'Customer', required: true),
          FieldDefinition(key: 'posting_date', label: 'Posting Date', type: FieldType.date, required: true),
          FieldDefinition(key: 'due_date', label: 'Due Date', type: FieldType.date),
          FieldDefinition(key: 'currency', label: 'Currency', type: FieldType.link, linkDocType: 'Currency', options: 'Currency'),
          // Posting account defaults (resolved by Hub's business-profile policy
          // in Phase 3); explicit here so the ledger spine has somewhere to read.
          FieldDefinition(key: 'debit_to', label: 'Debit To (Receivable)', type: FieldType.link, linkDocType: 'Account', options: 'Account'),
          FieldDefinition(key: 'income_account', label: 'Income Account', type: FieldType.link, linkDocType: 'Account', options: 'Account'),
          FieldDefinition(key: 'cost_center', label: 'Cost Center', type: FieldType.link, linkDocType: 'Cost Center', options: 'Cost Center'),
          // Document-level default tax code — third in the line → item →
          // document → party fallback chain resolved on save.
          FieldDefinition(key: 'tax_code', label: 'Default Tax Code', type: FieldType.link, linkDocType: 'Tax Code', options: 'Tax Code'),
          FieldDefinition(key: 'items', label: 'Items', type: FieldType.table, tableDocType: 'Sales Invoice Item', options: 'Sales Invoice Item'),
          FieldDefinition(key: 'total', label: 'Total', type: FieldType.currency, readOnly: true),
          // Computed VAT rows (output tax) — one per distinct tax code on submit.
          FieldDefinition(key: 'taxes', label: 'Taxes', type: FieldType.table, tableDocType: 'Tax Charge', options: 'Tax Charge'),
          FieldDefinition(key: 'tax_total', label: 'Tax Total', type: FieldType.currency, readOnly: true),
          FieldDefinition(key: 'grand_total', label: 'Grand Total', type: FieldType.currency, readOnly: true),
          FieldDefinition(key: 'outstanding_amount', label: 'Outstanding', type: FieldType.currency, readOnly: true, allowOnSubmit: true),
          FieldDefinition(key: 'payment_terms', label: 'Payment Terms', type: FieldType.data),
        ],
      );
}
