import 'package:mercantis_core/mercantis_core.dart';

import '../common/line_items.dart';

/// Operational DocTypes used by the Sales & Fulfilment and Purchasing
/// & Receiving workspaces but not part of the original module set.
abstract final class FulfilmentModule {
  static const _selling = 'Selling';
  static const _buying = 'Buying';

  static List<DocType> docTypes() => [
        _deliveryNote(),
        _purchaseReceipt(),
        // Line-item child tables (drive stock movements in Phase 3).
        fulfilmentLineDocType(id: 'Delivery Note Item', module: _selling, warehouseLabel: 'Source Warehouse'),
        fulfilmentLineDocType(id: 'Purchase Receipt Item', module: _buying, warehouseLabel: 'Target Warehouse'),
      ];

  static DocType _deliveryNote() => const DocType(
        id: 'Delivery Note',
        name: 'Delivery Note',
        module: _selling,
        isSubmittable: true,
        namingRule: 'DN-.YYYY.-.####',
        // Delivery journey workflow (Draft → Scheduled → Loaded → Out for
        // Delivery → Delivered/Failed). Mirrors the Swift wf-sales-delivery.
        workflowId: 'wf-sales-delivery',
        fields: [
          // Allocated by the Team posting authority at official submit —
          // gap-free per company, the document's real-world number on
          // screens and PDFs. Blank in Solo (the local id serves there).
          FieldDefinition(key: 'official_number', label: 'Official Number', type: FieldType.data, readOnly: true, allowOnSubmit: true),
          FieldDefinition(key: 'customer', label: 'Customer',
            type: FieldType.link, linkDocType: 'Customer',
            options: 'Customer', required: true),
          FieldDefinition(key: 'posting_date', label: 'Posting Date',
            type: FieldType.date, required: true),
          FieldDefinition(key: 'sales_order', label: 'Sales Order',
            type: FieldType.link, linkDocType: 'Sales Order',
            options: 'Sales Order'),
          FieldDefinition(key: 'set_warehouse', label: 'From Warehouse',
            type: FieldType.link, linkDocType: 'Warehouse',
            options: 'Warehouse'),
          // Returns (H6): a sales return is a Delivery Note with is_return set
          // and negative line quantities; the stock derivation adds the goods
          // back, valued at the original delivery's cost (return_against).
          FieldDefinition(key: 'is_return', label: 'Is Return',
            type: FieldType.check),
          FieldDefinition(key: 'return_against', label: 'Return Against',
            type: FieldType.link, linkDocType: 'Delivery Note',
            options: 'Delivery Note'),
          FieldDefinition(key: 'items', label: 'Items',
            type: FieldType.table, tableDocType: 'Delivery Note Item',
            options: 'Delivery Note Item'),
          FieldDefinition(key: 'transporter', label: 'Transporter',
            type: FieldType.data),
          FieldDefinition(key: 'vehicle_no', label: 'Vehicle No.',
            type: FieldType.data),
          FieldDefinition(key: 'driver', label: 'Driver',
            type: FieldType.data),
          // Set by the DeliveryRouteService when this note is added to a route;
          // route_status mirrors the stop's status. Editable after submit.
          FieldDefinition(key: 'delivery_route', label: 'Delivery Route',
            type: FieldType.link, linkDocType: 'Delivery Route',
            options: 'Delivery Route', readOnly: true, allowOnSubmit: true),
          FieldDefinition(key: 'route_status', label: 'Route Status',
            type: FieldType.data, readOnly: true, allowOnSubmit: true),
          FieldDefinition(key: 'remarks', label: 'Remarks',
            type: FieldType.longText),
        ],
      );

  static DocType _purchaseReceipt() => const DocType(
        id: 'Purchase Receipt',
        name: 'Purchase Receipt',
        module: _buying,
        isSubmittable: true,
        namingRule: 'PR-.YYYY.-.####',
        workflowId: 'wf-purchase-receipt',
        fields: [
          // Allocated by the Team posting authority at official submit —
          // gap-free per company, the document's real-world number on
          // screens and PDFs. Blank in Solo (the local id serves there).
          FieldDefinition(key: 'official_number', label: 'Official Number', type: FieldType.data, readOnly: true, allowOnSubmit: true),
          FieldDefinition(key: 'supplier', label: 'Supplier',
            type: FieldType.link, linkDocType: 'Supplier',
            options: 'Supplier', required: true),
          FieldDefinition(key: 'posting_date', label: 'Posting Date',
            type: FieldType.date, required: true),
          FieldDefinition(key: 'purchase_order', label: 'Purchase Order',
            type: FieldType.link, linkDocType: 'Purchase Order',
            options: 'Purchase Order'),
          FieldDefinition(key: 'set_warehouse', label: 'To Warehouse',
            type: FieldType.link, linkDocType: 'Warehouse',
            options: 'Warehouse'),
          // Returns (H6): a purchase return is a Purchase Receipt with is_return
          // set and negative line quantities; the stock derivation removes the
          // goods (costed at the current valuation).
          FieldDefinition(key: 'is_return', label: 'Is Return',
            type: FieldType.check),
          FieldDefinition(key: 'return_against', label: 'Return Against',
            type: FieldType.link, linkDocType: 'Purchase Receipt',
            options: 'Purchase Receipt'),
          FieldDefinition(key: 'items', label: 'Items',
            type: FieldType.table, tableDocType: 'Purchase Receipt Item',
            options: 'Purchase Receipt Item'),
          FieldDefinition(key: 'supplier_delivery_note',
            label: 'Supplier Delivery Note', type: FieldType.data),
          FieldDefinition(key: 'remarks', label: 'Remarks',
            type: FieldType.longText),
        ],
      );
}
