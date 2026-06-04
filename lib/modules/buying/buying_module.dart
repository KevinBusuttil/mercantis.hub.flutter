import 'package:mercantis_core/mercantis_core.dart';

import '../common/line_items.dart';

abstract final class BuyingModule {
  static const _module = 'Buying';

  static List<DocType> docTypes() => [
        _supplier(),
        _purchaseOrder(),
        _purchaseInvoice(),
        // Line-item child tables referenced by the documents above.
        lineItemDocType(id: 'Purchase Order Item', module: _module),
        lineItemDocType(id: 'Purchase Invoice Item', module: _module),
      ];

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
          // Posting account defaults for the ledger spine (Phase 3).
          FieldDefinition(key: 'credit_to', label: 'Credit To (Payable)', type: FieldType.link, linkDocType: 'Account', options: 'Account'),
          FieldDefinition(key: 'expense_account', label: 'Expense Account', type: FieldType.link, linkDocType: 'Account', options: 'Account'),
          FieldDefinition(key: 'cost_center', label: 'Cost Center', type: FieldType.link, linkDocType: 'Cost Center', options: 'Cost Center'),
          FieldDefinition(key: 'items', label: 'Items', type: FieldType.table, tableDocType: 'Purchase Invoice Item', options: 'Purchase Invoice Item'),
          FieldDefinition(key: 'total', label: 'Total', type: FieldType.currency, readOnly: true),
          FieldDefinition(key: 'tax_total', label: 'Tax Total', type: FieldType.currency, readOnly: true),
          FieldDefinition(key: 'grand_total', label: 'Grand Total', type: FieldType.currency, readOnly: true),
          FieldDefinition(key: 'outstanding_amount', label: 'Outstanding', type: FieldType.currency, readOnly: true),
        ],
      );
}
