import 'package:mercantis_core/mercantis_core.dart';

/// V2 Hospitality POS (Phase 3): the floor. Tables, the tabs open on them,
/// and menu modifiers.
///
/// A Tab is deliberately PRE-fiscal working state — it accumulates a
/// table's order while people eat, and it mutates constantly (rounds,
/// corrections, covers). Money, VAT and the sequential fiscal receipt come
/// into existence only when the tab settles into a POS Invoice on the
/// existing till spine (per-till series, session, Z). See
/// docs/MALTA_FISCAL_RECEIPTS.md for why that boundary matters.
abstract final class HospitalityModule {
  static const _module = 'Hospitality';

  static List<DocType> docTypes() => [
        _posTable(),
        _posTab(),
        _posTabItem(),
        _modifierGroup(),
        _modifierOption(),
        _kitchenTicket(),
        _kitchenTicketItem(),
      ];

  static DocType _posTable() => const DocType(
        id: 'POS Table',
        name: 'POS Table',
        module: _module,
        fields: [
          FieldDefinition(key: 'table_name', label: 'Table', type: FieldType.data, required: true),
          FieldDefinition(key: 'area', label: 'Area / Floor', type: FieldType.data),
          FieldDefinition(key: 'seats', label: 'Seats', type: FieldType.integer, defaultValue: '4'),
          FieldDefinition(key: 'enabled', label: 'Enabled', type: FieldType.check, defaultValue: '1'),
        ],
      );

  static DocType _posTab() => const DocType(
        id: 'POS Tab',
        name: 'POS Tab',
        module: _module,
        namingRule: 'TAB-.YYYY.-.####',
        fields: [
          FieldDefinition(key: 'table', label: 'Table', type: FieldType.link, linkDocType: 'POS Table', options: 'POS Table'),
          FieldDefinition(
            key: 'status',
            label: 'Status',
            type: FieldType.select,
            options: 'Open\nBilled\nVoid',
            defaultValue: 'Open',
          ),
          FieldDefinition(key: 'opened_at', label: 'Opened', type: FieldType.data, readOnly: true),
          FieldDefinition(key: 'covers', label: 'Covers', type: FieldType.integer, defaultValue: '1'),
          FieldDefinition(key: 'server', label: 'Server', type: FieldType.data),
          FieldDefinition(key: 'customer', label: 'Customer', type: FieldType.link, linkDocType: 'Customer', options: 'Customer'),
          FieldDefinition(key: 'items', label: 'Order', type: FieldType.table, tableDocType: 'POS Tab Item', options: 'POS Tab Item'),
          FieldDefinition(key: 'notes', label: 'Notes', type: FieldType.smallText),
          // Settlement stamps the fiscal document; voiding records why.
          FieldDefinition(key: 'pos_invoice', label: 'Settled As', type: FieldType.link, linkDocType: 'POS Invoice', options: 'POS Invoice', readOnly: true),
          FieldDefinition(key: 'void_reason', label: 'Void Reason', type: FieldType.data, readOnly: true),
        ],
      );

  /// One ordered line. `modifier_amount` is the PER-UNIT price delta of the
  /// chosen modifiers; settlement folds it into the invoice line's rate so
  /// the backend's amount == qty × rate invariant holds untouched.
  static DocType _posTabItem() => const DocType(
        id: 'POS Tab Item',
        name: 'POS Tab Item',
        module: _module,
        isChild: true,
        fields: [
          FieldDefinition(key: 'item', label: 'Item', type: FieldType.link, linkDocType: 'Item', options: 'Item', required: true),
          FieldDefinition(key: 'qty', label: 'Qty', type: FieldType.float, required: true, defaultValue: '1'),
          FieldDefinition(key: 'rate', label: 'Rate', type: FieldType.currency),
          FieldDefinition(key: 'modifiers', label: 'Modifiers', type: FieldType.smallText),
          FieldDefinition(key: 'modifier_amount', label: 'Modifier +/unit', type: FieldType.currency),
          FieldDefinition(key: 'notes', label: 'Kitchen Note', type: FieldType.data),
          // Kitchen-ticket state (V2-3 uses it; harmless before then).
          FieldDefinition(key: 'sent_to_kitchen', label: 'Sent', type: FieldType.check),
        ],
      );

  /// A menu item's choice set — "Cooking" (rare/medium/well), "Extras"
  /// (+cheese €0.50). Attached to Item via `modifier_group`.
  static DocType _modifierGroup() => const DocType(
        id: 'Modifier Group',
        name: 'Modifier Group',
        module: _module,
        fields: [
          FieldDefinition(key: 'group_name', label: 'Group Name', type: FieldType.data, required: true),
          FieldDefinition(key: 'options', label: 'Options', type: FieldType.table, tableDocType: 'Modifier Option', options: 'Modifier Option'),
        ],
      );

  /// V2-3: one ROUND sent to the kitchen. Each "Send to kitchen" snapshots
  /// the tab's not-yet-sent lines into a ticket, so a second round is a
  /// second ticket — the kitchen never re-reads a mutating tab. Tickets are
  /// working documents (not fiscal, not submittable): Open on the rail
  /// until the kitchen bumps them Done; voiding a tab voids its open
  /// tickets so the rail never cooks a dead order.
  static DocType _kitchenTicket() => const DocType(
        id: 'Kitchen Ticket',
        name: 'Kitchen Ticket',
        module: _module,
        namingRule: 'KOT-.YYYY.-.####',
        fields: [
          FieldDefinition(key: 'tab', label: 'Tab', type: FieldType.link, linkDocType: 'POS Tab', options: 'POS Tab', required: true),
          FieldDefinition(key: 'table', label: 'Table', type: FieldType.link, linkDocType: 'POS Table', options: 'POS Table'),
          FieldDefinition(
            key: 'status',
            label: 'Status',
            type: FieldType.select,
            options: 'Open\nDone\nVoid',
            defaultValue: 'Open',
          ),
          FieldDefinition(key: 'sent_at', label: 'Sent', type: FieldType.data, readOnly: true),
          FieldDefinition(key: 'server', label: 'Server', type: FieldType.data),
          FieldDefinition(key: 'items', label: 'Items', type: FieldType.table, tableDocType: 'Kitchen Ticket Item', options: 'Kitchen Ticket Item'),
        ],
      );

  static DocType _kitchenTicketItem() => const DocType(
        id: 'Kitchen Ticket Item',
        name: 'Kitchen Ticket Item',
        module: _module,
        isChild: true,
        fields: [
          FieldDefinition(key: 'item', label: 'Item', type: FieldType.link, linkDocType: 'Item', options: 'Item', required: true),
          FieldDefinition(key: 'qty', label: 'Qty', type: FieldType.float, required: true, defaultValue: '1'),
          FieldDefinition(key: 'modifiers', label: 'Modifiers', type: FieldType.smallText),
          FieldDefinition(key: 'notes', label: 'Kitchen Note', type: FieldType.data),
        ],
      );

  static DocType _modifierOption() => const DocType(
        id: 'Modifier Option',
        name: 'Modifier Option',
        module: _module,
        isChild: true,
        fields: [
          FieldDefinition(key: 'option_name', label: 'Option', type: FieldType.data, required: true),
          FieldDefinition(key: 'price_delta', label: 'Price +', type: FieldType.currency, defaultValue: '0'),
        ],
      );
}
