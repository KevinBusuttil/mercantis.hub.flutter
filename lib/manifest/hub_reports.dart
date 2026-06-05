import 'package:mercantis_core/mercantis_core.dart';

/// The Hub's report catalogue — 14 flat "list-and-format" reports that read the
/// real document store (mostly the ledger rows the derivation spine produces)
/// through the Core [ReportEngine]. Aggregating reports (Trial Balance, aging)
/// are layered on top app-side later; these are the straight registers.
abstract final class HubReports {
  static const _date = 'date';
  static const _currency = 'currency';
  static const _number = 'number';

  static List<ReportDefinition> all() => const [
        // ---- accounting --------------------------------------------------
        ReportDefinition(
          id: 'general_ledger',
          name: 'General Ledger',
          docType: 'GL Entry',
          columns: [
            ReportColumn(fieldKey: 'posting_date', label: 'Date', type: _date),
            ReportColumn(fieldKey: 'account', label: 'Account'),
            ReportColumn(fieldKey: 'debit', label: 'Debit', type: _currency),
            ReportColumn(fieldKey: 'credit', label: 'Credit', type: _currency),
            ReportColumn(fieldKey: 'party', label: 'Party'),
            ReportColumn(fieldKey: 'voucher_type', label: 'Voucher Type'),
            ReportColumn(fieldKey: 'voucher_no', label: 'Voucher No'),
          ],
        ),
        ReportDefinition(
          id: 'accounts_receivable',
          name: 'Accounts Receivable',
          docType: 'Customer Transaction',
          columns: [
            ReportColumn(fieldKey: 'posting_date', label: 'Date', type: _date),
            ReportColumn(fieldKey: 'customer', label: 'Customer'),
            ReportColumn(fieldKey: 'trans_type', label: 'Type'),
            ReportColumn(fieldKey: 'amount', label: 'Amount', type: _currency),
            ReportColumn(fieldKey: 'due_date', label: 'Due', type: _date),
            ReportColumn(fieldKey: 'voucher_no', label: 'Voucher No'),
          ],
        ),
        ReportDefinition(
          id: 'accounts_payable',
          name: 'Accounts Payable',
          docType: 'Supplier Transaction',
          columns: [
            ReportColumn(fieldKey: 'posting_date', label: 'Date', type: _date),
            ReportColumn(fieldKey: 'supplier', label: 'Supplier'),
            ReportColumn(fieldKey: 'trans_type', label: 'Type'),
            ReportColumn(fieldKey: 'amount', label: 'Amount', type: _currency),
            ReportColumn(fieldKey: 'due_date', label: 'Due', type: _date),
            ReportColumn(fieldKey: 'voucher_no', label: 'Voucher No'),
          ],
        ),
        ReportDefinition(
          id: 'journal_register',
          name: 'Journal Register',
          docType: 'Journal Entry',
          columns: [
            ReportColumn(fieldKey: 'id', label: 'Entry'),
            ReportColumn(fieldKey: 'posting_date', label: 'Date', type: _date),
            ReportColumn(fieldKey: 'status', label: 'Status'),
          ],
        ),
        // ---- selling -----------------------------------------------------
        ReportDefinition(
          id: 'sales_register',
          name: 'Sales Register',
          docType: 'Sales Invoice',
          columns: [
            ReportColumn(fieldKey: 'id', label: 'Invoice'),
            ReportColumn(fieldKey: 'customer', label: 'Customer'),
            ReportColumn(fieldKey: 'posting_date', label: 'Date', type: _date),
            ReportColumn(fieldKey: 'grand_total', label: 'Total', type: _currency),
            ReportColumn(fieldKey: 'outstanding_amount', label: 'Outstanding', type: _currency),
            ReportColumn(fieldKey: 'status', label: 'Status'),
          ],
        ),
        ReportDefinition(
          id: 'sales_order_book',
          name: 'Sales Order Book',
          docType: 'Sales Order',
          columns: [
            ReportColumn(fieldKey: 'id', label: 'Order'),
            ReportColumn(fieldKey: 'customer', label: 'Customer'),
            ReportColumn(fieldKey: 'transaction_date', label: 'Date', type: _date),
            ReportColumn(fieldKey: 'grand_total', label: 'Total', type: _currency),
            ReportColumn(fieldKey: 'status', label: 'Status'),
          ],
        ),
        ReportDefinition(
          id: 'delivery_register',
          name: 'Delivery Register',
          docType: 'Delivery Note',
          columns: [
            ReportColumn(fieldKey: 'id', label: 'Delivery Note'),
            ReportColumn(fieldKey: 'customer', label: 'Customer'),
            ReportColumn(fieldKey: 'posting_date', label: 'Date', type: _date),
            ReportColumn(fieldKey: 'set_warehouse', label: 'Warehouse'),
            ReportColumn(fieldKey: 'status', label: 'Status'),
          ],
        ),
        // ---- buying ------------------------------------------------------
        ReportDefinition(
          id: 'purchase_register',
          name: 'Purchase Register',
          docType: 'Purchase Invoice',
          columns: [
            ReportColumn(fieldKey: 'id', label: 'Invoice'),
            ReportColumn(fieldKey: 'supplier', label: 'Supplier'),
            ReportColumn(fieldKey: 'posting_date', label: 'Date', type: _date),
            ReportColumn(fieldKey: 'grand_total', label: 'Total', type: _currency),
            ReportColumn(fieldKey: 'outstanding_amount', label: 'Outstanding', type: _currency),
            ReportColumn(fieldKey: 'status', label: 'Status'),
          ],
        ),
        ReportDefinition(
          id: 'purchase_order_book',
          name: 'Purchase Order Book',
          docType: 'Purchase Order',
          columns: [
            ReportColumn(fieldKey: 'id', label: 'Order'),
            ReportColumn(fieldKey: 'supplier', label: 'Supplier'),
            ReportColumn(fieldKey: 'transaction_date', label: 'Date', type: _date),
            ReportColumn(fieldKey: 'grand_total', label: 'Total', type: _currency),
            ReportColumn(fieldKey: 'status', label: 'Status'),
          ],
        ),
        ReportDefinition(
          id: 'purchase_receipt_register',
          name: 'Purchase Receipt Register',
          docType: 'Purchase Receipt',
          columns: [
            ReportColumn(fieldKey: 'id', label: 'Receipt'),
            ReportColumn(fieldKey: 'supplier', label: 'Supplier'),
            ReportColumn(fieldKey: 'posting_date', label: 'Date', type: _date),
            ReportColumn(fieldKey: 'set_warehouse', label: 'Warehouse'),
            ReportColumn(fieldKey: 'status', label: 'Status'),
          ],
        ),
        // ---- payments ----------------------------------------------------
        ReportDefinition(
          id: 'payment_register',
          name: 'Payment Register',
          docType: 'Payment Entry',
          columns: [
            ReportColumn(fieldKey: 'id', label: 'Payment'),
            ReportColumn(fieldKey: 'posting_date', label: 'Date', type: _date),
            ReportColumn(fieldKey: 'payment_type', label: 'Type'),
            ReportColumn(fieldKey: 'party', label: 'Party'),
            ReportColumn(fieldKey: 'paid_amount', label: 'Amount', type: _currency),
          ],
        ),
        ReportDefinition(
          id: 'settlement_register',
          name: 'Settlement Register',
          docType: 'Settlement',
          columns: [
            ReportColumn(fieldKey: 'posting_date', label: 'Date', type: _date),
            ReportColumn(fieldKey: 'party', label: 'Party'),
            ReportColumn(fieldKey: 'invoice_voucher_no', label: 'Invoice'),
            ReportColumn(fieldKey: 'payment_voucher_no', label: 'Payment'),
            ReportColumn(fieldKey: 'allocated_amount', label: 'Allocated', type: _currency),
          ],
        ),
        // ---- stock -------------------------------------------------------
        ReportDefinition(
          id: 'stock_ledger',
          name: 'Stock Ledger',
          docType: 'Stock Ledger Entry',
          columns: [
            ReportColumn(fieldKey: 'posting_date', label: 'Date', type: _date),
            ReportColumn(fieldKey: 'item', label: 'Item'),
            ReportColumn(fieldKey: 'warehouse', label: 'Warehouse'),
            ReportColumn(fieldKey: 'qty_change', label: 'Qty Change', type: _number),
            ReportColumn(fieldKey: 'valuation_rate', label: 'Rate', type: _currency),
            ReportColumn(fieldKey: 'voucher_no', label: 'Voucher No'),
          ],
        ),
        ReportDefinition(
          id: 'stock_balance',
          name: 'Stock Balance',
          docType: 'Bin',
          columns: [
            ReportColumn(fieldKey: 'item', label: 'Item'),
            ReportColumn(fieldKey: 'warehouse', label: 'Warehouse'),
            ReportColumn(fieldKey: 'actual_qty', label: 'Qty', type: _number),
            ReportColumn(fieldKey: 'valuation_rate', label: 'Rate', type: _currency),
            ReportColumn(fieldKey: 'stock_value', label: 'Value', type: _currency),
          ],
        ),
      ];
}
