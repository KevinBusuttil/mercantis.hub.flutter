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
          FieldDefinition(fieldKey: 'account_name', label: 'Account Name', fieldType: FieldType.data, isMandatory: true),
          FieldDefinition(fieldKey: 'company', label: 'Company', fieldType: FieldType.link, options: 'Company'),
          FieldDefinition(
            fieldKey: 'root_type',
            label: 'Root Type',
            fieldType: FieldType.select,
            options: 'Asset\nLiability\nIncome\nExpense\nEquity',
          ),
          FieldDefinition(
            fieldKey: 'account_type',
            label: 'Account Type',
            fieldType: FieldType.select,
            options: 'Accumulated Depreciation\nAsset Received But Not Billed\nBank\nCash\nChargeable\nCost of Goods Sold\nDepreciation\nEquity\nExpense Account\nExpenses Included In Asset Valuation\nFixed Asset\nIncome Account\nPayable\nReceivable\nRound Off\nStock\nStock Adjustment\nTax\nTemporary',
          ),
          FieldDefinition(fieldKey: 'parent_account', label: 'Parent Account', fieldType: FieldType.link, options: 'Account'),
          FieldDefinition(fieldKey: 'is_group', label: 'Is Group', fieldType: FieldType.check),
          FieldDefinition(fieldKey: 'disabled', label: 'Disabled', fieldType: FieldType.check),
          FieldDefinition(fieldKey: 'currency', label: 'Account Currency', fieldType: FieldType.link, options: 'Currency'),
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
            fieldKey: 'voucher_type',
            label: 'Voucher Type',
            fieldType: FieldType.select,
            options: 'Journal Entry\nInter Company Journal Entry\nBank Entry\nCash Entry\nCredit Card Entry\nDebit Note\nCredit Note\nContra Entry\nExcise Entry\nWrite Off Entry\nOpening Entry\nDepreciation Entry',
            defaultValue: 'Journal Entry',
          ),
          FieldDefinition(fieldKey: 'posting_date', label: 'Posting Date', fieldType: FieldType.date, isMandatory: true),
          FieldDefinition(fieldKey: 'company', label: 'Company', fieldType: FieldType.link, options: 'Company'),
          FieldDefinition(fieldKey: 'accounts', label: 'Accounting Entries', fieldType: FieldType.table, options: 'Journal Entry Account'),
          FieldDefinition(fieldKey: 'total_debit', label: 'Total Debit', fieldType: FieldType.currency, readOnly: true),
          FieldDefinition(fieldKey: 'total_credit', label: 'Total Credit', fieldType: FieldType.currency, readOnly: true),
          FieldDefinition(fieldKey: 'difference', label: 'Difference', fieldType: FieldType.currency, readOnly: true),
          FieldDefinition(fieldKey: 'user_remark', label: 'User Remark', fieldType: FieldType.smallText),
          FieldDefinition(fieldKey: 'remark', label: 'Remark', fieldType: FieldType.smallText),
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
            fieldKey: 'payment_type',
            label: 'Payment Type',
            fieldType: FieldType.select,
            options: 'Receive\nPay\nInternal Transfer',
            isMandatory: true,
          ),
          FieldDefinition(fieldKey: 'posting_date', label: 'Posting Date', fieldType: FieldType.date, isMandatory: true),
          FieldDefinition(
            fieldKey: 'party_type',
            label: 'Party Type',
            fieldType: FieldType.select,
            options: 'Customer\nSupplier\nEmployee\nShareholder',
          ),
          FieldDefinition(fieldKey: 'party', label: 'Party', fieldType: FieldType.dynamicLink, options: 'party_type'),
          FieldDefinition(fieldKey: 'party_name', label: 'Party Name', fieldType: FieldType.data, readOnly: true),
          FieldDefinition(fieldKey: 'paid_from', label: 'Paid From', fieldType: FieldType.link, options: 'Account'),
          FieldDefinition(fieldKey: 'paid_to', label: 'Paid To', fieldType: FieldType.link, options: 'Account'),
          FieldDefinition(fieldKey: 'paid_amount', label: 'Paid Amount', fieldType: FieldType.currency, isMandatory: true),
          FieldDefinition(fieldKey: 'received_amount', label: 'Received Amount', fieldType: FieldType.currency),
          FieldDefinition(
            fieldKey: 'mode_of_payment',
            label: 'Mode of Payment',
            fieldType: FieldType.select,
            options: 'Cash\nBank Transfer\nCredit Card\nCheque\nWire Transfer\nOnline',
          ),
          FieldDefinition(fieldKey: 'reference_no', label: 'Reference No', fieldType: FieldType.data),
          FieldDefinition(fieldKey: 'remarks', label: 'Remarks', fieldType: FieldType.smallText),
        ],
      );
}
