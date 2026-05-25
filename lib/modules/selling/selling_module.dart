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
          FieldDefinition(key: 'customer', label: 'Customer', type: FieldType.link, options: 'Customer', required: true),
          FieldDefinition(key: 'transaction_date', label: 'Date', type: FieldType.date, required: true),
          FieldDefinition(key: 'valid_till', label: 'Valid Till', type: FieldType.date),
          FieldDefinition(key: 'currency', label: 'Currency', type: FieldType.link, options: 'Currency'),
          FieldDefinition(key: 'items', label: 'Items', type: FieldType.table, options: 'Quotation Item'),
          FieldDefinition(key: 'total', label: 'Total', type: FieldType.currency, readOnly: true),
          FieldDefinition(key: 'grand_total', label: 'Grand Total', type: FieldType.currency, readOnly: true),
          FieldDefinition(key: 'terms', label: 'Terms and Conditions', type: FieldType.longText),
          FieldDefinition(key: 'note', label: 'Internal Note', type: FieldType.smallText),
        ],
      );

  static DocType _salesOrder() => DocType(
        id: 'Sales Order',
        name: 'Sales Order',
        module: _module,
        isSubmittable: true,
        namingRule: 'SO-.YYYY.-.####',
        fields: [
          FieldDefinition(key: 'customer', label: 'Customer', type: FieldType.link, options: 'Customer', required: true),
          FieldDefinition(key: 'transaction_date', label: 'Date', type: FieldType.date, required: true),
          FieldDefinition(key: 'delivery_date', label: 'Delivery Date', type: FieldType.date),
          FieldDefinition(key: 'currency', label: 'Currency', type: FieldType.link, options: 'Currency'),
          FieldDefinition(key: 'items', label: 'Items', type: FieldType.table, options: 'Sales Order Item'),
          FieldDefinition(key: 'total', label: 'Total', type: FieldType.currency, readOnly: true),
          FieldDefinition(key: 'grand_total', label: 'Grand Total', type: FieldType.currency, readOnly: true),
          FieldDefinition(key: 'terms', label: 'Terms and Conditions', type: FieldType.longText),
        ],
      );

  static DocType _salesInvoice() => DocType(
        id: 'Sales Invoice',
        name: 'Sales Invoice',
        module: _module,
        isSubmittable: true,
        namingRule: 'SINV-.YYYY.-.####',
        fields: [
          FieldDefinition(key: 'customer', label: 'Customer', type: FieldType.link, options: 'Customer', required: true),
          FieldDefinition(key: 'posting_date', label: 'Posting Date', type: FieldType.date, required: true),
          FieldDefinition(key: 'due_date', label: 'Due Date', type: FieldType.date),
          FieldDefinition(key: 'currency', label: 'Currency', type: FieldType.link, options: 'Currency'),
          FieldDefinition(key: 'items', label: 'Items', type: FieldType.table, options: 'Sales Invoice Item'),
          FieldDefinition(key: 'total', label: 'Total', type: FieldType.currency, readOnly: true),
          FieldDefinition(key: 'tax_total', label: 'Tax Total', type: FieldType.currency, readOnly: true),
          FieldDefinition(key: 'grand_total', label: 'Grand Total', type: FieldType.currency, readOnly: true),
          FieldDefinition(key: 'outstanding_amount', label: 'Outstanding', type: FieldType.currency, readOnly: true),
          FieldDefinition(key: 'payment_terms', label: 'Payment Terms', type: FieldType.data),
        ],
      );
}
