import 'package:mercantis_core/mercantis_core.dart';

abstract final class StockModule {
  static const _module = 'Stock';

  static List<DocType> docTypes() => [
        _itemGroup(),
        _item(),
        _warehouse(),
        _stockEntry(),
      ];

  static DocType _itemGroup() => DocType(
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

  static DocType _item() => DocType(
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

  static DocType _warehouse() => DocType(
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

  static DocType _stockEntry() => DocType(
        id: 'Stock Entry',
        name: 'Stock Entry',
        module: _module,
        isSubmittable: true,
        namingRule: 'STE-.YYYY.-.####',
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
}
