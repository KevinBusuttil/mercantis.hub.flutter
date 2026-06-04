import 'package:mercantis_core/mercantis_core.dart';

/// Shared unit-of-measure options. UOM is modelled as a select (mirroring
/// `Item.stock_uom`) rather than a link, because there is no `UOM` DocType in
/// the Flutter manifest yet; this keeps line-item `uom` values valid without a
/// dangling link target.
const String kUomOptions = 'Nos\nKg\nGrams\nLitre\nMetre\nBox\nPair\nSet';

/// Builds a transactional line-item child DocType (Quotation Item, Sales Order
/// Item, Purchase Order Item, …). All sales/purchase line tables share the same
/// shape in the Swift Hub (`SalesItem` / `PurchaseItem`); the `amount` column is
/// a read-only formula (`qty * rate`) evaluated by the core expression engine.
///
/// `tax_code` is intentionally omitted until the Tax module is ported, to avoid
/// a link to a DocType that does not exist yet.
DocType lineItemDocType({
  required String id,
  required String module,
  String warehouseLabel = 'Warehouse',
}) =>
    DocType(
      id: id,
      name: id,
      module: module,
      isChild: true,
      fields: [
        FieldDefinition(key: 'item', label: 'Item', type: FieldType.link, linkDocType: 'Item', options: 'Item', required: true),
        FieldDefinition(key: 'description', label: 'Description', type: FieldType.data),
        FieldDefinition(key: 'qty', label: 'Quantity', type: FieldType.float, required: true, defaultValue: '1'),
        FieldDefinition(key: 'uom', label: 'UOM', type: FieldType.select, options: kUomOptions, defaultValue: 'Nos'),
        FieldDefinition(key: 'rate', label: 'Rate', type: FieldType.currency, required: true),
        FieldDefinition(key: 'amount', label: 'Amount', type: FieldType.currency, readOnly: true, formulaExpression: 'qty * rate'),
        FieldDefinition(key: 'warehouse', label: warehouseLabel, type: FieldType.link, linkDocType: 'Warehouse', options: 'Warehouse'),
      ],
    );

/// A fulfilment line (Delivery Note Item / Purchase Receipt Item). Identical to
/// [lineItemDocType] today, but kept distinct so receipt/delivery-specific
/// fields can diverge without disturbing billing line tables.
DocType fulfilmentLineDocType({
  required String id,
  required String module,
  required String warehouseLabel,
}) =>
    lineItemDocType(id: id, module: module, warehouseLabel: warehouseLabel);
