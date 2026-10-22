import 'package:mercantis_core_ui/mercantis_core_ui.dart';

/// Owner-view business language for the documents an owner touches daily
/// (commercialisation plan §M1.2 "Business-language pass"). Engine terms stay
/// in the Accountant view; journals keep their accounting names everywhere.
/// Words only — every lifecycle step is the same engine transition.
const _posted = LifecycleLabels(
  submit: 'Post',
  submitted: 'Posted',
  cancel: 'Reverse',
  cancelled: 'Reversed',
  amend: 'Correct',
  savedMessage: 'Saved on this device',
  submittedMessage: 'Posted',
  cancelledMessage: 'Reversed — the original stays on record',
);

LifecycleLabels _words(String submit, String submittedMessage,
        {String submitted = 'Posted'}) =>
    LifecycleLabels(
      submit: submit,
      submitted: submitted,
      cancel: _posted.cancel,
      cancelled: _posted.cancelled,
      amend: _posted.amend,
      savedMessage: _posted.savedMessage,
      submittedMessage: submittedMessage,
      cancelledMessage: _posted.cancelledMessage,
    );

final _owner = <String, DocTypePresentation>{
  'Customer': const DocTypePresentation(
    label: 'Customers',
    singular: 'customer',
    emptyTitle: 'No customers yet',
    emptyMessage: 'Add the people and businesses you sell to — or import '
        'them from a spreadsheet with the menu above.',
    lifecycle: LifecycleLabels(savedMessage: 'Customer saved on this device'),
  ),
  'Supplier': const DocTypePresentation(
    label: 'Suppliers',
    singular: 'supplier',
    emptyTitle: 'No suppliers yet',
    emptyMessage: 'Add who you buy from, so bills and expenses have a home.',
    lifecycle: LifecycleLabels(savedMessage: 'Supplier saved on this device'),
  ),
  'Item': const DocTypePresentation(
    label: 'Products & services',
    singular: 'product or service',
    emptyTitle: 'Nothing to sell yet',
    emptyMessage: 'Add the services you charge for or the products you '
        'stock. Prices and VAT fill in on quotes and invoices.',
    lifecycle: LifecycleLabels(savedMessage: 'Saved on this device'),
  ),
  'Quotation': DocTypePresentation(
    label: 'Quotes',
    singular: 'quote',
    emptyTitle: 'No quotes yet',
    emptyMessage: 'Send a quote, then turn it into an invoice in one tap '
        'when the customer accepts.',
    lifecycle: _words('Finalise quote', 'Quote finalised — ready to send',
        submitted: 'Final'),
  ),
  'Sales Order': DocTypePresentation(
    label: 'Sales orders',
    singular: 'sales order',
    emptyTitle: 'No sales orders yet',
    emptyMessage: 'Confirm what a customer ordered, then deliver and invoice '
        'from it.',
    lifecycle: _words('Confirm order', 'Order confirmed',
        submitted: 'Confirmed'),
  ),
  'Sales Invoice': DocTypePresentation(
    label: 'Invoices',
    singular: 'invoice',
    emptyTitle: 'No invoices yet',
    emptyMessage: 'Create one here, or convert an accepted quote.',
    lifecycle: _words('Post invoice',
        'Invoice posted — it now counts in your books'),
  ),
  'Delivery Note': DocTypePresentation(
    label: 'Deliveries',
    singular: 'delivery',
    emptyTitle: 'No deliveries yet',
    emptyMessage: 'Deliveries take goods out of stock — create one from a '
        'sales order.',
    lifecycle: _words('Confirm delivery', 'Delivered — stock updated',
        submitted: 'Delivered'),
  ),
  'Payment Entry': DocTypePresentation(
    label: 'Payments',
    singular: 'payment',
    emptyTitle: 'No payments yet',
    emptyMessage: 'Use Receive payment or Pay supplier to record money '
        'moving and match it to invoices.',
    lifecycle: _words('Record payment', 'Payment recorded',
        submitted: 'Recorded'),
  ),
  'Purchase Invoice': DocTypePresentation(
    label: 'Supplier bills',
    singular: 'bill',
    emptyTitle: 'No supplier bills yet',
    emptyMessage: 'Record bills as they arrive — or scan the paper copy.',
    lifecycle: _words('Post bill', 'Bill posted'),
  ),
  'Purchase Order': DocTypePresentation(
    label: 'Purchase orders',
    singular: 'purchase order',
    emptyTitle: 'No purchase orders yet',
    emptyMessage: 'Order from a supplier, then receive goods and the bill '
        'against it.',
    lifecycle: _words('Place order', 'Order placed', submitted: 'Placed'),
  ),
  'Purchase Receipt': DocTypePresentation(
    label: 'Goods received',
    singular: 'goods receipt',
    emptyTitle: 'Nothing received yet',
    emptyMessage: 'Receive goods against a purchase order to add them to '
        'stock.',
    lifecycle: _words('Receive goods', 'Goods received — stock updated',
        submitted: 'Received'),
  ),
  'Expense': DocTypePresentation(
    label: 'Expenses',
    singular: 'expense',
    emptyTitle: 'No expenses yet',
    emptyMessage: 'Record a cost you paid — or scan the receipt and let '
        'Atlas fill it in for you to check.',
    lifecycle: _words('Record expense', 'Expense recorded',
        submitted: 'Recorded'),
  ),
  'Stock Entry': DocTypePresentation(
    label: 'Stock movements',
    singular: 'stock movement',
    emptyTitle: 'No stock movements yet',
    emptyMessage: 'Move stock between locations, write off damage or add '
        'opening stock.',
    lifecycle: _words('Post movement', 'Stock updated'),
  ),
  'POS Invoice': DocTypePresentation(
    label: 'Till receipts',
    singular: 'receipt',
    emptyTitle: 'No till receipts yet',
    emptyMessage: 'Sales made at the till appear here.',
    lifecycle: _words('Post receipt', 'Receipt posted'),
  ),
  'Recurring Invoice': const DocTypePresentation(
    label: 'Repeat invoices',
    singular: 'repeat invoice',
    emptyTitle: 'No repeat invoices yet',
    emptyMessage: 'Set up a retainer or subscription and Atlas drafts the '
        'invoice each period for you to check and post.',
  ),
  'Bank Account': const DocTypePresentation(
    label: 'Bank accounts',
    singular: 'bank account',
    emptyTitle: 'No bank accounts yet',
    emptyMessage: 'Add the account customers pay into, then import its '
        'statements to reconcile.',
  ),
  'Tax Filing': const DocTypePresentation(
    label: 'VAT returns',
    singular: 'VAT return',
    emptyTitle: 'No VAT returns yet',
    emptyMessage: 'Prepare a return for a period — figures come from your '
        'posted invoices and bills.',
  ),
  // Journals stay in accounting language even in the Owner view.
  'Journal Entry': const DocTypePresentation(
    lifecycle: LifecycleLabels(savedMessage: 'Saved on this device'),
  ),
  'Company': const DocTypePresentation(
    label: 'Business details',
    singular: 'business',
  ),
};

/// The Owner-view presentation for [docType]; documents without an entry get
/// the generic owner lifecycle words (Post / Posted / Reverse / Correct).
DocTypePresentation ownerPresentation(String docType) =>
    _owner[docType] ?? const DocTypePresentation(lifecycle: _posted);
