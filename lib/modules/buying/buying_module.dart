import 'package:mercantis_core/mercantis_core.dart';

abstract final class BuyingModule {
  static const _module = 'Buying';

  static List<DocType> docTypes() => [
        _supplier(),
        _purchaseOrder(),
        _purchaseInvoice(),
      ];

  static DocType _supplier() => DocType(
        id: 'Supplier',
        name: 'Supplier',
        module: _module,
        isSubmittable: false,
        fields: [
          FieldDefinition(fieldKey: 'supplier_name', label: 'Supplier Name', fieldType: FieldType.data, isMandatory: true),
          FieldDefinition(
            fieldKey: 'supplier_type',
            label: 'Supplier Type',
            fieldType: FieldType.select,
            options: 'Company\nIndividual',
            defaultValue: 'Company',
          ),
          FieldDefinition(fieldKey: 'supplier_group', label: 'Supplier Group', fieldType: FieldType.data),
          FieldDefinition(fieldKey: 'country', label: 'Country', fieldType: FieldType.data),
          FieldDefinition(fieldKey: 'tax_id', label: 'Tax ID', fieldType: FieldType.data),
          FieldDefinition(fieldKey: 'default_currency', label: 'Default Currency', fieldType: FieldType.link, options: 'Currency'),
          FieldDefinition(fieldKey: 'payment_terms', label: 'Payment Terms', fieldType: FieldType.data),
          FieldDefinition(fieldKey: 'website', label: 'Website', fieldType: FieldType.data),
          FieldDefinition(fieldKey: 'on_hold', label: 'On Hold', fieldType: FieldType.check),
        ],
      );

  static DocType _purchaseOrder() => DocType(
        id: 'Purchase Order',
        name: 'Purchase Order',
        module: _module,
        isSubmittable: true,
        namingRule: 'PO-.YYYY.-.####',
        fields: [
          FieldDefinition(fieldKey: 'supplier', label: 'Supplier', fieldType: FieldType.link, options: 'Supplier', isMandatory: true),
          FieldDefinition(fieldKey: 'transaction_date', label: 'Date', fieldType: FieldType.date, isMandatory: true),
          FieldDefinition(fieldKey: 'schedule_date', label: 'Required By', fieldType: FieldType.date),
          FieldDefinition(fieldKey: 'currency', label: 'Currency', fieldType: FieldType.link, options: 'Currency'),
          FieldDefinition(fieldKey: 'items', label: 'Items', fieldType: FieldType.table, options: 'Purchase Order Item'),
          FieldDefinition(fieldKey: 'total', label: 'Total', fieldType: FieldType.currency, readOnly: true),
          FieldDefinition(fieldKey: 'grand_total', label: 'Grand Total', fieldType: FieldType.currency, readOnly: true),
          FieldDefinition(fieldKey: 'terms', label: 'Terms and Conditions', fieldType: FieldType.textEditor),
        ],
      );

  static DocType _purchaseInvoice() => DocType(
        id: 'Purchase Invoice',
        name: 'Purchase Invoice',
        module: _module,
        isSubmittable: true,
        namingRule: 'PINV-.YYYY.-.####',
        fields: [
          FieldDefinition(fieldKey: 'supplier', label: 'Supplier', fieldType: FieldType.link, options: 'Supplier', isMandatory: true),
          FieldDefinition(fieldKey: 'supplier_invoice_no', label: "Supplier's Invoice No", fieldType: FieldType.data),
          FieldDefinition(fieldKey: 'posting_date', label: 'Posting Date', fieldType: FieldType.date, isMandatory: true),
          FieldDefinition(fieldKey: 'due_date', label: 'Due Date', fieldType: FieldType.date),
          FieldDefinition(fieldKey: 'currency', label: 'Currency', fieldType: FieldType.link, options: 'Currency'),
          FieldDefinition(fieldKey: 'items', label: 'Items', fieldType: FieldType.table, options: 'Purchase Invoice Item'),
          FieldDefinition(fieldKey: 'total', label: 'Total', fieldType: FieldType.currency, readOnly: true),
          FieldDefinition(fieldKey: 'tax_total', label: 'Tax Total', fieldType: FieldType.currency, readOnly: true),
          FieldDefinition(fieldKey: 'grand_total', label: 'Grand Total', fieldType: FieldType.currency, readOnly: true),
          FieldDefinition(fieldKey: 'outstanding_amount', label: 'Outstanding', fieldType: FieldType.currency, readOnly: true),
        ],
      );
}
