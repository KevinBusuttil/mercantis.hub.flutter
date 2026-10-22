import 'package:mercantis_core/mercantis_core.dart';

/// One column of a take-on CSV template.
class TakeOnColumn {
  const TakeOnColumn(this.key, this.label, this.help,
      {this.required = false, this.aliases = const []});

  /// Canonical key the importer reads.
  final String key;
  final String label;
  final String help;
  final bool required;

  /// Other header spellings matched automatically when mapping columns
  /// (compared case- and punctuation-insensitively).
  final List<String> aliases;
}

/// The sections of an opening-data migration, in the order they are imported
/// (masters before the balances that reference them).
enum TakeOnSection {
  customers,
  suppliers,
  warehouses,
  items,
  openingStock,
  receivables,
  payables,
  trialBalance,
  bankBalances,
}

/// A downloadable template and the rules for one section.
class TakeOnTemplate {
  const TakeOnTemplate({
    required this.section,
    required this.title,
    required this.fileName,
    required this.purpose,
    required this.columns,
    required this.example,
    this.posts = false,
  });

  final TakeOnSection section;
  final String title;
  final String fileName;
  final String purpose;
  final List<TakeOnColumn> columns;
  final List<Map<String, String>> example;

  /// True when importing this section writes accounting entries. Such a
  /// section is imported all-or-nothing: one rejected row blocks it, because
  /// a partial opening position cannot reconcile.
  final bool posts;

  /// The template as CSV: header plus example rows to overwrite.
  String csv() => CsvCodec.encode(
        headers: [for (final c in columns) c.key],
        rows: example,
      );

  static TakeOnTemplate of(TakeOnSection s) =>
      all.firstWhere((t) => t.section == s);

  static const all = <TakeOnTemplate>[
    TakeOnTemplate(
      section: TakeOnSection.customers,
      title: 'Customers',
      fileName: 'atlas-takeon-1-customers.csv',
      purpose: 'Everyone you sell to. The code is how later files (open '
          'invoices) refer to the customer, and how a re-import recognises '
          'records it already created.',
      columns: [
        TakeOnColumn('customer_code', 'Customer code',
            'Your unique code for the customer (kept as the Atlas id).',
            required: true, aliases: ['code', 'customer id', 'account']),
        TakeOnColumn('customer_name', 'Name', 'Customer name.',
            required: true, aliases: ['name', 'customer']),
        TakeOnColumn('customer_type', 'Type', 'Company or Individual.'),
        TakeOnColumn('email', 'Email', 'Billing email.'),
        TakeOnColumn('tax_id', 'VAT / tax number', 'Customer VAT number.',
            aliases: ['vat number', 'vat no', 'tax number']),
        TakeOnColumn('country', 'Country', 'Country.'),
      ],
      example: [
        {
          'customer_code': 'C001',
          'customer_name': 'Blue Fig Café',
          'customer_type': 'Company',
          'email': 'accounts@bluefig.example',
          'tax_id': 'MT12345678',
          'country': 'Malta',
        },
      ],
    ),
    TakeOnTemplate(
      section: TakeOnSection.suppliers,
      title: 'Suppliers',
      fileName: 'atlas-takeon-2-suppliers.csv',
      purpose: 'Everyone you buy from. The code links open bills to the '
          'supplier.',
      columns: [
        TakeOnColumn('supplier_code', 'Supplier code',
            'Your unique code for the supplier (kept as the Atlas id).',
            required: true, aliases: ['code', 'supplier id', 'account']),
        TakeOnColumn('supplier_name', 'Name', 'Supplier name.',
            required: true, aliases: ['name', 'supplier']),
        TakeOnColumn('supplier_type', 'Type', 'Company or Individual.'),
        TakeOnColumn('tax_id', 'VAT / tax number', 'Supplier VAT number.',
            aliases: ['vat number', 'vat no', 'tax number']),
        TakeOnColumn('country', 'Country', 'Country.'),
      ],
      example: [
        {
          'supplier_code': 'S001',
          'supplier_name': 'Apex Supplies Ltd',
          'supplier_type': 'Company',
          'tax_id': 'MT87654321',
          'country': 'Malta',
        },
      ],
    ),
    TakeOnTemplate(
      section: TakeOnSection.warehouses,
      title: 'Warehouses',
      fileName: 'atlas-takeon-3-warehouses.csv',
      purpose: 'Places stock is kept (a shop, a store room, a van).',
      columns: [
        TakeOnColumn('warehouse_code', 'Warehouse code',
            'Unique code (kept as the Atlas id).',
            required: true, aliases: ['code', 'location code']),
        TakeOnColumn('warehouse_name', 'Name', 'Warehouse name.',
            required: true, aliases: ['name', 'location']),
      ],
      example: [
        {'warehouse_code': 'MAIN', 'warehouse_name': 'Main store'},
      ],
    ),
    TakeOnTemplate(
      section: TakeOnSection.items,
      title: 'Items and services',
      fileName: 'atlas-takeon-4-items.csv',
      purpose: 'What you sell and buy, with its unit and prices. Prices are '
          'optional; a blank price stays blank.',
      columns: [
        TakeOnColumn('item_code', 'Item code', 'Unique code / SKU.',
            required: true, aliases: ['code', 'sku', 'product code']),
        TakeOnColumn('item_name', 'Name', 'Item name.',
            required: true, aliases: ['name', 'description', 'product']),
        TakeOnColumn('item_type', 'Type',
            'Stock (counted on hand) or Service (not counted).',
            required: true, aliases: ['type']),
        TakeOnColumn('uom', 'Unit', 'Unit of measure, e.g. Nos, Kg, Box, Hour.',
            required: true, aliases: ['unit', 'stock uom', 'uom']),
        TakeOnColumn('selling_price', 'Selling price',
            'Standard selling price, excluding VAT (2 decimals).',
            aliases: ['price', 'sale price', 'standard rate']),
        TakeOnColumn('buying_price', 'Buying price',
            'Standard buying price, excluding VAT (2 decimals).',
            aliases: ['cost', 'purchase price']),
        TakeOnColumn('valuation_method', 'Valuation method',
            'Moving Average (default) or FIFO. Stock items only.'),
      ],
      example: [
        {
          'item_code': 'WIDGET-1',
          'item_name': 'Widget',
          'item_type': 'Stock',
          'uom': 'Nos',
          'selling_price': '12.00',
          'buying_price': '5.00',
          'valuation_method': 'Moving Average',
        },
        {
          'item_code': 'CONSULT',
          'item_name': 'Consulting hour',
          'item_type': 'Service',
          'uom': 'Hour',
          'selling_price': '60.00',
        },
      ],
    ),
    TakeOnTemplate(
      section: TakeOnSection.openingStock,
      title: 'Opening stock',
      fileName: 'atlas-takeon-5-opening-stock.csv',
      purpose: 'Quantity and total value on hand per item and warehouse at '
          'the opening date, as your stock valuation report shows it. Atlas '
          'derives the unit cost as value ÷ quantity; it never guesses a '
          'value.',
      posts: true,
      columns: [
        TakeOnColumn('item_code', 'Item code', 'Must be a Stock item.',
            required: true, aliases: ['code', 'sku']),
        TakeOnColumn('warehouse_code', 'Warehouse code', 'Where it is.',
            required: true, aliases: ['warehouse', 'location']),
        TakeOnColumn('qty', 'Quantity', 'On hand, in the item unit (> 0).',
            required: true, aliases: ['quantity', 'on hand']),
        TakeOnColumn('value', 'Total value',
            'Total cost value of that quantity (2 decimals).',
            required: true, aliases: ['stock value', 'amount', 'total']),
      ],
      example: [
        {
          'item_code': 'WIDGET-1',
          'warehouse_code': 'MAIN',
          'qty': '40',
          'value': '200.00',
        },
      ],
    ),
    TakeOnTemplate(
      section: TakeOnSection.receivables,
      title: 'Open customer invoices',
      fileName: 'atlas-takeon-6-open-receivables.csv',
      purpose: 'Every unpaid or part-paid customer invoice at the opening '
          'date, with the amount still owed (VAT included). Each becomes an '
          'opening invoice you can receive payment against.',
      posts: true,
      columns: [
        TakeOnColumn('invoice_no', 'Invoice number',
            'The invoice number in your old system (unique).',
            required: true, aliases: ['invoice', 'document no', 'ref']),
        TakeOnColumn('customer_code', 'Customer code',
            'Must exist (customers file or already in Atlas).',
            required: true, aliases: ['customer', 'account']),
        TakeOnColumn('invoice_date', 'Invoice date', 'YYYY-MM-DD.',
            required: true, aliases: ['date']),
        TakeOnColumn('due_date', 'Due date', 'YYYY-MM-DD (optional).'),
        TakeOnColumn('outstanding', 'Amount outstanding',
            'Still owed, VAT included, 2 decimals, greater than zero.',
            required: true,
            aliases: ['outstanding amount', 'balance', 'amount due', 'open amount']),
      ],
      example: [
        {
          'invoice_no': 'INV-1042',
          'customer_code': 'C001',
          'invoice_date': '2026-09-15',
          'due_date': '2026-10-15',
          'outstanding': '590.00',
        },
      ],
    ),
    TakeOnTemplate(
      section: TakeOnSection.payables,
      title: 'Open supplier bills',
      fileName: 'atlas-takeon-7-open-payables.csv',
      purpose: 'Every unpaid or part-paid supplier bill at the opening date, '
          'with the amount still owed (VAT included).',
      posts: true,
      columns: [
        TakeOnColumn('bill_no', 'Bill number',
            "The supplier's invoice number (unique per supplier).",
            required: true, aliases: ['bill', 'invoice no', 'supplier invoice', 'ref']),
        TakeOnColumn('supplier_code', 'Supplier code', 'Must exist.',
            required: true, aliases: ['supplier', 'account']),
        TakeOnColumn('bill_date', 'Bill date', 'YYYY-MM-DD.',
            required: true, aliases: ['date', 'invoice date']),
        TakeOnColumn('due_date', 'Due date', 'YYYY-MM-DD (optional).'),
        TakeOnColumn('outstanding', 'Amount outstanding',
            'Still owed, VAT included, 2 decimals, greater than zero.',
            required: true,
            aliases: ['outstanding amount', 'balance', 'amount due', 'open amount']),
      ],
      example: [
        {
          'bill_no': 'AP-5531',
          'supplier_code': 'S001',
          'bill_date': '2026-09-28',
          'due_date': '2026-10-28',
          'outstanding': '236.00',
        },
      ],
    ),
    TakeOnTemplate(
      section: TakeOnSection.trialBalance,
      title: 'Trial balance',
      fileName: 'atlas-takeon-8-trial-balance.csv',
      purpose: 'Your old system\'s trial balance at the opening date, every '
          'account. Atlas posts it as one opening journal, EXCEPT the '
          'receivable, payable and stock control accounts: those come from '
          'the open invoices, bills and opening stock files, and Atlas checks '
          'they add up to these lines.',
      posts: true,
      columns: [
        TakeOnColumn('account', 'Account',
            'Atlas account name or id (create missing accounts first).',
            required: true, aliases: ['account name', 'gl account', 'ledger']),
        TakeOnColumn('debit', 'Debit', 'Debit balance, 2 decimals.',
            aliases: ['dr']),
        TakeOnColumn('credit', 'Credit', 'Credit balance, 2 decimals.',
            aliases: ['cr']),
      ],
      example: [
        {'account': 'Bank', 'debit': '12500.00', 'credit': ''},
        {'account': 'Debtors', 'debit': '590.00', 'credit': ''},
        {'account': 'Stock', 'debit': '200.00', 'credit': ''},
        {'account': 'Creditors', 'debit': '', 'credit': '236.00'},
        {'account': 'VAT', 'debit': '', 'credit': '410.00'},
        {'account': 'Retained Earnings', 'debit': '', 'credit': '12644.00'},
      ],
    ),
    TakeOnTemplate(
      section: TakeOnSection.bankBalances,
      title: 'Bank and cash balances',
      fileName: 'atlas-takeon-9-bank-balances.csv',
      purpose: 'The balance on each bank statement and cash count at the '
          'opening date. Nothing is posted from this file: it is the '
          'independent figure the reconciliation checks the trial balance '
          'against.',
      columns: [
        TakeOnColumn('account', 'Account', 'The Atlas bank or cash account.',
            required: true, aliases: ['bank account', 'account name']),
        TakeOnColumn('statement_balance', 'Statement balance',
            'Balance per statement or count, 2 decimals (overdrawn: -).',
            required: true, aliases: ['balance', 'closing balance']),
      ],
      example: [
        {'account': 'Bank', 'statement_balance': '12500.00'},
      ],
    ),
  ];
}
