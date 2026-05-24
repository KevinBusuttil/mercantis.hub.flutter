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
          FieldDefinition(fieldKey: 'item_group_name', label: 'Name', fieldType: FieldType.data, isMandatory: true),
          FieldDefinition(fieldKey: 'parent_item_group', label: 'Parent', fieldType: FieldType.link, options: 'Item Group'),
          FieldDefinition(fieldKey: 'is_group', label: 'Is Group', fieldType: FieldType.check),
          FieldDefinition(fieldKey: 'description', label: 'Description', fieldType: FieldType.smallText),
        ],
      );

  static DocType _item() => DocType(
        id: 'Item',
        name: 'Item',
        module: _module,
        isSubmittable: false,
        fields: [
          FieldDefinition(fieldKey: 'item_code', label: 'Item Code', fieldType: FieldType.data, isMandatory: true),
          FieldDefinition(fieldKey: 'item_name', label: 'Item Name', fieldType: FieldType.data, isMandatory: true),
          FieldDefinition(fieldKey: 'item_group', label: 'Item Group', fieldType: FieldType.link, options: 'Item Group'),
          FieldDefinition(fieldKey: 'description', label: 'Description', fieldType: FieldType.textEditor),
          FieldDefinition(
            fieldKey: 'stock_uom',
            label: 'Stock UOM',
            fieldType: FieldType.select,
            options: 'Nos\nKg\nGrams\nLitre\nMetre\nBox\nPair\nSet',
            defaultValue: 'Nos',
          ),
          FieldDefinition(fieldKey: 'standard_rate', label: 'Standard Selling Rate', fieldType: FieldType.currency),
          FieldDefinition(fieldKey: 'standard_buying_rate', label: 'Standard Buying Rate', fieldType: FieldType.currency),
          FieldDefinition(fieldKey: 'is_stock_item', label: 'Is Stock Item', fieldType: FieldType.check, defaultValue: '1'),
          FieldDefinition(fieldKey: 'is_service_item', label: 'Is Service Item', fieldType: FieldType.check),
          FieldDefinition(fieldKey: 'disabled', label: 'Disabled', fieldType: FieldType.check),
          FieldDefinition(fieldKey: 'image', label: 'Image', fieldType: FieldType.attachImage),
          FieldDefinition(fieldKey: 'barcode', label: 'Barcode', fieldType: FieldType.barcode),
        ],
      );

  static DocType _warehouse() => DocType(
        id: 'Warehouse',
        name: 'Warehouse',
        module: _module,
        isTree: true,
        fields: [
          FieldDefinition(fieldKey: 'warehouse_name', label: 'Warehouse Name', fieldType: FieldType.data, isMandatory: true),
          FieldDefinition(fieldKey: 'company', label: 'Company', fieldType: FieldType.link, options: 'Company'),
          FieldDefinition(
            fieldKey: 'warehouse_type',
            label: 'Warehouse Type',
            fieldType: FieldType.select,
            options: 'Stores\nWork In Progress\nFinished Goods\nScrap\nVirtual',
          ),
          FieldDefinition(fieldKey: 'parent_warehouse', label: 'Parent Warehouse', fieldType: FieldType.link, options: 'Warehouse'),
          FieldDefinition(fieldKey: 'is_group', label: 'Is Group', fieldType: FieldType.check),
          FieldDefinition(fieldKey: 'disabled', label: 'Disabled', fieldType: FieldType.check),
          FieldDefinition(fieldKey: 'address', label: 'Address', fieldType: FieldType.smallText),
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
            fieldKey: 'stock_entry_type',
            label: 'Stock Entry Type',
            fieldType: FieldType.select,
            options: 'Material Issue\nMaterial Receipt\nMaterial Transfer\nManufacture\nRepack',
            isMandatory: true,
          ),
          FieldDefinition(fieldKey: 'posting_date', label: 'Posting Date', fieldType: FieldType.date, isMandatory: true),
          FieldDefinition(fieldKey: 'from_warehouse', label: 'From Warehouse', fieldType: FieldType.link, options: 'Warehouse'),
          FieldDefinition(fieldKey: 'to_warehouse', label: 'To Warehouse', fieldType: FieldType.link, options: 'Warehouse'),
          FieldDefinition(fieldKey: 'items', label: 'Items', fieldType: FieldType.table, options: 'Stock Entry Detail'),
          FieldDefinition(fieldKey: 'total_amount', label: 'Total Amount', fieldType: FieldType.currency, readOnly: true),
          FieldDefinition(fieldKey: 'remarks', label: 'Remarks', fieldType: FieldType.smallText),
        ],
      );
}
