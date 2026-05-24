import 'package:mercantis_core/mercantis_core.dart';

abstract final class SetupModule {
  static const _module = 'Setup';

  static List<DocType> docTypes() => [
        _company(),
        _currency(),
        _fiscalYear(),
        _costCenter(),
      ];

  static DocType _company() => DocType(
        id: 'Company',
        name: 'Company',
        module: _module,
        isSingleton: false,
        fields: [
          FieldDefinition(fieldKey: 'company_name', label: 'Company Name', fieldType: FieldType.data, isMandatory: true),
          FieldDefinition(fieldKey: 'abbr', label: 'Abbreviation', fieldType: FieldType.data, isMandatory: true),
          FieldDefinition(fieldKey: 'country', label: 'Country', fieldType: FieldType.data),
          FieldDefinition(fieldKey: 'default_currency', label: 'Default Currency', fieldType: FieldType.link, options: 'Currency'),
          FieldDefinition(fieldKey: 'tax_id', label: 'Tax ID', fieldType: FieldType.data),
          FieldDefinition(fieldKey: 'website', label: 'Website', fieldType: FieldType.data),
          FieldDefinition(fieldKey: 'phone_no', label: 'Phone No', fieldType: FieldType.data),
          FieldDefinition(fieldKey: 'email', label: 'Email', fieldType: FieldType.data),
          FieldDefinition(fieldKey: 'address', label: 'Address', fieldType: FieldType.textEditor),
          FieldDefinition(fieldKey: 'company_logo', label: 'Company Logo', fieldType: FieldType.attachImage),
        ],
      );

  static DocType _currency() => DocType(
        id: 'Currency',
        name: 'Currency',
        module: _module,
        fields: [
          FieldDefinition(fieldKey: 'currency_name', label: 'Currency Name', fieldType: FieldType.data, isMandatory: true),
          FieldDefinition(fieldKey: 'symbol', label: 'Symbol', fieldType: FieldType.data),
          FieldDefinition(fieldKey: 'fraction', label: 'Fraction', fieldType: FieldType.data),
          FieldDefinition(fieldKey: 'fraction_units', label: 'Fraction Units', fieldType: FieldType.integer),
          FieldDefinition(fieldKey: 'number_format', label: 'Number Format', fieldType: FieldType.data),
          FieldDefinition(fieldKey: 'smallest_currency_fraction_value', label: 'Smallest Currency Fraction Value', fieldType: FieldType.float),
          FieldDefinition(fieldKey: 'enabled', label: 'Enabled', fieldType: FieldType.check, defaultValue: '1'),
        ],
      );

  static DocType _fiscalYear() => DocType(
        id: 'Fiscal Year',
        name: 'Fiscal Year',
        module: _module,
        fields: [
          FieldDefinition(fieldKey: 'year', label: 'Year Name', fieldType: FieldType.data, isMandatory: true),
          FieldDefinition(fieldKey: 'year_start_date', label: 'Year Start Date', fieldType: FieldType.date, isMandatory: true),
          FieldDefinition(fieldKey: 'year_end_date', label: 'Year End Date', fieldType: FieldType.date, isMandatory: true),
          FieldDefinition(fieldKey: 'is_short_year', label: 'Is Short Year', fieldType: FieldType.check),
          FieldDefinition(fieldKey: 'companies', label: 'Companies', fieldType: FieldType.table, options: 'Fiscal Year Company'),
        ],
      );

  static DocType _costCenter() => DocType(
        id: 'Cost Center',
        name: 'Cost Center',
        module: _module,
        isTree: true,
        fields: [
          FieldDefinition(fieldKey: 'cost_center_name', label: 'Cost Center Name', fieldType: FieldType.data, isMandatory: true),
          FieldDefinition(fieldKey: 'parent_cost_center', label: 'Parent Cost Center', fieldType: FieldType.link, options: 'Cost Center'),
          FieldDefinition(fieldKey: 'company', label: 'Company', fieldType: FieldType.link, options: 'Company'),
          FieldDefinition(fieldKey: 'is_group', label: 'Is Group', fieldType: FieldType.check),
          FieldDefinition(fieldKey: 'disabled', label: 'Disabled', fieldType: FieldType.check),
        ],
      );
}
