import 'package:mercantis_core/mercantis_core.dart';

abstract final class AccountingModule {
  static const _module = 'Accounting';

  static List<DocType> docTypes() => [
        _account(),
        _journalEntry(),
        _payment(),
      ];

  static DocType _account() => DocType(
        id: 'Account',
        name: 'Account',
        module: _module,
        isTree: true,
        fields: [
          FieldDefinition(key: 'account_name', label: 'Account Name', type: FieldType.data, required: true),
          FieldDefinition(key: 'company', label: 'Company', type: FieldType.link, options: 'Company'),
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
          FieldDefinition(key: 'parent_account', label: 'Parent Account', type: FieldType.link, options: 'Account'),
          FieldDefinition(key: 'is_group', label: 'Is Group', type: FieldType.check),
          FieldDefinition(key: 'disabled', label: 'Disabled', type: FieldType.check),
          FieldDefinition(key: 'currency', label: 'Account Currency', type: FieldType.link, options: 'Currency'),
        ],
      );

  static DocType _journalEntry() => DocType(
        id: 'Journal Entry',
        name: 'Journal Entry',
        module: _module,
        isSubmittable: true,
        namingRule: 'JV-.YYYY.-.####',
        fields: [
          FieldDefinition(
            key: 'voucher_type',
            label: 'Voucher Type',
            type: FieldType.select,
            options: 'Journal Entry\nInter Company Journal Entry\nBank Entry\nCash Entry\nCredit Card Entry\nDebit Note\nCredit Note\nContra Entry\nExcise Entry\nWrite Off Entry\nOpening Entry\nDepreciation Entry',
            defaultValue: 'Journal Entry',
          ),
          FieldDefinition(key: 'posting_date', label: 'Posting Date', type: FieldType.date, required: true),
          FieldDefinition(key: 'company', label: 'Company', type: FieldType.link, options: 'Company'),
          FieldDefinition(key: 'accounts', label: 'Accounting Entries', type: FieldType.table, options: 'Journal Entry Account'),
          FieldDefinition(key: 'total_debit', label: 'Total Debit', type: FieldType.currency, readOnly: true),
          FieldDefinition(key: 'total_credit', label: 'Total Credit', type: FieldType.currency, readOnly: true),
          FieldDefinition(key: 'difference', label: 'Difference', type: FieldType.currency, readOnly: true),
          FieldDefinition(key: 'user_remark', label: 'User Remark', type: FieldType.smallText),
          FieldDefinition(key: 'remark', label: 'Remark', type: FieldType.smallText),
        ],
      );

  static DocType _payment() => DocType(
        id: 'Payment Entry',
        name: 'Payment Entry',
        module: _module,
        isSubmittable: true,
        namingRule: 'PAY-.YYYY.-.####',
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
          FieldDefinition(key: 'party', label: 'Party', type: FieldType.dynamicLink, options: 'party_type'),
          FieldDefinition(key: 'party_name', label: 'Party Name', type: FieldType.data, readOnly: true),
          FieldDefinition(key: 'paid_from', label: 'Paid From', type: FieldType.link, options: 'Account'),
          FieldDefinition(key: 'paid_to', label: 'Paid To', type: FieldType.link, options: 'Account'),
          FieldDefinition(key: 'paid_amount', label: 'Paid Amount', type: FieldType.currency, required: true),
          FieldDefinition(key: 'received_amount', label: 'Received Amount', type: FieldType.currency),
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
}
