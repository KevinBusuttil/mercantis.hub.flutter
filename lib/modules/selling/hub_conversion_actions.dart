import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

import 'hub_document_conversion.dart';

/// Wires the pure [HubDocumentConversion] builders (H3) into the document detail
/// screen as one-click "Create …" command-bar actions, via the core
/// [documentActionRegistryProvider] seam.
///
/// Gating is synchronous, on the source document's own fields: master records
/// (Lead) just need to be saved; submittable sources must be Submitted
/// (docStatus 1). The work runs in each action's `invoke` — for Order →
/// Delivery/Invoice/Receipt it first totals what's already been fulfilled
/// (querying the submitted downstream documents that link back) so each line
/// defaults to the remaining balance, then saves the draft and opens it.
void registerHubConversionActions(WidgetRef ref) {
  ref.read(documentActionRegistryProvider).register(hubConversionActionsFor);
}

/// The conversion actions available for [doc] of [docType]. Pure and
/// synchronous — exposed for tests; registered via [registerHubConversionActions].
List<DocumentAction> hubConversionActionsFor(Document doc, DocType docType) {
  switch (docType.id) {
    case 'Lead':
      // A Lead is a master record (never submitted) — offer the flows once it
      // has been saved.
      if (doc.id.isEmpty) return const [];
      return [
        const DocumentAction(
          id: 'lead-to-customer',
          label: 'Create Customer',
          icon: Icons.person_add_alt,
          invoke: _leadToCustomer,
        ),
        const DocumentAction(
          id: 'lead-to-quotation',
          label: 'Create Quotation',
          icon: Icons.request_quote_outlined,
          invoke: _leadToQuotation,
        ),
      ];
  }

  // Everything else converts only from a Submitted source.
  if (doc.id.isEmpty || doc.docStatus != 1) return const [];

  switch (docType.id) {
    case 'Quotation':
      return [
        const DocumentAction(
          id: 'quotation-to-sales-order',
          label: 'Create Sales Order',
          icon: Icons.shopping_cart_checkout,
          style: WorkflowActionStyle.primary,
          invoke: _quotationToSalesOrder,
        ),
      ];
    case 'Sales Order':
      return [
        const DocumentAction(
          id: 'sales-order-to-delivery',
          label: 'Create Delivery Note',
          icon: Icons.local_shipping_outlined,
          invoke: _salesOrderToDelivery,
        ),
        const DocumentAction(
          id: 'sales-order-to-invoice',
          label: 'Create Sales Invoice',
          icon: Icons.receipt_long_outlined,
          invoke: _salesOrderToInvoice,
        ),
      ];
    case 'Delivery Note':
      return [
        const DocumentAction(
          id: 'delivery-to-invoice',
          label: 'Create Sales Invoice',
          icon: Icons.receipt_long_outlined,
          invoke: _deliveryToInvoice,
        ),
      ];
    case 'Purchase Order':
      return [
        const DocumentAction(
          id: 'purchase-order-to-receipt',
          label: 'Create Purchase Receipt',
          icon: Icons.inventory_2_outlined,
          invoke: _purchaseOrderToReceipt,
        ),
        const DocumentAction(
          id: 'purchase-order-to-invoice',
          label: 'Create Purchase Invoice',
          icon: Icons.receipt_long_outlined,
          invoke: _purchaseOrderToInvoice,
        ),
      ];
    case 'Purchase Receipt':
      return [
        const DocumentAction(
          id: 'receipt-to-invoice',
          label: 'Create Purchase Invoice',
          icon: Icons.receipt_long_outlined,
          invoke: _receiptToInvoice,
        ),
      ];
    default:
      return const [];
  }
}

// MARK: - Selling

Future<void> _quotationToSalesOrder(
    BuildContext context, WidgetRef ref, Document doc) async {
  final nav = _Nav.of(context);
  final engine = await ref.read(documentEngineProvider.future);
  await _saveAndOpen(
      nav, ref, engine, HubDocumentConversion.quotationToSalesOrder(doc));
}

Future<void> _salesOrderToDelivery(
    BuildContext context, WidgetRef ref, Document doc) async {
  final nav = _Nav.of(context);
  final engine = await ref.read(documentEngineProvider.future);
  final delivered = await fulfilledByItemFromEngine(
      engine, 'Delivery Note', 'sales_order', doc.id);
  await _saveAndOpen(
    nav,
    ref,
    engine,
    HubDocumentConversion.salesOrderToDelivery(doc, deliveredByItem: delivered),
    emptyMessage: 'Every line on this order has already been delivered.',
  );
}

Future<void> _salesOrderToInvoice(
    BuildContext context, WidgetRef ref, Document doc) async {
  final nav = _Nav.of(context);
  final engine = await ref.read(documentEngineProvider.future);
  final billed = await fulfilledByItemFromEngine(
      engine, 'Sales Invoice', 'sales_order', doc.id);
  await _saveAndOpen(
    nav,
    ref,
    engine,
    HubDocumentConversion.salesOrderToInvoice(doc, billedByItem: billed),
    emptyMessage: 'Every line on this order has already been invoiced.',
  );
}

Future<void> _deliveryToInvoice(
    BuildContext context, WidgetRef ref, Document doc) async {
  final nav = _Nav.of(context);
  final engine = await ref.read(documentEngineProvider.future);
  await _saveAndOpen(
      nav, ref, engine, HubDocumentConversion.deliveryToInvoice(doc));
}

// MARK: - Buying

Future<void> _purchaseOrderToReceipt(
    BuildContext context, WidgetRef ref, Document doc) async {
  final nav = _Nav.of(context);
  final engine = await ref.read(documentEngineProvider.future);
  final received = await fulfilledByItemFromEngine(
      engine, 'Purchase Receipt', 'purchase_order', doc.id);
  await _saveAndOpen(
    nav,
    ref,
    engine,
    HubDocumentConversion.purchaseOrderToReceipt(doc, receivedByItem: received),
    emptyMessage: 'Every line on this order has already been received.',
  );
}

Future<void> _purchaseOrderToInvoice(
    BuildContext context, WidgetRef ref, Document doc) async {
  final nav = _Nav.of(context);
  final engine = await ref.read(documentEngineProvider.future);
  final billed = await fulfilledByItemFromEngine(
      engine, 'Purchase Invoice', 'purchase_order', doc.id);
  await _saveAndOpen(
    nav,
    ref,
    engine,
    HubDocumentConversion.purchaseOrderToInvoice(doc, billedByItem: billed),
    emptyMessage: 'Every line on this order has already been invoiced.',
  );
}

Future<void> _receiptToInvoice(
    BuildContext context, WidgetRef ref, Document doc) async {
  final nav = _Nav.of(context);
  final engine = await ref.read(documentEngineProvider.future);
  await _saveAndOpen(
      nav, ref, engine, HubDocumentConversion.receiptToInvoice(doc));
}

// MARK: - CRM

Future<void> _leadToCustomer(
    BuildContext context, WidgetRef ref, Document doc) async {
  final nav = _Nav.of(context);
  final engine = await ref.read(documentEngineProvider.future);
  await _saveAndOpen(
      nav, ref, engine, HubDocumentConversion.leadToCustomer(doc));
}

Future<void> _leadToQuotation(
    BuildContext context, WidgetRef ref, Document doc) async {
  final nav = _Nav.of(context);
  final engine = await ref.read(documentEngineProvider.future);
  final roles = ref.read(currentUserProvider).roles;
  // Promote the lead to a Customer first (the quotation needs a customer id),
  // then open an empty quotation drafted against it.
  final customer =
      await engine.save(HubDocumentConversion.leadToCustomer(doc), roles);
  final quote = HubDocumentConversion.quotationForCustomer(
      customerId: customer.id, company: doc.company);
  await _saveAndOpen(nav, ref, engine, quote);
}

// MARK: - Helpers

/// Router + messenger captured from the source document's [BuildContext] *before*
/// any await, so the post-save navigation never touches a [BuildContext] across
/// an async gap (both handles stay valid even as the form is torn down by the
/// navigation they trigger).
class _Nav {
  const _Nav(this.router, this.messenger);
  final GoRouter router;
  final ScaffoldMessengerState messenger;

  factory _Nav.of(BuildContext context) =>
      _Nav(GoRouter.of(context), ScaffoldMessenger.of(context));
}

/// Sums fulfilled qty per item across the *submitted* downstream documents of
/// [downstreamDocType] that link back to [sourceId] via [linkField] — the
/// `deliveredByItem` / `billedByItem` map the remaining-qty converters consume.
///
/// Each match is re-fetched by id because `DocumentEngine.list` hydrates only
/// the parent payload, not `document_children`; only `fetch` loads child rows,
/// and [HubDocumentConversion.fulfilledByItem] sums `children['items']`. Listing
/// alone would total nothing, so every repeat conversion would re-propose the
/// full original quantities and risk duplicate drafts.
///
/// Visible for testing.
Future<Map<String, double>> fulfilledByItemFromEngine(
  DocumentEngine engine,
  String downstreamDocType,
  String linkField,
  String sourceId,
) async {
  final matches =
      await engine.list(downstreamDocType, filters: {linkField: sourceId});
  final hydrated = <Document>[];
  for (final match in matches) {
    if (match.docStatus != 1) continue; // only submitted documents count
    final full = await engine.fetch(downstreamDocType, match.id);
    if (full != null) hydrated.add(full);
  }
  return HubDocumentConversion.fulfilledByItem(hydrated);
}

/// Saves [draft] and opens it. For remaining-qty conversions a fully fulfilled
/// source nets to zero lines — in that case nothing is saved and [emptyMessage]
/// is shown instead.
Future<void> _saveAndOpen(
  _Nav nav,
  WidgetRef ref,
  DocumentEngine engine,
  Document draft, {
  String? emptyMessage,
}) async {
  if (emptyMessage != null && (draft.children['items']?.isEmpty ?? true)) {
    nav.messenger.showSnackBar(SnackBar(content: Text(emptyMessage)));
    return;
  }
  final roles = ref.read(currentUserProvider).roles;
  final saved = await engine.save(draft, roles);
  nav.router.go('/form/${saved.docType}/${saved.id}');
}
