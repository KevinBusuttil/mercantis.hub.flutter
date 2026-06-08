import 'package:mercantis_core/mercantis_core.dart';

/// VAT / Tax foundation master data (ported from the Swift Hub `Tax` module).
///
/// Two masters plus one shared child table:
///  * `Tax Category` — optional grouping (Goods, Services, Domestic…).
///  * `Tax Code` — the VAT code itself (Standard / Reduced / Zero / Exempt),
///    each carrying a rate and a posting account.
///  * `Tax Charge` — one computed tax row inside an invoice's `taxes` table,
///    populated on save by `TaxCalculationInterceptor` and turned into
///    `Tax Transaction` ledger rows + GL legs on submit by the ledger spine.
abstract final class TaxModule {
  static const _module = 'Tax';

  static List<DocType> docTypes() => [
        _taxCategory(),
        _taxCode(),
        _taxCharge(),
      ];

  /// Optional grouping for tax codes. Micro businesses can ignore it; it exists
  /// so codes can be organised without overloading the code name.
  static DocType _taxCategory() => const DocType(
        id: 'Tax Category',
        name: 'Tax Category',
        module: _module,
        fields: [
          FieldDefinition(key: 'tax_category_name', label: 'Tax Category Name', type: FieldType.data, required: true),
          FieldDefinition(key: 'description', label: 'Description', type: FieldType.longText),
          FieldDefinition(key: 'enabled', label: 'Enabled', type: FieldType.check, defaultValue: '1'),
        ],
      );

  /// The VAT / tax code. Create one record per band: Standard (e.g. 18),
  /// Reduced (e.g. 7), Zero (0), Exempt (0). `tax_account` is the GL account the
  /// tax posts to; when blank, derivation falls back to the Company's
  /// `default_vat_account`.
  static DocType _taxCode() => const DocType(
        id: 'Tax Code',
        name: 'Tax Code',
        module: _module,
        fields: [
          FieldDefinition(key: 'tax_code_name', label: 'Tax Code Name', type: FieldType.data, required: true),
          FieldDefinition(key: 'tax_type', label: 'Tax Type', type: FieldType.select, options: 'VAT\nSalesTax', defaultValue: 'VAT', required: true),
          FieldDefinition(key: 'rate', label: 'Rate (%)', type: FieldType.float, required: true, defaultValue: '0'),
          FieldDefinition(key: 'tax_category', label: 'Tax Category', type: FieldType.link, linkDocType: 'Tax Category', options: 'Tax Category'),
          FieldDefinition(key: 'tax_account', label: 'Tax Account', type: FieldType.link, linkDocType: 'Account', options: 'Account'),
          FieldDefinition(key: 'is_default', label: 'Default', type: FieldType.check),
          FieldDefinition(key: 'enabled', label: 'Enabled', type: FieldType.check, defaultValue: '1'),
        ],
      );

  /// One computed tax row inside a Sales / Purchase Invoice `taxes` child table.
  /// Shared between sales and purchase so there is a single tax-row shape.
  static DocType _taxCharge() => const DocType(
        id: 'Tax Charge',
        name: 'Tax Charge',
        module: _module,
        isChild: true,
        fields: [
          FieldDefinition(key: 'tax_code', label: 'Tax Code', type: FieldType.link, linkDocType: 'Tax Code', options: 'Tax Code', required: true),
          FieldDefinition(key: 'tax_type', label: 'Tax Type', type: FieldType.data),
          FieldDefinition(key: 'description', label: 'Description', type: FieldType.data),
          FieldDefinition(key: 'rate', label: 'Rate (%)', type: FieldType.float, defaultValue: '0'),
          FieldDefinition(key: 'tax_account', label: 'Tax Account', type: FieldType.link, linkDocType: 'Account', options: 'Account'),
          FieldDefinition(key: 'taxable_amount', label: 'Taxable Amount', type: FieldType.currency, defaultValue: '0'),
          FieldDefinition(key: 'tax_amount', label: 'Tax Amount', type: FieldType.currency, defaultValue: '0'),
        ],
      );
}
