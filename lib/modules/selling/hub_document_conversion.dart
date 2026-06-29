import 'package:mercantis_core/mercantis_core.dart';

/// Builds a draft of a downstream document from an upstream one, so an operator
/// can convert a Quotation → Sales Order, an order into a Delivery or Invoice,
/// invoice a delivery, and the buy-side equivalents — in one click rather than
/// re-keying the lines. Each result is an ordinary Draft (docStatus 0,
/// `workflow_state: Draft`); the caller applies Business-Profile defaults and
/// saves it, and the normal tax / submit flow takes over.
///
/// Order → Delivery / Invoice conversions default each line to the **remaining**
/// (un-fulfilled) quantity, given the qty already delivered / billed against the
/// order (passed in by the caller, which has the engine to total it). A line
/// with nothing left is dropped, so re-converting a partially-fulfilled order
/// proposes only the balance.
///
/// Pure: no engine, no I/O — every method maps a [Document] to a draft
/// [Document]. Port of Swift `HubDocumentConversion`.
class HubDocumentConversion {
  const HubDocumentConversion._();

  // MARK: - Selling

  /// Quotation → Sales Order draft. Header (customer / currency / tax / default
  /// warehouse / delivery date) and the full item lines carry over; the order
  /// links back to the originating quotation.
  static Document quotationToSalesOrder(Document quote) {
    final fields = <String, dynamic>{
      'transaction_date': _today(),
      'quotation': quote.id,
    };
    _copy(const [
      'customer', 'currency', 'conversion_rate', 'price_list', 'tax_code',
      'set_warehouse', 'delivery_date',
    ], quote.payload, fields);
    final items = _carryAll(
      quote,
      const ['item', 'description', 'qty', 'uom', 'rate', 'tax_code', 'warehouse', 'delivery_date'],
      'Sales Order',
    );
    return _draft(docType: 'Sales Order', company: quote.company, fields: fields, items: items);
  }

  /// Sales Order → Delivery Note draft. Each line defaults to the qty still to
  /// deliver (ordered − already delivered); fully-delivered lines are dropped.
  static Document salesOrderToDelivery(Document order,
      {Map<String, double> deliveredByItem = const {}}) {
    final fields = <String, dynamic>{
      'posting_date': _today(),
      'sales_order': order.id,
    };
    _copy(const ['customer', 'currency', 'conversion_rate'], order.payload, fields);
    final warehouse = order.payload['set_warehouse'] ?? order.payload['warehouse'];
    if (warehouse != null) fields['set_warehouse'] = warehouse;
    final items = remainingLines(
      order.children['items'] ?? const [],
      fulfilledByItem: deliveredByItem,
      carryKeys: const ['item', 'description', 'uom', 'rate', 'warehouse'],
      targetDocType: 'Delivery Note',
      backLink: (key: 'sales_order', value: order.id),
    );
    return _draft(docType: 'Delivery Note', company: order.company, fields: fields, items: items);
  }

  /// Sales Order → Sales Invoice draft. Each line defaults to the qty still to
  /// bill (ordered − already billed); fully-billed lines are dropped.
  static Document salesOrderToInvoice(Document order,
      {Map<String, double> billedByItem = const {}}) {
    final fields = <String, dynamic>{
      'posting_date': _today(),
      'sales_order': order.id,
    };
    _copy(const ['customer', 'currency', 'conversion_rate', 'price_list', 'tax_code'],
        order.payload, fields);
    final items = remainingLines(
      order.children['items'] ?? const [],
      fulfilledByItem: billedByItem,
      carryKeys: const ['item', 'description', 'uom', 'rate', 'tax_code', 'warehouse'],
      targetDocType: 'Sales Invoice',
    );
    return _draft(docType: 'Sales Invoice', company: order.company, fields: fields, items: items);
  }

  /// Delivery Note → Sales Invoice draft (deliver-then-invoice). Bills the goods
  /// that physically shipped: the delivery's lines carry over verbatim, and the
  /// order link threads through when the delivery itself came from an order.
  static Document deliveryToInvoice(Document delivery) {
    final fields = <String, dynamic>{
      'posting_date': _today(),
      'delivery_note': delivery.id,
    };
    _copy(const ['customer', 'currency', 'conversion_rate'], delivery.payload, fields);
    if (delivery.payload['sales_order'] != null) {
      fields['sales_order'] = delivery.payload['sales_order'];
    }
    final items = _carryAll(
      delivery,
      const ['item', 'description', 'qty', 'uom', 'rate', 'warehouse'],
      'Sales Invoice',
    );
    return _draft(docType: 'Sales Invoice', company: delivery.company, fields: fields, items: items);
  }

  // MARK: - Buying

  /// Purchase Order → Purchase Receipt draft. Each line defaults to the qty
  /// still to receive (ordered − already received); fully-received lines drop.
  static Document purchaseOrderToReceipt(Document order,
      {Map<String, double> receivedByItem = const {}}) {
    final fields = <String, dynamic>{
      'posting_date': _today(),
      'purchase_order': order.id,
    };
    _copy(const ['supplier', 'currency', 'conversion_rate'], order.payload, fields);
    final warehouse = order.payload['set_warehouse'] ?? order.payload['warehouse'];
    if (warehouse != null) fields['set_warehouse'] = warehouse;
    final items = remainingLines(
      order.children['items'] ?? const [],
      fulfilledByItem: receivedByItem,
      carryKeys: const ['item', 'description', 'uom', 'rate', 'warehouse'],
      targetDocType: 'Purchase Receipt',
      backLink: (key: 'purchase_order', value: order.id),
    );
    return _draft(docType: 'Purchase Receipt', company: order.company, fields: fields, items: items);
  }

  /// Purchase Order → Purchase Invoice draft. Each line defaults to the qty
  /// still to bill (ordered − already billed); fully-billed lines drop.
  static Document purchaseOrderToInvoice(Document order,
      {Map<String, double> billedByItem = const {}}) {
    final fields = <String, dynamic>{
      'posting_date': _today(),
      'purchase_order': order.id,
    };
    _copy(const ['supplier', 'currency', 'conversion_rate', 'price_list', 'tax_code'],
        order.payload, fields);
    final items = remainingLines(
      order.children['items'] ?? const [],
      fulfilledByItem: billedByItem,
      carryKeys: const ['item', 'description', 'uom', 'rate', 'tax_code', 'warehouse'],
      targetDocType: 'Purchase Invoice',
    );
    return _draft(docType: 'Purchase Invoice', company: order.company, fields: fields, items: items);
  }

  /// Purchase Receipt → Purchase Invoice draft (receive-then-bill). Bills the
  /// goods physically received; the order link threads through when the receipt
  /// came from an order.
  static Document receiptToInvoice(Document receipt) {
    final fields = <String, dynamic>{
      'posting_date': _today(),
      'purchase_receipt': receipt.id,
    };
    _copy(const ['supplier', 'currency', 'conversion_rate'], receipt.payload, fields);
    if (receipt.payload['purchase_order'] != null) {
      fields['purchase_order'] = receipt.payload['purchase_order'];
    }
    final items = _carryAll(
      receipt,
      const ['item', 'description', 'qty', 'uom', 'rate', 'warehouse'],
      'Purchase Invoice',
    );
    return _draft(docType: 'Purchase Invoice', company: receipt.company, fields: fields, items: items);
  }

  // MARK: - CRM

  /// Lead → Customer draft. A lead with a company becomes a Company customer
  /// named after `company_name`, otherwise an Individual named after the
  /// lead's first/last name. Customer has its own naming series, so the engine
  /// assigns the id on save.
  static Document leadToCustomer(Document lead) {
    final companyName = _string(lead.payload['company_name']);
    final personName = [
      _string(lead.payload['first_name']) ?? '',
      _string(lead.payload['last_name']) ?? '',
    ].where((s) => s.isNotEmpty).join(' ').trim();
    final fields = <String, dynamic>{
      'customer_type': companyName != null ? 'Company' : 'Individual',
      'customer_name': companyName ??
          (personName.isNotEmpty ? personName : 'New Customer'),
    };
    if (lead.payload['territory'] != null) fields['territory'] = lead.payload['territory'];
    return _bareDraft(docType: 'Customer', company: lead.company, fields: fields);
  }

  /// An empty Draft Quotation for a Customer — the destination of the one-click
  /// Lead → Quotation flow. The operator adds line items; currency / tax
  /// defaults are filled by the Business Profile when the caller saves it.
  static Document quotationForCustomer({
    required String customerId,
    String? opportunityId,
    required String? company,
  }) {
    final fields = <String, dynamic>{
      'customer': customerId,
      'transaction_date': _today(),
    };
    if (opportunityId != null && opportunityId.isNotEmpty) {
      fields['opportunity'] = opportunityId;
    }
    return _draft(docType: 'Quotation', company: company, fields: fields, items: const []);
  }

  // MARK: - Helpers

  /// Totals fulfilled quantity per item across a set of downstream documents
  /// (e.g. the submitted Delivery Notes / Invoices that link back to an order).
  /// The caller fetches those documents from the engine; this folds their item
  /// lines into the `{item: qty}` map that the Order → Delivery/Invoice
  /// converters consume as `deliveredByItem` / `billedByItem`.
  static Map<String, double> fulfilledByItem(Iterable<Document> downstream) {
    final totals = <String, double>{};
    for (final document in downstream) {
      for (final row in document.children['items'] ?? const <ChildRow>[]) {
        final itemId = _string(row.payload['item']);
        if (itemId == null) continue;
        totals[itemId] = (totals[itemId] ?? 0) + (_double(row.payload['qty']) ?? 0);
      }
    }
    return totals;
  }

  /// Carry source lines into a downstream table, defaulting each line's qty to
  /// the amount still un-fulfilled (ordered − already fulfilled for that item).
  /// [fulfilledByItem] is consumed greedily across lines of the same item, and a
  /// line with nothing left is dropped. When [backLink] is given (delivery /
  /// receipt lines), each surviving line gets it set to the source id.
  static List<ChildRow> remainingLines(
    List<ChildRow> rows, {
    required Map<String, double> fulfilledByItem,
    required List<String> carryKeys,
    required String targetDocType,
    ({String key, String value})? backLink,
  }) {
    final pool = Map<String, double>.from(fulfilledByItem);
    final result = <ChildRow>[];
    for (final row in rows) {
      final orderedQty = _double(row.payload['qty']) ?? 0;
      var remaining = orderedQty;
      final itemId = _string(row.payload['item']);
      if (itemId != null) {
        final already = pool[itemId] ?? 0;
        if (already > 0) {
          final netted = already < orderedQty ? already : orderedQty;
          remaining = orderedQty - netted;
          pool[itemId] = already - netted;
        }
      }
      if (remaining <= 0.0000001) continue;
      final lineFields = <String, dynamic>{};
      if (backLink != null) lineFields[backLink.key] = backLink.value;
      _copy(carryKeys, row.payload, lineFields);
      lineFields['qty'] = remaining;
      result.add(_row(targetDocType, result.length, lineFields));
    }
    return result;
  }

  /// Carry every source line verbatim (the keys in [carryKeys]) into a new table
  /// for [targetDocType].
  static List<ChildRow> _carryAll(
      Document source, List<String> carryKeys, String targetDocType) {
    final rows = source.children['items'] ?? const <ChildRow>[];
    final result = <ChildRow>[];
    for (final row in rows) {
      final lineFields = <String, dynamic>{};
      _copy(carryKeys, row.payload, lineFields);
      result.add(_row(targetDocType, result.length, lineFields));
    }
    return result;
  }

  static ChildRow _row(String parentDocType, int index, Map<String, dynamic> fields) =>
      ChildRow(
        id: '',
        parentId: '',
        parentDocType: parentDocType,
        tableName: 'items',
        rowIndex: index,
        payload: fields,
      );

  /// Copies [keys] from [source] into [target], but only where [target] has no
  /// value yet and [source] has a non-null one (so explicit header fields win).
  static void _copy(
      List<String> keys, Map<String, dynamic> source, Map<String, dynamic> target) {
    for (final key in keys) {
      if (target[key] != null) continue;
      final value = source[key];
      if (value != null) target[key] = value;
    }
  }

  static String? _string(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static double? _double(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value.trim());
    return null;
  }

  /// Today as a `yyyy-MM-dd` string — the format the date field editors store.
  static String _today() {
    final now = DateTime.now();
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    return '${now.year.toString().padLeft(4, '0')}-$m-$d';
  }

  /// A submittable-document draft: starts in the workflow's initial `Draft`
  /// state so the Submit transition (whose `from` is Draft) is available.
  static Document _draft({
    required String docType,
    required String? company,
    required Map<String, dynamic> fields,
    required List<ChildRow> items,
  }) {
    final payload = <String, dynamic>{'workflow_state': 'Draft', ...fields};
    return Document(
      id: '',
      docType: docType,
      company: company,
      docStatus: 0,
      payload: payload,
      children: {'items': items},
    );
  }

  /// A master-record draft (no items, no workflow state) — used for Lead →
  /// Customer.
  static Document _bareDraft({
    required String docType,
    required String? company,
    required Map<String, dynamic> fields,
  }) =>
      Document(
        id: '',
        docType: docType,
        company: company,
        docStatus: 0,
        payload: Map<String, dynamic>.from(fields),
      );
}
