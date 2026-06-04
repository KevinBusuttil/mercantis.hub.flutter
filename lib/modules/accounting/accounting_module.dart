import 'package:mercantis_core/mercantis_core.dart';

abstract final class AccountingModule {
  static const _module = 'Accounting';

  /// Append-only conflict policy shared by every derived subledger DocType.
  static const _ledgerPolicy =
      SyncPolicy(conflictResolution: ConflictResolution.appendOnly);

  static const _partyTypeOptions = '\nCustomer\nSupplier\nEmployee';
  static const _transTypeOptions =
      'Invoice\nPayment\nCreditNote\nSettlement\nWriteOff\nAdjustment\nInterest\nFee';

  static List<DocType> docTypes() => [
        _account(),
        _journalEntry(),
        _journalEntryAccount(),
        _payment(),
        _paymentEntryReference(),
        // Derived subledgers — written by the Phase 3 ledger derivation service.
        _glEntry(),
        _customerTransaction(),
        _supplierTransaction(),
        _settlement(),
        _taxTransaction(),
      ];

  static DocType _account() => const DocType(
        id: 'Account',
        name: 'Account',
        module: _module,
        isTree: true,
        fields: [
          FieldDefinition(key: 'account_name', label: 'Account Name', type: FieldType.data, required: true),
          FieldDefinition(key: 'company', label: 'Company', type: FieldType.link, linkDocType: 'Company', options: 'Company'),
          FieldDefinition(
            key: 'root_type',
            label: 'Root Type',
            type: FieldType.select,
            options: 'Asset\nLiability\nIncome\nExpense\nEquity',
          ),
          FieldDefinition(
            key: 'account_type',
            label: 'Account Type',
            type: FieldType.select,
            options: 'Accumulated Depreciation\nAsset Received But Not Billed\nBank\nCash\nChargeable\nCost of Goods Sold\nDepreciation\nEquity\nExpense Account\nExpenses Included In Asset Valuation\nFixed Asset\nIncome Account\nPayable\nReceivable\nRound Off\nStock\nStock Adjustment\nTax\nTemporary',
          ),
          FieldDefinition(key: 'parent_account', label: 'Parent Account', type: FieldType.link, linkDocType: 'Account', options: 'Account'),
          FieldDefinition(key: 'is_group', label: 'Is Group', type: FieldType.check),
          FieldDefinition(key: 'disabled', label: 'Disabled', type: FieldType.check),
          FieldDefinition(key: 'currency', label: 'Account Currency', type: FieldType.link, linkDocType: 'Currency', options: 'Currency'),
        ],
      );

  static DocType _journalEntry() => const DocType(
        id: 'Journal Entry',
        name: 'Journal Entry',
        module: _module,
        isSubmittable: true,
        namingRule: 'JV-.YYYY.-.####',
        workflowId: 'wf-journal-entry',
        fields: [
          FieldDefinition(
            key: 'voucher_type',
            label: 'Voucher Type',
            type: FieldType.select,
            options: 'Journal Entry\nInter Company Journal Entry\nBank Entry\nCash Entry\nCredit Card Entry\nDebit Note\nCredit Note\nContra Entry\nExcise Entry\nWrite Off Entry\nOpening Entry\nDepreciation Entry',
            defaultValue: 'Journal Entry',
          ),
          FieldDefinition(key: 'posting_date', label: 'Posting Date', type: FieldType.date, required: true),
          FieldDefinition(key: 'company', label: 'Company', type: FieldType.link, linkDocType: 'Company', options: 'Company'),
          FieldDefinition(key: 'accounts', label: 'Accounting Entries', type: FieldType.table, tableDocType: 'Journal Entry Account', options: 'Journal Entry Account'),
          FieldDefinition(key: 'total_debit', label: 'Total Debit', type: FieldType.currency, readOnly: true),
          FieldDefinition(key: 'total_credit', label: 'Total Credit', type: FieldType.currency, readOnly: true),
          FieldDefinition(key: 'difference', label: 'Difference', type: FieldType.currency, readOnly: true),
          FieldDefinition(key: 'user_remark', label: 'User Remark', type: FieldType.smallText),
          FieldDefinition(key: 'remark', label: 'Remark', type: FieldType.smallText),
        ],
      );

  /// Child table for [_journalEntry]: one double-entry row.
  static DocType _journalEntryAccount() => const DocType(
        id: 'Journal Entry Account',
        name: 'Journal Entry Account',
        module: _module,
        isChild: true,
        fields: [
          FieldDefinition(key: 'account', label: 'Account', type: FieldType.link, linkDocType: 'Account', options: 'Account', required: true),
          FieldDefinition(key: 'party_type', label: 'Party Type', type: FieldType.select, options: _partyTypeOptions),
          FieldDefinition(key: 'party', label: 'Party', type: FieldType.data),
          FieldDefinition(key: 'debit', label: 'Debit', type: FieldType.currency, defaultValue: '0'),
          FieldDefinition(key: 'credit', label: 'Credit', type: FieldType.currency, defaultValue: '0'),
          FieldDefinition(key: 'cost_center', label: 'Cost Center', type: FieldType.link, linkDocType: 'Cost Center', options: 'Cost Center'),
          FieldDefinition(key: 'reference_doctype', label: 'Reference DocType', type: FieldType.select, options: '\nSales Invoice\nPurchase Invoice\nPayment Entry\nJournal Entry'),
          FieldDefinition(key: 'reference_name', label: 'Reference Name', type: FieldType.data),
        ],
      );

  static DocType _payment() => const DocType(
        id: 'Payment Entry',
        name: 'Payment Entry',
        module: _module,
        isSubmittable: true,
        namingRule: 'PAY-.YYYY.-.####',
        workflowId: 'wf-payment-entry',
        fields: [
          FieldDefinition(
            key: 'payment_type',
            label: 'Payment Type',
            type: FieldType.select,
            options: 'Receive\nPay\nInternal Transfer',
            required: true,
          ),
          FieldDefinition(key: 'posting_date', label: 'Posting Date', type: FieldType.date, required: true),
          FieldDefinition(
            key: 'party_type',
            label: 'Party Type',
            type: FieldType.select,
            options: 'Customer\nSupplier\nEmployee\nShareholder',
          ),
          FieldDefinition(key: 'party', label: 'Party', type: FieldType.dynamicLink, linkDocType: 'party_type', options: 'party_type'),
          FieldDefinition(key: 'party_name', label: 'Party Name', type: FieldType.data, readOnly: true),
          FieldDefinition(key: 'paid_from', label: 'Paid From', type: FieldType.link, linkDocType: 'Account', options: 'Account'),
          FieldDefinition(key: 'paid_to', label: 'Paid To', type: FieldType.link, linkDocType: 'Account', options: 'Account'),
          FieldDefinition(key: 'paid_amount', label: 'Paid Amount', type: FieldType.currency, required: true),
          FieldDefinition(key: 'received_amount', label: 'Received Amount', type: FieldType.currency),
          // Invoice allocations — promoted to Settlement rows on submit (Phase 3).
          FieldDefinition(key: 'references', label: 'Payment References', type: FieldType.table, tableDocType: 'Payment Entry Reference', options: 'Payment Entry Reference'),
          FieldDefinition(
            key: 'mode_of_payment',
            label: 'Mode of Payment',
            type: FieldType.select,
            options: 'Cash\nBank Transfer\nCredit Card\nCheque\nWire Transfer\nOnline',
          ),
          FieldDefinition(key: 'reference_no', label: 'Reference No', type: FieldType.data),
          FieldDefinition(key: 'remarks', label: 'Remarks', type: FieldType.smallText),
        ],
      );

  /// Child table for [_payment]: an allocation of the payment against an
  /// outstanding invoice or journal entry.
  static DocType _paymentEntryReference() => const DocType(
        id: 'Payment Entry Reference',
        name: 'Payment Entry Reference',
        module: _module,
        isChild: true,
        fields: [
          FieldDefinition(key: 'reference_doctype', label: 'Reference DocType', type: FieldType.select, options: 'Sales Invoice\nPurchase Invoice\nJournal Entry', required: true),
          FieldDefinition(key: 'reference_name', label: 'Reference Name', type: FieldType.data, required: true),
          FieldDefinition(key: 'total_amount', label: 'Total Amount', type: FieldType.currency),
          FieldDefinition(key: 'outstanding_amount', label: 'Outstanding', type: FieldType.currency),
          FieldDefinition(key: 'allocated_amount', label: 'Allocated Amount', type: FieldType.currency, required: true, defaultValue: '0'),
        ],
      );

  /// The universal general ledger. One or more rows per submitted Invoice /
  /// Payment / Journal / Stock voucher; reversals append `is_reversal` rows.
  static DocType _glEntry() => const DocType(
        id: 'GL Entry',
        name: 'GL Entry',
        module: _module,
        syncPolicy: _ledgerPolicy,
        fields: [
          FieldDefinition(key: 'posting_date', label: 'Posting Date', type: FieldType.date, required: true),
          FieldDefinition(key: 'account', label: 'Account', type: FieldType.link, linkDocType: 'Account', options: 'Account', required: true),
          FieldDefinition(key: 'debit', label: 'Debit', type: FieldType.currency, defaultValue: '0'),
          FieldDefinition(key: 'credit', label: 'Credit', type: FieldType.currency, defaultValue: '0'),
          FieldDefinition(key: 'party_type', label: 'Party Type', type: FieldType.select, options: _partyTypeOptions),
          FieldDefinition(key: 'party', label: 'Party', type: FieldType.data),
          FieldDefinition(key: 'cost_center', label: 'Cost Center', type: FieldType.link, linkDocType: 'Cost Center', options: 'Cost Center'),
          FieldDefinition(key: 'voucher_type', label: 'Voucher Type', type: FieldType.data, required: true),
          FieldDefinition(key: 'voucher_no', label: 'Voucher No', type: FieldType.data, required: true),
          FieldDefinition(key: 'remarks', label: 'Remarks', type: FieldType.longText),
          FieldDefinition(key: 'is_reversal', label: 'Reversal', type: FieldType.check),
        ],
      );

  /// Customer subledger (Swift `CustTrans`): signed amounts, positive = the
  /// customer owes us. Powers the Customer Statement & aging reports.
  static DocType _customerTransaction() => const DocType(
        id: 'Customer Transaction',
        name: 'Customer Transaction',
        module: _module,
        syncPolicy: _ledgerPolicy,
        fields: [
          FieldDefinition(key: 'trans_type', label: 'Trans Type', type: FieldType.select, options: _transTypeOptions, required: true),
          FieldDefinition(key: 'customer', label: 'Customer', type: FieldType.link, linkDocType: 'Customer', options: 'Customer', required: true),
          FieldDefinition(key: 'posting_date', label: 'Posting Date', type: FieldType.date, required: true),
          FieldDefinition(key: 'due_date', label: 'Due Date', type: FieldType.date),
          FieldDefinition(key: 'amount', label: 'Amount', type: FieldType.currency, required: true, defaultValue: '0'),
          FieldDefinition(key: 'currency', label: 'Currency', type: FieldType.link, linkDocType: 'Currency', options: 'Currency'),
          FieldDefinition(key: 'voucher_type', label: 'Voucher Type', type: FieldType.data, required: true),
          FieldDefinition(key: 'voucher_no', label: 'Voucher No', type: FieldType.data, required: true),
          FieldDefinition(key: 'is_reversal', label: 'Reversal', type: FieldType.check),
        ],
      );

  /// Supplier subledger (Swift `VendTrans`): symmetric to customer; positive =
  /// we owe the supplier.
  static DocType _supplierTransaction() => const DocType(
        id: 'Supplier Transaction',
        name: 'Supplier Transaction',
        module: _module,
        syncPolicy: _ledgerPolicy,
        fields: [
          FieldDefinition(key: 'trans_type', label: 'Trans Type', type: FieldType.select, options: _transTypeOptions, required: true),
          FieldDefinition(key: 'supplier', label: 'Supplier', type: FieldType.link, linkDocType: 'Supplier', options: 'Supplier', required: true),
          FieldDefinition(key: 'posting_date', label: 'Posting Date', type: FieldType.date, required: true),
          FieldDefinition(key: 'due_date', label: 'Due Date', type: FieldType.date),
          FieldDefinition(key: 'amount', label: 'Amount', type: FieldType.currency, required: true, defaultValue: '0'),
          FieldDefinition(key: 'currency', label: 'Currency', type: FieldType.link, linkDocType: 'Currency', options: 'Currency'),
          FieldDefinition(key: 'voucher_type', label: 'Voucher Type', type: FieldType.data, required: true),
          FieldDefinition(key: 'voucher_no', label: 'Voucher No', type: FieldType.data, required: true),
          FieldDefinition(key: 'is_reversal', label: 'Reversal', type: FieldType.check),
        ],
      );

  /// Explicit "payment X settled invoice Y for amount Z" rows — derived from
  /// `Payment Entry.references` on submit. Makes statement reports trivial.
  static DocType _settlement() => const DocType(
        id: 'Settlement',
        name: 'Settlement',
        module: _module,
        syncPolicy: _ledgerPolicy,
        fields: [
          FieldDefinition(key: 'payment_voucher_type', label: 'Payment DocType', type: FieldType.data, required: true),
          FieldDefinition(key: 'payment_voucher_no', label: 'Payment No', type: FieldType.data, required: true),
          FieldDefinition(key: 'invoice_voucher_type', label: 'Invoice DocType', type: FieldType.data, required: true),
          FieldDefinition(key: 'invoice_voucher_no', label: 'Invoice No', type: FieldType.data, required: true),
          FieldDefinition(key: 'party_type', label: 'Party Type', type: FieldType.select, options: 'Customer\nSupplier', required: true),
          FieldDefinition(key: 'party', label: 'Party', type: FieldType.data, required: true),
          FieldDefinition(key: 'allocated_amount', label: 'Allocated Amount', type: FieldType.currency, required: true, defaultValue: '0'),
          FieldDefinition(key: 'posting_date', label: 'Posting Date', type: FieldType.date, required: true),
          FieldDefinition(key: 'is_reversal', label: 'Reversal', type: FieldType.check),
        ],
      );

  /// Tax subledger (Swift `TaxTrans`): VAT / WHT / sales-tax postings. Reserved
  /// here; rows begin flowing once the Tax module's derivation lands.
  static DocType _taxTransaction() => const DocType(
        id: 'Tax Transaction',
        name: 'Tax Transaction',
        module: _module,
        syncPolicy: _ledgerPolicy,
        fields: [
          FieldDefinition(key: 'tax_type', label: 'Tax Type', type: FieldType.select, options: 'VAT\nSalesTax\nWHT\nExciseDuty', required: true),
          FieldDefinition(key: 'tax', label: 'Tax', type: FieldType.data),
          FieldDefinition(key: 'posting_date', label: 'Posting Date', type: FieldType.date, required: true),
          FieldDefinition(key: 'base_amount', label: 'Taxable Base', type: FieldType.currency, required: true, defaultValue: '0'),
          FieldDefinition(key: 'tax_amount', label: 'Tax Amount', type: FieldType.currency, required: true, defaultValue: '0'),
          FieldDefinition(key: 'rate', label: 'Rate (%)', type: FieldType.float, defaultValue: '0'),
          FieldDefinition(key: 'party_type', label: 'Party Type', type: FieldType.select, options: '\nCustomer\nSupplier'),
          FieldDefinition(key: 'party', label: 'Party', type: FieldType.data),
          FieldDefinition(key: 'voucher_type', label: 'Voucher Type', type: FieldType.data, required: true),
          FieldDefinition(key: 'voucher_no', label: 'Voucher No', type: FieldType.data, required: true),
          FieldDefinition(key: 'is_reversal', label: 'Reversal', type: FieldType.check),
        ],
      );
}
