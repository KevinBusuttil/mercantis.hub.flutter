import 'package:mercantis_core/mercantis_core.dart';

abstract final class SetupModule {
  static const _module = 'Setup';

  static List<DocType> docTypes() => [
        _company(),
        _currency(),
        _fiscalYear(),
        _fiscalYearCompany(),
        _costCenter(),
        _hubSettings(),
        _hubAuth(),
        _uom(),
        _brand(),
        _priceList(),
        _itemPrice(),
        _customerGroup(),
        _supplierGroup(),
        _territory(),
      ];

  // ---- catalogue & party masters -----------------------------------------

  static DocType _uom() => const DocType(
        id: 'UOM',
        name: 'UOM',
        module: _module,
        fields: [
          FieldDefinition(key: 'uom_name', label: 'UOM Name', type: FieldType.data, required: true),
          FieldDefinition(key: 'must_be_whole_number', label: 'Must Be Whole Number', type: FieldType.check),
          FieldDefinition(key: 'enabled', label: 'Enabled', type: FieldType.check, defaultValue: '1'),
        ],
      );

  static DocType _brand() => const DocType(
        id: 'Brand',
        name: 'Brand',
        module: _module,
        fields: [
          FieldDefinition(key: 'brand_name', label: 'Brand Name', type: FieldType.data, required: true),
          FieldDefinition(key: 'description', label: 'Description', type: FieldType.longText),
        ],
      );

  static DocType _priceList() => const DocType(
        id: 'Price List',
        name: 'Price List',
        module: _module,
        fields: [
          FieldDefinition(key: 'price_list_name', label: 'Price List Name', type: FieldType.data, required: true),
          FieldDefinition(key: 'currency', label: 'Currency', type: FieldType.link, linkDocType: 'Currency', options: 'Currency', required: true),
          FieldDefinition(key: 'buying', label: 'Used for Buying', type: FieldType.check),
          FieldDefinition(key: 'selling', label: 'Used for Selling', type: FieldType.check, defaultValue: '1'),
          FieldDefinition(key: 'enabled', label: 'Enabled', type: FieldType.check, defaultValue: '1'),
          FieldDefinition(key: 'items', label: 'Item Rates', type: FieldType.table, tableDocType: 'Item Price', options: 'Item Price'),
        ],
      );

  static DocType _itemPrice() => const DocType(
        id: 'Item Price',
        name: 'Item Price',
        module: _module,
        isChild: true,
        fields: [
          FieldDefinition(key: 'item', label: 'Item', type: FieldType.link, linkDocType: 'Item', options: 'Item', required: true),
          FieldDefinition(key: 'uom', label: 'UOM', type: FieldType.link, linkDocType: 'UOM', options: 'UOM'),
          FieldDefinition(key: 'rate', label: 'Rate', type: FieldType.currency, required: true),
          FieldDefinition(key: 'min_qty', label: 'Min Qty', type: FieldType.float, defaultValue: '0'),
          FieldDefinition(key: 'valid_from', label: 'Valid From', type: FieldType.date),
          FieldDefinition(key: 'valid_upto', label: 'Valid Upto', type: FieldType.date),
        ],
      );

  static DocType _customerGroup() => const DocType(
        id: 'Customer Group',
        name: 'Customer Group',
        module: _module,
        isTree: true,
        fields: [
          FieldDefinition(key: 'customer_group_name', label: 'Customer Group Name', type: FieldType.data, required: true),
          FieldDefinition(key: 'parent_customer_group', label: 'Parent Customer Group', type: FieldType.link, linkDocType: 'Customer Group', options: 'Customer Group'),
          FieldDefinition(key: 'is_group', label: 'Is Group', type: FieldType.check),
        ],
      );

  static DocType _supplierGroup() => const DocType(
        id: 'Supplier Group',
        name: 'Supplier Group',
        module: _module,
        isTree: true,
        fields: [
          FieldDefinition(key: 'supplier_group_name', label: 'Supplier Group Name', type: FieldType.data, required: true),
          FieldDefinition(key: 'parent_supplier_group', label: 'Parent Supplier Group', type: FieldType.link, linkDocType: 'Supplier Group', options: 'Supplier Group'),
          FieldDefinition(key: 'is_group', label: 'Is Group', type: FieldType.check),
        ],
      );

  static DocType _territory() => const DocType(
        id: 'Territory',
        name: 'Territory',
        module: _module,
        isTree: true,
        fields: [
          FieldDefinition(key: 'territory_name', label: 'Territory Name', type: FieldType.data, required: true),
          FieldDefinition(key: 'parent_territory', label: 'Parent Territory', type: FieldType.link, linkDocType: 'Territory', options: 'Territory'),
          FieldDefinition(key: 'is_group', label: 'Is Group', type: FieldType.check),
        ],
      );

  /// Single-record app preferences (advanced mode, optional-module visibility,
  /// operator identity). Managed by the Settings screen.
  static DocType _hubSettings() => const DocType(
        id: 'Hub Settings',
        name: 'Hub Settings',
        module: _module,
        fields: [
          FieldDefinition(key: 'advanced_mode', label: 'Advanced Mode', type: FieldType.check),
          FieldDefinition(key: 'pos_enabled', label: 'POS Enabled', type: FieldType.check, defaultValue: '1'),
          FieldDefinition(key: 'manufacturing_enabled', label: 'Manufacturing Enabled', type: FieldType.check, defaultValue: '1'),
          FieldDefinition(key: 'deliveries_enabled', label: 'Deliveries Enabled', type: FieldType.check, defaultValue: '1'),
          FieldDefinition(key: 'operator_name', label: 'Operator Name', type: FieldType.data),
          FieldDefinition(key: 'operator_email', label: 'Operator Email', type: FieldType.data),
        ],
      );

  /// Single-record store of on-device operator profiles (the local passcode
  /// lock). `profiles` holds a JSON array of profiles with salted passcode
  /// digests; `active_id` remembers the signed-in operator. Managed by the
  /// auth gate and Settings, never browsed directly.
  static DocType _hubAuth() => const DocType(
        id: 'Hub Auth',
        name: 'Hub Auth',
        module: _module,
        fields: [
          FieldDefinition(key: 'profiles', label: 'Profiles', type: FieldType.longText),
          FieldDefinition(key: 'active_id', label: 'Active Operator', type: FieldType.data),
        ],
      );

  static DocType _company() => const DocType(
        id: 'Company',
        name: 'Company',
        module: _module,
        isSingleton: false,
        fields: [
          FieldDefinition(key: 'company_name', label: 'Company Name', type: FieldType.data, required: true),
          FieldDefinition(key: 'abbr', label: 'Abbreviation', type: FieldType.data, required: true),
          FieldDefinition(key: 'country', label: 'Country', type: FieldType.data),
          FieldDefinition(key: 'default_currency', label: 'Default Currency', type: FieldType.link, linkDocType: 'Currency', options: 'Currency'),
          // S8 pricing: company-wide selling rates, third in the resolution
          // order (document's list, then customer's, then this).
          FieldDefinition(key: 'default_selling_price_list', label: 'Default Selling Price List', type: FieldType.link, linkDocType: 'Price List', options: 'Price List'),
          FieldDefinition(key: 'default_receivable_account', label: 'Default Receivable Account', type: FieldType.link, linkDocType: 'Account', options: 'Account'),
          FieldDefinition(key: 'default_income_account', label: 'Default Income Account', type: FieldType.link, linkDocType: 'Account', options: 'Account'),
          FieldDefinition(key: 'default_payable_account', label: 'Default Payable Account', type: FieldType.link, linkDocType: 'Account', options: 'Account'),
          FieldDefinition(key: 'default_expense_account', label: 'Default Expense Account', type: FieldType.link, linkDocType: 'Account', options: 'Account'),
          FieldDefinition(key: 'default_cash_account', label: 'Default Cash/Bank Account', type: FieldType.link, linkDocType: 'Account', options: 'Account'),
          FieldDefinition(key: 'default_vat_account', label: 'Default VAT Account', type: FieldType.link, linkDocType: 'Account', options: 'Account'),
          FieldDefinition(key: 'default_inventory_account', label: 'Default Inventory Asset Account', type: FieldType.link, linkDocType: 'Account', options: 'Account'),
          FieldDefinition(key: 'default_cogs_account', label: 'Default COGS Account', type: FieldType.link, linkDocType: 'Account', options: 'Account'),
          FieldDefinition(key: 'default_stock_adjustment_account', label: 'Default Stock Adjustment Account', type: FieldType.link, linkDocType: 'Account', options: 'Account'),
          FieldDefinition(key: 'default_grni_account', label: 'Default Stock Received But Not Billed Account', type: FieldType.link, linkDocType: 'Account', options: 'Account'),
          // Posting guards (H5): postings dated on/before books_lock_date are
          // blocked; stock issues that would drive a bin negative are rejected
          // unless allow_negative_stock is set.
          FieldDefinition(key: 'books_lock_date', label: 'Books Locked Until', type: FieldType.date),
          FieldDefinition(key: 'allow_negative_stock', label: 'Allow Negative Stock', type: FieldType.check),
          FieldDefinition(key: 'tax_id', label: 'Tax ID', type: FieldType.data),
          FieldDefinition(key: 'website', label: 'Website', type: FieldType.data),
          FieldDefinition(key: 'phone_no', label: 'Phone No', type: FieldType.data),
          FieldDefinition(key: 'email', label: 'Email', type: FieldType.data),
          FieldDefinition(key: 'address', label: 'Address', type: FieldType.longText),
          FieldDefinition(key: 'company_logo', label: 'Company Logo', type: FieldType.attachImage),
        ],
      );

  static DocType _currency() => const DocType(
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

  static DocType _fiscalYear() => const DocType(
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
  static DocType _fiscalYearCompany() => const DocType(
        id: 'Fiscal Year Company',
        name: 'Fiscal Year Company',
        module: _module,
        isChild: true,
        fields: [
          FieldDefinition(key: 'company', label: 'Company', type: FieldType.link, linkDocType: 'Company', options: 'Company', required: true),
        ],
      );

  static DocType _costCenter() => const DocType(
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
