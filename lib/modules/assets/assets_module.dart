import 'package:mercantis_core/mercantis_core.dart';

/// S10 Fixed Assets (Phase 5). The Asset is a REGISTER document — like a
/// Job, it carries state (Draft → In Use → Disposed) but never posts GL
/// itself. The money lives in submitted Journal Entries: one per
/// depreciation period (Dr expense / Cr accumulated) and one at disposal
/// (clear gross + accumulated, book proceeds, balance to gain/loss) —
/// all through the ordinary JE balance guard and ledger derivation.
abstract final class AssetsModule {
  static const _module = 'Assets';

  static List<DocType> docTypes() => [
        _assetCategory(),
        _asset(),
        _depreciationRow(),
      ];

  /// Account and life defaults per kind of asset ("Vehicles", "Equipment").
  static DocType _assetCategory() => const DocType(
        id: 'Asset Category',
        name: 'Asset Category',
        module: _module,
        fields: [
          FieldDefinition(key: 'category_name', label: 'Category', type: FieldType.data, required: true),
          FieldDefinition(key: 'asset_account', label: 'Asset Account', type: FieldType.link, linkDocType: 'Account', options: 'Account'),
          FieldDefinition(key: 'accumulated_depreciation_account', label: 'Accumulated Depreciation', type: FieldType.link, linkDocType: 'Account', options: 'Account'),
          FieldDefinition(key: 'depreciation_expense_account', label: 'Depreciation Expense', type: FieldType.link, linkDocType: 'Account', options: 'Account'),
          FieldDefinition(key: 'useful_life_months', label: 'Useful Life (months)', type: FieldType.integer, defaultValue: '60'),
        ],
      );

  static DocType _asset() => const DocType(
        id: 'Asset',
        name: 'Asset',
        module: _module,
        namingRule: 'AST-.YYYY.-.####',
        fields: [
          FieldDefinition(key: 'asset_name', label: 'Asset', type: FieldType.data, required: true),
          FieldDefinition(key: 'category', label: 'Category', type: FieldType.link, linkDocType: 'Asset Category', options: 'Asset Category'),
          FieldDefinition(
            key: 'status',
            label: 'Status',
            type: FieldType.select,
            options: 'Draft\nIn Use\nDisposed',
            defaultValue: 'Draft',
          ),
          FieldDefinition(key: 'purchase_date', label: 'Purchase Date', type: FieldType.date, required: true),
          FieldDefinition(key: 'gross_purchase_amount', label: 'Gross Cost', type: FieldType.currency, required: true),
          FieldDefinition(key: 'salvage_value', label: 'Salvage Value', type: FieldType.currency, defaultValue: '0'),
          FieldDefinition(key: 'useful_life_months', label: 'Useful Life (months)', type: FieldType.integer),
          // Defaults to purchase_date when blank.
          FieldDefinition(key: 'depreciation_start', label: 'Depreciate From', type: FieldType.date),
          // Accounts fall back to the category's.
          FieldDefinition(key: 'asset_account', label: 'Asset Account', type: FieldType.link, linkDocType: 'Account', options: 'Account'),
          FieldDefinition(key: 'accumulated_depreciation_account', label: 'Accumulated Depreciation', type: FieldType.link, linkDocType: 'Account', options: 'Account'),
          FieldDefinition(key: 'depreciation_expense_account', label: 'Depreciation Expense', type: FieldType.link, linkDocType: 'Account', options: 'Account'),
          FieldDefinition(key: 'schedule', label: 'Depreciation Schedule', type: FieldType.table, tableDocType: 'Asset Depreciation Row', options: 'Asset Depreciation Row'),
          // Disposal trail, stamped by AssetService.dispose.
          FieldDefinition(key: 'disposal_date', label: 'Disposed On', type: FieldType.date, readOnly: true),
          FieldDefinition(key: 'disposal_journal', label: 'Disposal Entry', type: FieldType.link, linkDocType: 'Journal Entry', options: 'Journal Entry', readOnly: true),
          FieldDefinition(key: 'notes', label: 'Notes', type: FieldType.smallText),
        ],
      );

  /// One depreciation period. `journal_entry` + `posted` are stamped when
  /// the period's JE submits — the row is the idempotency record.
  static DocType _depreciationRow() => const DocType(
        id: 'Asset Depreciation Row',
        name: 'Asset Depreciation Row',
        module: _module,
        isChild: true,
        fields: [
          FieldDefinition(key: 'period_date', label: 'Period', type: FieldType.date, required: true),
          FieldDefinition(key: 'amount', label: 'Amount', type: FieldType.currency, required: true),
          FieldDefinition(key: 'journal_entry', label: 'Posted As', type: FieldType.link, linkDocType: 'Journal Entry', options: 'Journal Entry', readOnly: true),
          FieldDefinition(key: 'posted', label: 'Posted', type: FieldType.check, readOnly: true),
        ],
      );
}
