import 'package:mercantis_core/mercantis_core.dart';

/// Banking master data + reconciliation records (H1 — ported from the Swift Hub
/// `Banking` module: BankAccount / BankStatementLine / BankReconciliation).
///
///  * `Bank Account` — a real-world bank account, mapped to the GL `Account`
///    (type Bank) its movements post to.
///  * `Bank Statement Line` — one imported statement transaction (signed
///    `amount` = deposit − withdrawal), the unit the matching service later
///    reconciles against a Payment Entry / Journal Entry.
///  * `Bank Reconciliation` — a reconcile session for an account over a period:
///    statement opening/closing vs the ledger balance, and the resulting
///    difference that must reach zero.
abstract final class BankingModule {
  static const _module = 'Banking';

  static List<DocType> docTypes() => [
        _bankAccount(),
        _bankStatementLine(),
        _bankReconciliation(),
      ];

  static DocType _bankAccount() => const DocType(
        id: 'Bank Account',
        name: 'Bank Account',
        module: _module,
        fields: [
          FieldDefinition(key: 'account_name', label: 'Account Name', type: FieldType.data, required: true),
          FieldDefinition(key: 'bank_name', label: 'Bank', type: FieldType.data),
          FieldDefinition(key: 'account_number', label: 'Account Number', type: FieldType.data),
          FieldDefinition(key: 'iban', label: 'IBAN', type: FieldType.data),
          FieldDefinition(key: 'swift_bic', label: 'SWIFT / BIC', type: FieldType.data),
          FieldDefinition(key: 'currency', label: 'Currency', type: FieldType.link, linkDocType: 'Currency', options: 'Currency'),
          // The ledger account (type Bank) this account's movements post to —
          // what the reconciliation compares the statement against.
          FieldDefinition(key: 'gl_account', label: 'Ledger Account', type: FieldType.link, linkDocType: 'Account', options: 'Account'),
          FieldDefinition(key: 'is_default', label: 'Default', type: FieldType.check),
          FieldDefinition(key: 'disabled', label: 'Disabled', type: FieldType.check),
        ],
      );

  static DocType _bankStatementLine() => const DocType(
        id: 'Bank Statement Line',
        name: 'Bank Statement Line',
        module: _module,
        fields: [
          FieldDefinition(key: 'bank_account', label: 'Bank Account', type: FieldType.link, linkDocType: 'Bank Account', options: 'Bank Account', required: true),
          FieldDefinition(key: 'posting_date', label: 'Date', type: FieldType.date, required: true),
          FieldDefinition(key: 'description', label: 'Description', type: FieldType.data),
          FieldDefinition(key: 'reference_number', label: 'Reference', type: FieldType.data),
          // Money in / out, plus the signed amount the matcher works with.
          FieldDefinition(key: 'deposit', label: 'Deposit', type: FieldType.currency, defaultValue: '0'),
          FieldDefinition(key: 'withdrawal', label: 'Withdrawal', type: FieldType.currency, defaultValue: '0'),
          FieldDefinition(key: 'amount', label: 'Amount', type: FieldType.currency, readOnly: true, formulaExpression: 'deposit - withdrawal'),
          FieldDefinition(
            key: 'status',
            label: 'Status',
            type: FieldType.select,
            options: 'Unreconciled\nReconciled\nIgnored',
            defaultValue: 'Unreconciled',
          ),
          // What this line was reconciled against, once matched.
          FieldDefinition(key: 'matched_voucher_type', label: 'Matched Voucher Type', type: FieldType.select, options: 'Payment Entry\nJournal Entry'),
          FieldDefinition(key: 'matched_voucher', label: 'Matched Voucher', type: FieldType.data),
          // Groups the lines that came in from one CSV import.
          FieldDefinition(key: 'import_batch', label: 'Import Batch', type: FieldType.data),
        ],
      );

  static DocType _bankReconciliation() => const DocType(
        id: 'Bank Reconciliation',
        name: 'Bank Reconciliation',
        module: _module,
        fields: [
          FieldDefinition(key: 'bank_account', label: 'Bank Account', type: FieldType.link, linkDocType: 'Bank Account', options: 'Bank Account', required: true),
          FieldDefinition(key: 'from_date', label: 'From Date', type: FieldType.date),
          FieldDefinition(key: 'to_date', label: 'To Date', type: FieldType.date),
          FieldDefinition(key: 'statement_opening_balance', label: 'Statement Opening Balance', type: FieldType.currency, defaultValue: '0'),
          FieldDefinition(key: 'statement_closing_balance', label: 'Statement Closing Balance', type: FieldType.currency, defaultValue: '0'),
          // Filled by the reconciliation flow from the GL: the ledger balance on
          // the account and the gap to the statement (must reach 0 to clear).
          FieldDefinition(key: 'ledger_balance', label: 'Ledger Balance', type: FieldType.currency, readOnly: true, defaultValue: '0'),
          FieldDefinition(key: 'difference', label: 'Difference', type: FieldType.currency, readOnly: true, defaultValue: '0'),
        ],
      );
}
