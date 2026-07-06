import 'package:mercantis_core/mercantis_core.dart';

/// Online sales channels (Phase 5): generic channel entities that any
/// storefront (CSV export today, WooCommerce/Shopify polling later) feeds.
///
///  * `Sales Channel` — one storefront: where its stock issues from, whether
///    its prices already include VAT, and whether posted invoices submit
///    automatically or stay drafts for review.
///  * `Channel Product` — SKU mapping: the storefront's SKU → our Item. An
///    unmapped SKU falls back to an Item with the same id; otherwise the
///    order fails loudly instead of guessing.
///  * `Channel Order` — one imported storefront order, staged for review.
///    Posting turns it into an official Sales Invoice (with stock + COGS via
///    `update_stock`); the accounting always happens on the invoice, never
///    on this staging record.
///  * `Channel Sync Log` — one row per import / posting run, so the owner can
///    see what came in and what failed.
abstract final class ChannelsModule {
  static const _module = 'Channels';

  static List<DocType> docTypes() => [
        _salesChannel(),
        _channelProduct(),
        _channelOrder(),
        _channelOrderLine(),
        _channelSyncLog(),
      ];

  static DocType _salesChannel() => const DocType(
        id: 'Sales Channel',
        name: 'Sales Channel',
        module: _module,
        namingRule: 'CHAN-.####',
        fields: [
          FieldDefinition(key: 'channel_name', label: 'Channel Name', type: FieldType.data, required: true),
          FieldDefinition(
            key: 'channel_type',
            label: 'Type',
            type: FieldType.select,
            options: 'CSV\nWooCommerce\nShopify',
            defaultValue: 'CSV',
          ),
          // Where channel sales issue stock from; blank means orders post as
          // service-style invoices (no stock movement, no COGS).
          FieldDefinition(key: 'warehouse', label: 'Ships From Warehouse', type: FieldType.link, linkDocType: 'Warehouse', options: 'Warehouse'),
          // Storefront prices are usually consumer prices — VAT included.
          FieldDefinition(key: 'prices_include_tax', label: 'Prices Include Tax', type: FieldType.check, defaultValue: '1'),
          // Applied to imported lines that carry no tax code of their own.
          FieldDefinition(key: 'tax_code', label: 'Default Tax Code', type: FieldType.link, linkDocType: 'Tax Code', options: 'Tax Code'),
          // Fallback buyer when an order carries no usable customer details.
          FieldDefinition(key: 'default_customer', label: 'Default Customer', type: FieldType.link, linkDocType: 'Customer', options: 'Customer'),
          // Off = posted invoices stay drafts for review (the safe default);
          // on = they submit (and post stock/GL) immediately.
          FieldDefinition(key: 'auto_submit', label: 'Submit Invoices Automatically', type: FieldType.check),
          FieldDefinition(key: 'currency', label: 'Currency', type: FieldType.link, linkDocType: 'Currency', options: 'Currency'),
          FieldDefinition(key: 'disabled', label: 'Disabled', type: FieldType.check),
        ],
      );

  static DocType _channelProduct() => const DocType(
        id: 'Channel Product',
        name: 'Channel Product',
        module: _module,
        namingRule: 'CHMAP-.####',
        fields: [
          FieldDefinition(key: 'channel', label: 'Channel', type: FieldType.link, linkDocType: 'Sales Channel', options: 'Sales Channel', required: true),
          FieldDefinition(key: 'channel_sku', label: 'Channel SKU', type: FieldType.data, required: true),
          FieldDefinition(key: 'item', label: 'Item', type: FieldType.link, linkDocType: 'Item', options: 'Item', required: true),
        ],
      );

  static DocType _channelOrder() => const DocType(
        id: 'Channel Order',
        name: 'Channel Order',
        module: _module,
        fields: [
          FieldDefinition(key: 'channel', label: 'Channel', type: FieldType.link, linkDocType: 'Sales Channel', options: 'Sales Channel', required: true),
          FieldDefinition(key: 'external_order_id', label: 'Order Reference', type: FieldType.data, required: true),
          FieldDefinition(key: 'order_date', label: 'Order Date', type: FieldType.date),
          FieldDefinition(key: 'customer_name', label: 'Customer Name', type: FieldType.data),
          FieldDefinition(key: 'customer_email', label: 'Customer Email', type: FieldType.data),
          FieldDefinition(
            key: 'status',
            label: 'Status',
            type: FieldType.select,
            options: 'Imported\nPosted\nFailed\nIgnored',
            defaultValue: 'Imported',
          ),
          FieldDefinition(key: 'lines', label: 'Lines', type: FieldType.table, tableDocType: 'Channel Order Line', options: 'Channel Order Line'),
          FieldDefinition(key: 'gross_total', label: 'Order Total', type: FieldType.currency, readOnly: true),
          FieldDefinition(key: 'sales_invoice', label: 'Posted As', type: FieldType.link, linkDocType: 'Sales Invoice', options: 'Sales Invoice', readOnly: true),
          FieldDefinition(key: 'error', label: 'Last Error', type: FieldType.data, readOnly: true),
          FieldDefinition(key: 'import_batch', label: 'Import Batch', type: FieldType.data, readOnly: true),
        ],
      );

  static DocType _channelOrderLine() => const DocType(
        id: 'Channel Order Line',
        name: 'Channel Order Line',
        module: _module,
        isChild: true,
        fields: [
          FieldDefinition(key: 'sku', label: 'Channel SKU', type: FieldType.data, required: true),
          FieldDefinition(key: 'description', label: 'Description', type: FieldType.data),
          FieldDefinition(key: 'qty', label: 'Quantity', type: FieldType.float, required: true, defaultValue: '1'),
          // Not required: a promo line can legitimately cost 0.
          FieldDefinition(key: 'rate', label: 'Unit Price', type: FieldType.currency, defaultValue: '0'),
          FieldDefinition(key: 'amount', label: 'Amount', type: FieldType.currency, readOnly: true, formulaExpression: 'qty * rate'),
        ],
      );

  static DocType _channelSyncLog() => const DocType(
        id: 'Channel Sync Log',
        name: 'Channel Sync Log',
        module: _module,
        namingRule: 'CSYNC-.####',
        fields: [
          FieldDefinition(key: 'channel', label: 'Channel', type: FieldType.link, linkDocType: 'Sales Channel', options: 'Sales Channel', required: true),
          FieldDefinition(
            key: 'run_type',
            label: 'Run',
            type: FieldType.select,
            options: 'CSV Import\nPost Orders',
            required: true,
          ),
          FieldDefinition(key: 'run_on', label: 'Run At', type: FieldType.data, readOnly: true),
          FieldDefinition(key: 'imported', label: 'Imported', type: FieldType.integer, readOnly: true, defaultValue: '0'),
          FieldDefinition(key: 'duplicates', label: 'Already Imported', type: FieldType.integer, readOnly: true, defaultValue: '0'),
          FieldDefinition(key: 'skipped', label: 'Unreadable Rows', type: FieldType.integer, readOnly: true, defaultValue: '0'),
          FieldDefinition(key: 'posted', label: 'Posted', type: FieldType.integer, readOnly: true, defaultValue: '0'),
          FieldDefinition(key: 'failed', label: 'Failed', type: FieldType.integer, readOnly: true, defaultValue: '0'),
          FieldDefinition(key: 'notes', label: 'Notes', type: FieldType.smallText, readOnly: true),
        ],
      );
}
