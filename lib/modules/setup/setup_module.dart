import 'package:mercantis_core/mercantis_core.dart';

abstract final class SetupModule {
  static const _module = 'Setup';

  static List<DocType> docTypes() => [
        _company(),
        _currency(),
        _fiscalYear(),
        _fiscalYearCompany(),
        _costCenter(),
      ];

  static DocType _company() => DocType(
        id: 'Company',
        name: 'Company',
        module: _module,
        isSingleton: false,
        fields: [
          FieldDefinition(key: 'company_name', label: 'Company Name', type: FieldType.data, required: true),
          FieldDefinition(key: 'abbr', label: 'Abbreviation', type: FieldType.data, required: true),
          FieldDefinition(key: 'country', label: 'Country', type: FieldType.data),
          FieldDefinition(key: 'default_currency', label: 'Default Currency', type: FieldType.link, linkDocType: 'Currency', options: 'Currency'),
          FieldDefinition(key: 'tax_id', label: 'Tax ID', type: FieldType.data),
          FieldDefinition(key: 'website', label: 'Website', type: FieldType.data),
          FieldDefinition(key: 'phone_no', label: 'Phone No', type: FieldType.data),
          FieldDefinition(key: 'email', label: 'Email', type: FieldType.data),
          FieldDefinition(key: 'address', label: 'Address', type: FieldType.longText),
          FieldDefinition(key: 'company_logo', label: 'Company Logo', type: FieldType.attachImage),
        ],
      );

  static DocType _currency() => DocType(
        id: 'Currency',
        name: 'Currency',
        module: _module,
        fields: [
          FieldDefinition(key: 'currency_name', label: 'Currency Name', type: FieldType.data, required: true),
          FieldDefinition(key: 'symbol', label: 'Symbol', type: FieldType.data),
          FieldDefinition(key: 'fraction', label: 'Fraction', type: FieldType.data),
          FieldDefinition(key: 'fraction_units', label: 'Fraction Units', type: FieldType.integer),
          FieldDefinition(key: 'number_format', label: 'Number Format', type: FieldType.data),
          FieldDefinition(key: 'smallest_currency_fraction_value', label: 'Smallest Currency Fraction Value', type: FieldType.float),
          FieldDefinition(key: 'enabled', label: 'Enabled', type: FieldType.check, defaultValue: '1'),
        ],
      );

  static DocType _fiscalYear() => DocType(
        id: 'Fiscal Year',
        name: 'Fiscal Year',
        module: _module,
        fields: [
          FieldDefinition(key: 'year', label: 'Year Name', type: FieldType.data, required: true),
          FieldDefinition(key: 'year_start_date', label: 'Year Start Date', type: FieldType.date, required: true),
          FieldDefinition(key: 'year_end_date', label: 'Year End Date', type: FieldType.date, required: true),
          FieldDefinition(key: 'is_short_year', label: 'Is Short Year', type: FieldType.check),
          FieldDefinition(key: 'companies', label: 'Companies', type: FieldType.table, tableDocType: 'Fiscal Year Company', options: 'Fiscal Year Company'),
        ],
      );

  /// Child table for [_fiscalYear]: companies sharing this fiscal period.
  static DocType _fiscalYearCompany() => DocType(
        id: 'Fiscal Year Company',
        name: 'Fiscal Year Company',
        module: _module,
        isChild: true,
        fields: [
          FieldDefinition(key: 'company', label: 'Company', type: FieldType.link, linkDocType: 'Company', options: 'Company', required: true),
        ],
      );

  static DocType _costCenter() => DocType(
        id: 'Cost Center',
        name: 'Cost Center',
        module: _module,
        isTree: true,
        fields: [
          FieldDefinition(key: 'cost_center_name', label: 'Cost Center Name', type: FieldType.data, required: true),
          FieldDefinition(key: 'parent_cost_center', label: 'Parent Cost Center', type: FieldType.link, linkDocType: 'Cost Center', options: 'Cost Center'),
          FieldDefinition(key: 'company', label: 'Company', type: FieldType.link, linkDocType: 'Company', options: 'Company'),
          FieldDefinition(key: 'is_group', label: 'Is Group', type: FieldType.check),
          FieldDefinition(key: 'disabled', label: 'Disabled', type: FieldType.check),
        ],
      );
}
