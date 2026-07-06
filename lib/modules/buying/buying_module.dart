import 'package:mercantis_core/mercantis_core.dart';

import '../common/line_items.dart';

abstract final class BuyingModule {
  static const _module = 'Buying';

  static List<DocType> docTypes() => [
        _expense(),
        _supplier(),
        _supplierQuotation(),
        _purchaseOrder(),
        _purchaseInvoice(),
        // Line-item child tables referenced by the documents above.
        lineItemDocType(id: 'Supplier Quotation Item', module: _module),
        lineItemDocType(id: 'Purchase Order Item', module: _module),
        lineItemDocType(id: 'Purchase Invoice Item', module: _module),
      ];

  /// Supplier Quotation — a supplier's RFQ response (pre-purchase). Submittable
  /// via the (previously inert) `wf-supplier-quotation` workflow. Mirrors the
  /// Purchase Order shape. Swift parity: `SupplierQuotation`.
  static DocType _supplierQuotation() => const DocType(
        id: 'Supplier Quotation',
        name: 'Supplier Quotation',
        module: _module,
        isSubmittable: true,
        namingRule: 'SQTN-.YYYY.-.####',
        workflowId: 'wf-supplier-quotation',
        fields: [
          FieldDefinition(key: 'supplier', label: 'Supplier', type: FieldType.link, linkDocType: 'Supplier', options: 'Supplier', required: true),
          FieldDefinition(key: 'transaction_date', label: 'Date', type: FieldType.date, required: true),
          FieldDefinition(key: 'valid_till', label: 'Valid Till', type: FieldType.date),
          FieldDefinition(key: 'currency', label: 'Currency', type: FieldType.link, linkDocType: 'Currency', options: 'Currency'),
          FieldDefinition(key: 'items', label: 'Items', type: FieldType.table, tableDocType: 'Supplier Quotation Item', options: 'Supplier Quotation Item'),
          FieldDefinition(key: 'total', label: 'Total', type: FieldType.currency, readOnly: true),
          FieldDefinition(key: 'grand_total', label: 'Grand Total', type: FieldType.currency, readOnly: true),
          FieldDefinition(key: 'terms', label: 'Terms and Conditions', type: FieldType.longText),
        ],
      );

  static DocType _supplier() => const DocType(
        id: 'Supplier',
        name: 'Supplier',
        module: _module,
        isSubmittable: false,
        fields: [
          FieldDefinition(key: 'supplier_name', label: 'Supplier Name', type: FieldType.data, required: true),
          FieldDefinition(
            key: 'supplier_type',
            label: 'Supplier Type',
            type: FieldType.select,
            options: 'Company\nIndividual',
            defaultValue: 'Company',
          ),
          FieldDefinition(key: 'supplier_group', label: 'Supplier Group', type: FieldType.data),
          FieldDefinition(key: 'country', label: 'Country', type: FieldType.data),
          FieldDefinition(key: 'tax_id', label: 'Tax ID', type: FieldType.data),
          FieldDefinition(key: 'tax_code', label: 'Default Tax Code', type: FieldType.link, linkDocType: 'Tax Code', options: 'Tax Code'),
          FieldDefinition(key: 'default_currency', label: 'Default Currency', type: FieldType.link, linkDocType: 'Currency', options: 'Currency'),
          FieldDefinition(key: 'payment_terms', label: 'Payment Terms', type: FieldType.data),
          FieldDefinition(key: 'website', label: 'Website', type: FieldType.data),
          FieldDefinition(key: 'on_hold', label: 'On Hold', type: FieldType.check),
        ],
      );

  static DocType _purchaseOrder() => const DocType(
        id: 'Purchase Order',
        name: 'Purchase Order',
        module: _module,
        isSubmittable: true,
        namingRule: 'PO-.YYYY.-.####',
        workflowId: 'wf-purchase-order',
        fields: [
          FieldDefinition(key: 'supplier', label: 'Supplier', type: FieldType.link, linkDocType: 'Supplier', options: 'Supplier', required: true),
          FieldDefinition(key: 'transaction_date', label: 'Date', type: FieldType.date, required: true),
          FieldDefinition(key: 'schedule_date', label: 'Required By', type: FieldType.date),
          FieldDefinition(key: 'currency', label: 'Currency', type: FieldType.link, linkDocType: 'Currency', options: 'Currency'),
          FieldDefinition(key: 'items', label: 'Items', type: FieldType.table, tableDocType: 'Purchase Order Item', options: 'Purchase Order Item'),
          FieldDefinition(key: 'total', label: 'Total', type: FieldType.currency, readOnly: true),
          FieldDefinition(key: 'grand_total', label: 'Grand Total', type: FieldType.currency, readOnly: true),
          FieldDefinition(key: 'terms', label: 'Terms and Conditions', type: FieldType.longText),
        ],
      );

  static DocType _purchaseInvoice() => const DocType(
        id: 'Purchase Invoice',
        name: 'Purchase Invoice',
        module: _module,
        isSubmittable: true,
        namingRule: 'PINV-.YYYY.-.####',
        workflowId: 'wf-purchase-invoice',
        fields: [
          FieldDefinition(key: 'supplier', label: 'Supplier', type: FieldType.link, linkDocType: 'Supplier', options: 'Supplier', required: true),
          FieldDefinition(key: 'supplier_invoice_no', label: "Supplier's Invoice No", type: FieldType.data),
          FieldDefinition(key: 'posting_date', label: 'Posting Date', type: FieldType.date, required: true),
          FieldDefinition(key: 'due_date', label: 'Due Date', type: FieldType.date),
          FieldDefinition(key: 'currency', label: 'Currency', type: FieldType.link, linkDocType: 'Currency', options: 'Currency'),
          FieldDefinition(key: 'conversion_rate', label: 'Exchange Rate', type: FieldType.float, defaultValue: '1'),
          // Posting account defaults for the ledger spine (Phase 3).
          FieldDefinition(key: 'credit_to', label: 'Credit To (Payable)', type: FieldType.link, linkDocType: 'Account', options: 'Account'),
          FieldDefinition(key: 'expense_account', label: 'Expense Account', type: FieldType.link, linkDocType: 'Account', options: 'Account'),
          FieldDefinition(key: 'cost_center', label: 'Cost Center', type: FieldType.link, linkDocType: 'Cost Center', options: 'Cost Center'),
          // Document-level default tax code — third in the line → item →
          // document → party fallback chain resolved on save.
          FieldDefinition(key: 'tax_code', label: 'Default Tax Code', type: FieldType.link, linkDocType: 'Tax Code', options: 'Tax Code'),
          // Returns (H6): a debit note is a Purchase Invoice with is_return set
          // and negative line quantities, linked to the original via
          // return_against; the ledger spine reverses the GL/subledger from the
          // negative amounts.
          FieldDefinition(key: 'is_return', label: 'Is Return (Debit Note)', type: FieldType.check),
          FieldDefinition(key: 'return_against', label: 'Return Against', type: FieldType.link, linkDocType: 'Purchase Invoice', options: 'Purchase Invoice'),
          // Phase 1B: a one-document business can receive stock (Dr Inventory /
          // Cr GRNI) straight from the bill instead of raising a Purchase Receipt.
          FieldDefinition(key: 'update_stock', label: 'Update Stock', type: FieldType.check),
          FieldDefinition(key: 'set_warehouse', label: 'To Warehouse', type: FieldType.link, linkDocType: 'Warehouse', options: 'Warehouse'),
          FieldDefinition(key: 'items', label: 'Items', type: FieldType.table, tableDocType: 'Purchase Invoice Item', options: 'Purchase Invoice Item'),
          FieldDefinition(key: 'total', label: 'Total', type: FieldType.currency, readOnly: true),
          // Computed VAT rows (input tax) — one per distinct tax code on submit.
          FieldDefinition(key: 'taxes', label: 'Taxes', type: FieldType.table, tableDocType: 'Tax Charge', options: 'Tax Charge'),
          FieldDefinition(key: 'tax_total', label: 'Tax Total', type: FieldType.currency, readOnly: true),
          FieldDefinition(key: 'grand_total', label: 'Grand Total', type: FieldType.currency, readOnly: true),
          FieldDefinition(key: 'outstanding_amount', label: 'Outstanding', type: FieldType.currency, readOnly: true, allowOnSubmit: true),
        ],
      );

  /// Lightweight expense (Phase 1A): the coffee-receipt document. One
  /// category, net + VAT, paid from cash/bank (or left unpaid against the
  /// supplier). Posts straight to the GL on submit via LedgerDerivation —
  /// no line items, no full Purchase Invoice ceremony.
  static DocType _expense() => const DocType(
        id: 'Expense',
        name: 'Expense',
        module: _module,
        isSubmittable: true,
        namingRule: 'EXP-.YYYY.-.####',
        workflowId: 'wf-expense',
        fields: [
          FieldDefinition(key: 'posting_date', label: 'Date', type: FieldType.date, required: true),
          FieldDefinition(key: 'description', label: 'Description', type: FieldType.data, required: true),
          FieldDefinition(key: 'supplier', label: 'Supplier', type: FieldType.link, linkDocType: 'Supplier', options: 'Supplier'),
          FieldDefinition(key: 'expense_account', label: 'Category', type: FieldType.link, linkDocType: 'Account', options: 'Account', required: true),
          FieldDefinition(key: 'net_amount', label: 'Net Amount', type: FieldType.currency, required: true),
          FieldDefinition(key: 'tax_code', label: 'Tax Code', type: FieldType.link, linkDocType: 'Tax Code', options: 'Tax Code'),
          FieldDefinition(key: 'tax_amount', label: 'VAT Amount', type: FieldType.currency),
          FieldDefinition(key: 'tax_account', label: 'VAT Account', type: FieldType.link, linkDocType: 'Account', options: 'Account', readOnly: true),
          FieldDefinition(key: 'gross_amount', label: 'Gross Amount', type: FieldType.currency, readOnly: true),
          FieldDefinition(key: 'is_paid', label: 'Paid', type: FieldType.check, defaultValue: '1'),
          // Phase 6: pass-through project costs. billed/billed_on are stamped
          // after submit by ProjectBilling, hence allowOnSubmit.
          FieldDefinition(key: 'project', label: 'Project', type: FieldType.link, linkDocType: 'Project', options: 'Project'),
          FieldDefinition(key: 'billable', label: 'Billable to Customer', type: FieldType.check),
          FieldDefinition(key: 'billed', label: 'Billed', type: FieldType.check, readOnly: true, allowOnSubmit: true),
          FieldDefinition(key: 'billed_on', label: 'Billed On', type: FieldType.link, linkDocType: 'Sales Invoice', options: 'Sales Invoice', readOnly: true, allowOnSubmit: true),
          FieldDefinition(key: 'paid_from', label: 'Paid From', type: FieldType.link, linkDocType: 'Account', options: 'Account'),
          FieldDefinition(key: 'credit_to', label: 'Payable Account', type: FieldType.link, linkDocType: 'Account', options: 'Account'),
        ],
      );
}
