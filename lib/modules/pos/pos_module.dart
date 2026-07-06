import 'package:mercantis_core/mercantis_core.dart';

import '../common/line_items.dart';

/// Point-of-sale module (ported from the Swift Hub `POS`). A POS Invoice is a
/// cash sale: it issues stock and posts Dr Cash / Cr Income (+ output VAT) with
/// no receivable — payment is captured inline via `tenders`. It reuses the tax
/// engine (it carries a `taxes` table) and the stock derivation (its warehouse
/// field is `set_warehouse`). POS Profile / POS Session are config/session
/// records and do not post.
abstract final class PosModule {
  static const _module = 'POS';

  static List<DocType> docTypes() => [
        _posProfile(),
        _posSession(),
        _posInvoice(),
        lineItemDocType(id: 'POS Invoice Item', module: _module),
        _paymentTender(),
      ];

  /// Till configuration: supplies default warehouse / accounts / customer.
  static DocType _posProfile() => const DocType(
        id: 'POS Profile',
        name: 'POS Profile',
        module: _module,
        fields: [
          FieldDefinition(key: 'profile_name', label: 'Profile Name', type: FieldType.data, required: true),
          FieldDefinition(key: 'warehouse', label: 'Warehouse', type: FieldType.link, linkDocType: 'Warehouse', options: 'Warehouse'),
          FieldDefinition(key: 'customer', label: 'Default Customer', type: FieldType.link, linkDocType: 'Customer', options: 'Customer'),
          FieldDefinition(key: 'currency', label: 'Currency', type: FieldType.link, linkDocType: 'Currency', options: 'Currency'),
          FieldDefinition(key: 'cash_account', label: 'Cash / Bank Account', type: FieldType.link, linkDocType: 'Account', options: 'Account'),
          FieldDefinition(key: 'income_account', label: 'Income Account', type: FieldType.link, linkDocType: 'Account', options: 'Account'),
          FieldDefinition(key: 'tax_code', label: 'Default Tax Code', type: FieldType.link, linkDocType: 'Tax Code', options: 'Tax Code'),
          FieldDefinition(key: 'prices_include_tax', label: 'Prices Include Tax', type: FieldType.check, defaultValue: '1'),
          FieldDefinition(key: 'enabled', label: 'Enabled', type: FieldType.check, defaultValue: '1'),
        ],
      );

  /// Operational till session (open/close). Reporting only — does not post.
  static DocType _posSession() => const DocType(
        id: 'POS Session',
        name: 'POS Session',
        module: _module,
        fields: [
          FieldDefinition(key: 'pos_profile', label: 'POS Profile', type: FieldType.link, linkDocType: 'POS Profile', options: 'POS Profile', required: true),
          FieldDefinition(key: 'status', label: 'Status', type: FieldType.select, options: 'Open\nClosed', defaultValue: 'Open'),
          FieldDefinition(key: 'opening_date', label: 'Opened', type: FieldType.date),
          FieldDefinition(key: 'closing_date', label: 'Closed', type: FieldType.date),
          FieldDefinition(key: 'opening_amount', label: 'Opening Float', type: FieldType.currency, defaultValue: '0'),
          FieldDefinition(key: 'closing_amount', label: 'Closing Cash', type: FieldType.currency),
          FieldDefinition(key: 'total_sales', label: 'Total Sales', type: FieldType.currency, defaultValue: '0'),
          FieldDefinition(key: 'total_qty', label: 'Items Sold', type: FieldType.float, defaultValue: '0'),
        ],
      );

  /// Cash sale. Submittable; posting (Dr Cash / Cr Income / output VAT + stock
  /// issue) is handled by the ledger derivation on submit/cancel.
  static DocType _posInvoice() => const DocType(
        id: 'POS Invoice',
        name: 'POS Invoice',
        module: _module,
        isSubmittable: true,
        namingRule: 'POS-.YYYY.-.####',
        workflowId: 'wf-pos-invoice',
        fields: [
          FieldDefinition(key: 'pos_profile', label: 'POS Profile', type: FieldType.link, linkDocType: 'POS Profile', options: 'POS Profile'),
          FieldDefinition(key: 'pos_session', label: 'POS Session', type: FieldType.link, linkDocType: 'POS Session', options: 'POS Session'),
          FieldDefinition(key: 'customer', label: 'Customer', type: FieldType.link, linkDocType: 'Customer', options: 'Customer'),
          FieldDefinition(key: 'posting_date', label: 'Date', type: FieldType.date, required: true),
          FieldDefinition(key: 'currency', label: 'Currency', type: FieldType.link, linkDocType: 'Currency', options: 'Currency'),
          // `set_warehouse` so the shared stock derivation issues stock from it.
          FieldDefinition(key: 'set_warehouse', label: 'Warehouse', type: FieldType.link, linkDocType: 'Warehouse', options: 'Warehouse'),
          FieldDefinition(key: 'tax_code', label: 'Default Tax Code', type: FieldType.link, linkDocType: 'Tax Code', options: 'Tax Code'),
          FieldDefinition(key: 'prices_include_tax', label: 'Prices Include Tax', type: FieldType.check),
          // Posting accounts (resolved from POS Profile / Company defaults).
          FieldDefinition(key: 'cash_account', label: 'Cash / Bank Account', type: FieldType.link, linkDocType: 'Account', options: 'Account'),
          FieldDefinition(key: 'income_account', label: 'Income Account', type: FieldType.link, linkDocType: 'Account', options: 'Account'),
          // Returns (H6): a POS refund is a POS Invoice with is_return set and
          // negative line quantities — cash and income reverse, and the stock
          // returns at the original sale's cost (return_against).
          FieldDefinition(key: 'is_return', label: 'Is Return', type: FieldType.check),
          FieldDefinition(key: 'return_against', label: 'Return Against', type: FieldType.link, linkDocType: 'POS Invoice', options: 'POS Invoice'),
          FieldDefinition(key: 'items', label: 'Items', type: FieldType.table, tableDocType: 'POS Invoice Item', options: 'POS Invoice Item'),
          FieldDefinition(key: 'total', label: 'Total', type: FieldType.currency, readOnly: true),
          FieldDefinition(key: 'taxes', label: 'Taxes', type: FieldType.table, tableDocType: 'Tax Charge', options: 'Tax Charge'),
          FieldDefinition(key: 'tax_total', label: 'Tax Total', type: FieldType.currency, readOnly: true),
          FieldDefinition(key: 'grand_total', label: 'Grand Total', type: FieldType.currency, readOnly: true),
          FieldDefinition(key: 'tenders', label: 'Payments', type: FieldType.table, tableDocType: 'Payment Tender', options: 'Payment Tender'),
          FieldDefinition(key: 'paid_amount', label: 'Paid Amount', type: FieldType.currency, readOnly: true),
          FieldDefinition(key: 'change_amount', label: 'Change', type: FieldType.currency, readOnly: true),
          FieldDefinition(key: 'remarks', label: 'Remarks', type: FieldType.smallText, allowOnSubmit: true),
        ],
      );

  /// One payment line on a POS Invoice.
  static DocType _paymentTender() => const DocType(
        id: 'Payment Tender',
        name: 'Payment Tender',
        module: _module,
        isChild: true,
        fields: [
          FieldDefinition(key: 'tender_type', label: 'Tender', type: FieldType.select, options: 'Cash\nCard\nOther', defaultValue: 'Cash', required: true),
          FieldDefinition(key: 'amount', label: 'Amount', type: FieldType.currency, required: true, defaultValue: '0'),
          FieldDefinition(key: 'reference', label: 'Reference', type: FieldType.data),
        ],
      );
}
