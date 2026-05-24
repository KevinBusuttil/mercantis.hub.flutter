import 'package:mercantis_core/mercantis_core.dart';

abstract final class SellingModule {
  static const _module = 'Selling';

  static List<DocType> docTypes() => [
        _quotation(),
        _salesOrder(),
        _salesInvoice(),
      ];

  static DocType _quotation() => DocType(
        id: 'Quotation',
        name: 'Quotation',
        module: _module,
        isSubmittable: true,
        namingRule: 'QTN-.YYYY.-.####',
        fields: [
          FieldDefinition(fieldKey: 'customer', label: 'Customer', fieldType: FieldType.link, options: 'Customer', isMandatory: true),
          FieldDefinition(fieldKey: 'transaction_date', label: 'Date', fieldType: FieldType.date, isMandatory: true),
          FieldDefinition(fieldKey: 'valid_till', label: 'Valid Till', fieldType: FieldType.date),
          FieldDefinition(fieldKey: 'currency', label: 'Currency', fieldType: FieldType.link, options: 'Currency'),
          FieldDefinition(fieldKey: 'items', label: 'Items', fieldType: FieldType.table, options: 'Quotation Item'),
          FieldDefinition(fieldKey: 'total', label: 'Total', fieldType: FieldType.currency, readOnly: true),
          FieldDefinition(fieldKey: 'grand_total', label: 'Grand Total', fieldType: FieldType.currency, readOnly: true),
          FieldDefinition(fieldKey: 'terms', label: 'Terms and Conditions', fieldType: FieldType.textEditor),
          FieldDefinition(fieldKey: 'note', label: 'Internal Note', fieldType: FieldType.smallText),
        ],
      );

  static DocType _salesOrder() => DocType(
        id: 'Sales Order',
        name: 'Sales Order',
        module: _module,
        isSubmittable: true,
        namingRule: 'SO-.YYYY.-.####',
        fields: [
          FieldDefinition(fieldKey: 'customer', label: 'Customer', fieldType: FieldType.link, options: 'Customer', isMandatory: true),
          FieldDefinition(fieldKey: 'transaction_date', label: 'Date', fieldType: FieldType.date, isMandatory: true),
          FieldDefinition(fieldKey: 'delivery_date', label: 'Delivery Date', fieldType: FieldType.date),
          FieldDefinition(fieldKey: 'currency', label: 'Currency', fieldType: FieldType.link, options: 'Currency'),
          FieldDefinition(fieldKey: 'items', label: 'Items', fieldType: FieldType.table, options: 'Sales Order Item'),
          FieldDefinition(fieldKey: 'total', label: 'Total', fieldType: FieldType.currency, readOnly: true),
          FieldDefinition(fieldKey: 'grand_total', label: 'Grand Total', fieldType: FieldType.currency, readOnly: true),
          FieldDefinition(fieldKey: 'terms', label: 'Terms and Conditions', fieldType: FieldType.textEditor),
        ],
      );

  static DocType _salesInvoice() => DocType(
        id: 'Sales Invoice',
        name: 'Sales Invoice',
        module: _module,
        isSubmittable: true,
        namingRule: 'SINV-.YYYY.-.####',
        fields: [
          FieldDefinition(fieldKey: 'customer', label: 'Customer', fieldType: FieldType.link, options: 'Customer', isMandatory: true),
          FieldDefinition(fieldKey: 'posting_date', label: 'Posting Date', fieldType: FieldType.date, isMandatory: true),
          FieldDefinition(fieldKey: 'due_date', label: 'Due Date', fieldType: FieldType.date),
          FieldDefinition(fieldKey: 'currency', label: 'Currency', fieldType: FieldType.link, options: 'Currency'),
          FieldDefinition(fieldKey: 'items', label: 'Items', fieldType: FieldType.table, options: 'Sales Invoice Item'),
          FieldDefinition(fieldKey: 'total', label: 'Total', fieldType: FieldType.currency, readOnly: true),
          FieldDefinition(fieldKey: 'tax_total', label: 'Tax Total', fieldType: FieldType.currency, readOnly: true),
          FieldDefinition(fieldKey: 'grand_total', label: 'Grand Total', fieldType: FieldType.currency, readOnly: true),
          FieldDefinition(fieldKey: 'outstanding_amount', label: 'Outstanding', fieldType: FieldType.currency, readOnly: true),
          FieldDefinition(fieldKey: 'payment_terms', label: 'Payment Terms', fieldType: FieldType.data),
        ],
      );
}
