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
        lineItemDocType(id: 'Recurring Invoice Item', module: _module),
        _recurringInvoice(),
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
          // Lifecycle timestamps (Phase 1A): stamped by the Mark as Sent /
          // Accepted / Rejected actions; QuotationStatus derives the status.
          FieldDefinition(key: 'sent_on', label: 'Sent On', type: FieldType.date, readOnly: true, allowOnSubmit: true),
          FieldDefinition(key: 'accepted_on', label: 'Accepted On', type: FieldType.date, readOnly: true, allowOnSubmit: true),
          FieldDefinition(key: 'rejected_on', label: 'Rejected On', type: FieldType.date, readOnly: true, allowOnSubmit: true),
          FieldDefinition(key: 'currency', label: 'Currency', type: FieldType.link, linkDocType: 'Currency', options: 'Currency'),
          FieldDefinition(key: 'price_list', label: 'Price List', type: FieldType.link, linkDocType: 'Price List', options: 'Price List'),
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
          FieldDefinition(key: 'price_list', label: 'Price List', type: FieldType.link, linkDocType: 'Price List', options: 'Price List'),
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
          // S8 pricing: blank line rates resolve through this list first;
          // stamped automatically when resolution used a fallback list.
          FieldDefinition(key: 'price_list', label: 'Price List', type: FieldType.link, linkDocType: 'Price List', options: 'Price List'),
          FieldDefinition(key: 'conversion_rate', label: 'Exchange Rate', type: FieldType.float, defaultValue: '1'),
          // Posting account defaults (resolved by Hub's business-profile policy
          // in Phase 3); explicit here so the ledger spine has somewhere to read.
          FieldDefinition(key: 'debit_to', label: 'Debit To (Receivable)', type: FieldType.link, linkDocType: 'Account', options: 'Account'),
          FieldDefinition(key: 'income_account', label: 'Income Account', type: FieldType.link, linkDocType: 'Account', options: 'Account'),
          FieldDefinition(key: 'cost_center', label: 'Cost Center', type: FieldType.link, linkDocType: 'Cost Center', options: 'Cost Center'),
          // Document-level default tax code — third in the line → item →
          // document → party fallback chain resolved on save.
          FieldDefinition(key: 'tax_code', label: 'Default Tax Code', type: FieldType.link, linkDocType: 'Tax Code', options: 'Tax Code'),
          // Returns (H6): a credit note is a Sales Invoice with is_return set
          // and negative line quantities, linked to the original via
          // return_against. The ledger spine posts the reversed GL/subledger
          // automatically from the negative amounts.
          FieldDefinition(key: 'is_return', label: 'Is Return (Credit Note)', type: FieldType.check),
          FieldDefinition(key: 'return_against', label: 'Return Against', type: FieldType.link, linkDocType: 'Sales Invoice', options: 'Sales Invoice'),
          // Phase 1B: an invoice-only business can issue stock (and post COGS)
          // straight from the invoice instead of raising a Delivery Note.
          FieldDefinition(key: 'update_stock', label: 'Update Stock', type: FieldType.check),
          FieldDefinition(key: 'set_warehouse', label: 'From Warehouse', type: FieldType.link, linkDocType: 'Warehouse', options: 'Warehouse'),
          // Retail pricing: line rates already contain VAT; the tax
          // interceptor extracts it so grand_total == the entered amounts.
          FieldDefinition(key: 'prices_include_tax', label: 'Prices Include Tax', type: FieldType.check),
          FieldDefinition(key: 'recurring_invoice', label: 'Recurring Template', type: FieldType.link, linkDocType: 'Recurring Invoice', options: 'Recurring Invoice', readOnly: true),
          FieldDefinition(key: 'project', label: 'Project', type: FieldType.link, linkDocType: 'Project', options: 'Project'),
          // Which online channel the sale came through (Phase 5), for
          // channel-level reporting.
          FieldDefinition(key: 'sales_channel', label: 'Sales Channel', type: FieldType.link, linkDocType: 'Sales Channel', options: 'Sales Channel', readOnly: true),
          FieldDefinition(key: 'items', label: 'Items', type: FieldType.table, tableDocType: 'Sales Invoice Item', options: 'Sales Invoice Item'),
          FieldDefinition(key: 'total', label: 'Total', type: FieldType.currency, readOnly: true),
          // Computed VAT rows (output tax) — one per distinct tax code on submit.
          FieldDefinition(key: 'taxes', label: 'Taxes', type: FieldType.table, tableDocType: 'Tax Charge', options: 'Tax Charge'),
          FieldDefinition(key: 'tax_total', label: 'Tax Total', type: FieldType.currency, readOnly: true),
          FieldDefinition(key: 'grand_total', label: 'Grand Total', type: FieldType.currency, readOnly: true),
          FieldDefinition(key: 'outstanding_amount', label: 'Outstanding', type: FieldType.currency, readOnly: true, allowOnSubmit: true),
          // Allocated by the Team posting authority at official submit —
          // gap-free per company, the document's real-world number on
          // screens and PDFs. Blank in Solo (the local id serves there).
          FieldDefinition(key: 'official_number', label: 'Official Number', type: FieldType.data, readOnly: true, allowOnSubmit: true),
          FieldDefinition(key: 'payment_terms', label: 'Payment Terms', type: FieldType.data),
        ],
      );

  /// Recurring invoice template (Phase 1A/7): a retainer that drafts its own
  /// Sales Invoice each period. RecurringInvoiceService generates the drafts
  /// (at boot and on demand), advances next_invoice_date, and records
  /// failures on the template; auto_submit posts them without review.
  static DocType _recurringInvoice() => const DocType(
        id: 'Recurring Invoice',
        name: 'Recurring Invoice',
        module: _module,
        namingRule: 'RINV-.YYYY.-.####',
        fields: [
          FieldDefinition(key: 'customer', label: 'Customer', type: FieldType.link, linkDocType: 'Customer', options: 'Customer', required: true),
          FieldDefinition(
            key: 'frequency',
            label: 'Frequency',
            type: FieldType.select,
            options: 'Weekly\nMonthly\nQuarterly\nYearly',
            defaultValue: 'Monthly',
            required: true,
          ),
          FieldDefinition(key: 'start_date', label: 'Start Date', type: FieldType.date, required: true),
          FieldDefinition(key: 'next_invoice_date', label: 'Next Invoice Date', type: FieldType.date, required: true),
          FieldDefinition(key: 'end_date', label: 'End Date', type: FieldType.date),
          FieldDefinition(key: 'active', label: 'Active', type: FieldType.check, defaultValue: '1'),
          FieldDefinition(key: 'auto_submit', label: 'Submit Automatically', type: FieldType.check),
          FieldDefinition(key: 'tax_code', label: 'Tax Code', type: FieldType.link, linkDocType: 'Tax Code', options: 'Tax Code'),
          FieldDefinition(key: 'currency', label: 'Currency', type: FieldType.link, linkDocType: 'Currency', options: 'Currency'),
          FieldDefinition(key: 'items', label: 'Items', type: FieldType.table, tableDocType: 'Recurring Invoice Item', options: 'Recurring Invoice Item'),
          FieldDefinition(key: 'last_generated_on', label: 'Last Generated', type: FieldType.date, readOnly: true),
          FieldDefinition(key: 'last_error', label: 'Last Error', type: FieldType.data, readOnly: true),
        ],
      );
}
