import 'package:mercantis_core/mercantis_core.dart';

abstract final class StockModule {
  static const _module = 'Stock';

  static List<DocType> docTypes() => [
        _itemGroup(),
        _item(),
        _warehouse(),
        _stockEntry(),
        _stockEntryDetail(),
        _stockLedgerEntry(),
        _bin(),
      ];

  static DocType _itemGroup() => const DocType(
        id: 'Item Group',
        name: 'Item Group',
        module: _module,
        isTree: true,
        fields: [
          FieldDefinition(key: 'item_group_name', label: 'Name', type: FieldType.data, required: true),
          FieldDefinition(key: 'parent_item_group', label: 'Parent', type: FieldType.link, linkDocType: 'Item Group', options: 'Item Group'),
          FieldDefinition(key: 'is_group', label: 'Is Group', type: FieldType.check),
          FieldDefinition(key: 'description', label: 'Description', type: FieldType.smallText),
        ],
      );

  static DocType _item() => const DocType(
        id: 'Item',
        name: 'Item',
        module: _module,
        isSubmittable: false,
        fields: [
          FieldDefinition(key: 'item_code', label: 'Item Code', type: FieldType.data, required: true),
          FieldDefinition(key: 'item_name', label: 'Item Name', type: FieldType.data, required: true),
          FieldDefinition(key: 'item_group', label: 'Item Group', type: FieldType.link, linkDocType: 'Item Group', options: 'Item Group'),
          FieldDefinition(key: 'description', label: 'Description', type: FieldType.longText),
          FieldDefinition(
            key: 'stock_uom',
            label: 'Stock UOM',
            type: FieldType.select,
            options: 'Nos\nKg\nGrams\nLitre\nMetre\nBox\nPair\nSet',
            defaultValue: 'Nos',
          ),
          FieldDefinition(key: 'standard_rate', label: 'Standard Selling Rate', type: FieldType.currency),
          FieldDefinition(key: 'standard_buying_rate', label: 'Standard Buying Rate', type: FieldType.currency),
          FieldDefinition(key: 'is_stock_item', label: 'Is Stock Item', type: FieldType.check, defaultValue: '1'),
          FieldDefinition(key: 'is_service_item', label: 'Is Service Item', type: FieldType.check),
          FieldDefinition(key: 'disabled', label: 'Disabled', type: FieldType.check),
          FieldDefinition(key: 'image', label: 'Image', type: FieldType.attachImage),
          FieldDefinition(key: 'barcode', label: 'Barcode', type: FieldType.barcode),
        ],
      );

  static DocType _warehouse() => const DocType(
        id: 'Warehouse',
        name: 'Warehouse',
        module: _module,
        isTree: true,
        fields: [
          FieldDefinition(key: 'warehouse_name', label: 'Warehouse Name', type: FieldType.data, required: true),
          FieldDefinition(key: 'company', label: 'Company', type: FieldType.link, linkDocType: 'Company', options: 'Company'),
          FieldDefinition(
            key: 'warehouse_type',
            label: 'Warehouse Type',
            type: FieldType.select,
            options: 'Stores\nWork In Progress\nFinished Goods\nScrap\nVirtual',
          ),
          FieldDefinition(key: 'parent_warehouse', label: 'Parent Warehouse', type: FieldType.link, linkDocType: 'Warehouse', options: 'Warehouse'),
          FieldDefinition(key: 'is_group', label: 'Is Group', type: FieldType.check),
          FieldDefinition(key: 'disabled', label: 'Disabled', type: FieldType.check),
          FieldDefinition(key: 'address', label: 'Address', type: FieldType.smallText),
        ],
      );

  static DocType _stockEntry() => const DocType(
        id: 'Stock Entry',
        name: 'Stock Entry',
        module: _module,
        isSubmittable: true,
        namingRule: 'STE-.YYYY.-.####',
        workflowId: 'wf-stock-entry',
        fields: [
          FieldDefinition(
            key: 'stock_entry_type',
            label: 'Stock Entry Type',
            type: FieldType.select,
            options: 'Material Issue\nMaterial Receipt\nMaterial Transfer\nManufacture\nRepack',
            required: true,
          ),
          FieldDefinition(key: 'posting_date', label: 'Posting Date', type: FieldType.date, required: true),
          FieldDefinition(key: 'from_warehouse', label: 'From Warehouse', type: FieldType.link, linkDocType: 'Warehouse', options: 'Warehouse'),
          FieldDefinition(key: 'to_warehouse', label: 'To Warehouse', type: FieldType.link, linkDocType: 'Warehouse', options: 'Warehouse'),
          FieldDefinition(key: 'items', label: 'Items', type: FieldType.table, tableDocType: 'Stock Entry Detail', options: 'Stock Entry Detail'),
          FieldDefinition(key: 'total_amount', label: 'Total Amount', type: FieldType.currency, readOnly: true),
          FieldDefinition(key: 'remarks', label: 'Remarks', type: FieldType.smallText),
        ],
      );

  /// Child table for [_stockEntry]: a two-leg movement (out of
  /// `source_warehouse`, into `target_warehouse`). `amount` = qty × valuation.
  static DocType _stockEntryDetail() => const DocType(
        id: 'Stock Entry Detail',
        name: 'Stock Entry Detail',
        module: _module,
        isChild: true,
        fields: [
          FieldDefinition(key: 'item', label: 'Item', type: FieldType.link, linkDocType: 'Item', options: 'Item', required: true),
          FieldDefinition(key: 'uom', label: 'UOM', type: FieldType.select, options: 'Nos\nKg\nGrams\nLitre\nMetre\nBox\nPair\nSet', defaultValue: 'Nos'),
          FieldDefinition(key: 'qty', label: 'Quantity', type: FieldType.float, required: true, defaultValue: '0'),
          FieldDefinition(key: 'source_warehouse', label: 'Source Warehouse', type: FieldType.link, linkDocType: 'Warehouse', options: 'Warehouse'),
          FieldDefinition(key: 'target_warehouse', label: 'Target Warehouse', type: FieldType.link, linkDocType: 'Warehouse', options: 'Warehouse'),
          FieldDefinition(key: 'valuation_rate', label: 'Valuation Rate', type: FieldType.currency),
          FieldDefinition(key: 'amount', label: 'Amount', type: FieldType.currency, readOnly: true, formulaExpression: 'qty * valuation_rate'),
        ],
      );

  /// Append-only stock ledger. Rows are derived by the Phase 3
  /// `StockBalanceService`/ledger derivation on submit & cancel (signed
  /// `qty_change`; reversals append negated rows with `is_reversal = true`).
  static DocType _stockLedgerEntry() => const DocType(
        id: 'Stock Ledger Entry',
        name: 'Stock Ledger Entry',
        module: _module,
        syncPolicy: const SyncPolicy(conflictResolution: ConflictResolution.appendOnly),
        fields: [
          FieldDefinition(
            key: 'trans_type',
            label: 'Trans Type',
            type: FieldType.select,
            options: 'Receipt\nIssue\nTransfer\nAdjustment\nCounting\nReservation\nProduction',
            defaultValue: 'Issue',
          ),
          FieldDefinition(key: 'item', label: 'Item', type: FieldType.link, linkDocType: 'Item', options: 'Item', required: true),
          FieldDefinition(key: 'warehouse', label: 'Warehouse', type: FieldType.link, linkDocType: 'Warehouse', options: 'Warehouse', required: true),
          FieldDefinition(key: 'posting_date', label: 'Posting Date', type: FieldType.date, required: true),
          FieldDefinition(key: 'posting_time', label: 'Posting Time', type: FieldType.dateTime),
          FieldDefinition(key: 'voucher_type', label: 'Voucher Type', type: FieldType.data, required: true),
          FieldDefinition(key: 'voucher_no', label: 'Voucher No', type: FieldType.data, required: true),
          FieldDefinition(key: 'qty_change', label: 'Qty Change', type: FieldType.float, required: true, defaultValue: '0'),
          FieldDefinition(key: 'valuation_rate', label: 'Valuation Rate', type: FieldType.currency),
          FieldDefinition(key: 'amount', label: 'Amount', type: FieldType.currency, readOnly: true, formulaExpression: 'qty_change * valuation_rate'),
          FieldDefinition(key: 'is_reversal', label: 'Reversal', type: FieldType.check),
        ],
      );

  /// Derived running balance per (item, warehouse). Recomputed from the full
  /// ledger by `StockBalanceService` after each stock movement — not edited
  /// directly.
  static DocType _bin() => const DocType(
        id: 'Bin',
        name: 'Bin',
        module: _module,
        fields: [
          FieldDefinition(key: 'item', label: 'Item', type: FieldType.link, linkDocType: 'Item', options: 'Item', required: true),
          FieldDefinition(key: 'warehouse', label: 'Warehouse', type: FieldType.link, linkDocType: 'Warehouse', options: 'Warehouse', required: true),
          FieldDefinition(key: 'actual_qty', label: 'Actual Qty', type: FieldType.float, defaultValue: '0'),
          FieldDefinition(key: 'valuation_rate', label: 'Valuation Rate', type: FieldType.currency, defaultValue: '0'),
          FieldDefinition(key: 'stock_value', label: 'Stock Value', type: FieldType.currency, defaultValue: '0'),
          FieldDefinition(key: 'last_movement_date', label: 'Last Movement', type: FieldType.date),
        ],
      );
}
