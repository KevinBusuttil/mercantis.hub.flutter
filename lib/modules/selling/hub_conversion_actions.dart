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
        DocumentAction(
          id: 'lead-to-customer',
          label: 'Create Customer',
          icon: Icons.person_add_alt,
          invoke: _leadToCustomer,
        ),
        DocumentAction(
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
        DocumentAction(
          id: 'quotation-to-sales-order',
          label: 'Create Sales Order',
          icon: Icons.shopping_cart_checkout,
          style: WorkflowActionStyle.primary,
          invoke: _quotationToSalesOrder,
        ),
      ];
    case 'Sales Order':
      return [
        DocumentAction(
          id: 'sales-order-to-delivery',
          label: 'Create Delivery Note',
          icon: Icons.local_shipping_outlined,
          invoke: _salesOrderToDelivery,
        ),
        DocumentAction(
          id: 'sales-order-to-invoice',
          label: 'Create Sales Invoice',
          icon: Icons.receipt_long_outlined,
          invoke: _salesOrderToInvoice,
        ),
      ];
    case 'Delivery Note':
      return [
        DocumentAction(
          id: 'delivery-to-invoice',
          label: 'Create Sales Invoice',
          icon: Icons.receipt_long_outlined,
          invoke: _deliveryToInvoice,
        ),
      ];
    case 'Purchase Order':
      return [
        DocumentAction(
          id: 'purchase-order-to-receipt',
          label: 'Create Purchase Receipt',
          icon: Icons.inventory_2_outlined,
          invoke: _purchaseOrderToReceipt,
        ),
        DocumentAction(
          id: 'purchase-order-to-invoice',
          label: 'Create Purchase Invoice',
          icon: Icons.receipt_long_outlined,
          invoke: _purchaseOrderToInvoice,
        ),
      ];
    case 'Purchase Receipt':
      return [
        DocumentAction(
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
  final engine = await ref.read(documentEngineProvider.future);
  await _saveAndOpen(
      context, ref, engine, HubDocumentConversion.quotationToSalesOrder(doc));
}

Future<void> _salesOrderToDelivery(
    BuildContext context, WidgetRef ref, Document doc) async {
  final engine = await ref.read(documentEngineProvider.future);
  final delivered =
      await _fulfilledByItem(engine, 'Delivery Note', 'sales_order', doc.id);
  await _saveAndOpen(
    context,
    ref,
    engine,
    HubDocumentConversion.salesOrderToDelivery(doc, deliveredByItem: delivered),
    emptyMessage: 'Every line on this order has already been delivered.',
  );
}

Future<void> _salesOrderToInvoice(
    BuildContext context, WidgetRef ref, Document doc) async {
  final engine = await ref.read(documentEngineProvider.future);
  final billed =
      await _fulfilledByItem(engine, 'Sales Invoice', 'sales_order', doc.id);
  await _saveAndOpen(
    context,
    ref,
    engine,
    HubDocumentConversion.salesOrderToInvoice(doc, billedByItem: billed),
    emptyMessage: 'Every line on this order has already been invoiced.',
  );
}

Future<void> _deliveryToInvoice(
    BuildContext context, WidgetRef ref, Document doc) async {
  final engine = await ref.read(documentEngineProvider.future);
  await _saveAndOpen(
      context, ref, engine, HubDocumentConversion.deliveryToInvoice(doc));
}

// MARK: - Buying

Future<void> _purchaseOrderToReceipt(
    BuildContext context, WidgetRef ref, Document doc) async {
  final engine = await ref.read(documentEngineProvider.future);
  final received = await _fulfilledByItem(
      engine, 'Purchase Receipt', 'purchase_order', doc.id);
  await _saveAndOpen(
    context,
    ref,
    engine,
    HubDocumentConversion.purchaseOrderToReceipt(doc,
        receivedByItem: received),
    emptyMessage: 'Every line on this order has already been received.',
  );
}

Future<void> _purchaseOrderToInvoice(
    BuildContext context, WidgetRef ref, Document doc) async {
  final engine = await ref.read(documentEngineProvider.future);
  final billed = await _fulfilledByItem(
      engine, 'Purchase Invoice', 'purchase_order', doc.id);
  await _saveAndOpen(
    context,
    ref,
    engine,
    HubDocumentConversion.purchaseOrderToInvoice(doc, billedByItem: billed),
    emptyMessage: 'Every line on this order has already been invoiced.',
  );
}

Future<void> _receiptToInvoice(
    BuildContext context, WidgetRef ref, Document doc) async {
  final engine = await ref.read(documentEngineProvider.future);
  await _saveAndOpen(
      context, ref, engine, HubDocumentConversion.receiptToInvoice(doc));
}

// MARK: - CRM

Future<void> _leadToCustomer(
    BuildContext context, WidgetRef ref, Document doc) async {
  final engine = await ref.read(documentEngineProvider.future);
  await _saveAndOpen(
      context, ref, engine, HubDocumentConversion.leadToCustomer(doc));
}

Future<void> _leadToQuotation(
    BuildContext context, WidgetRef ref, Document doc) async {
  final engine = await ref.read(documentEngineProvider.future);
  final roles = ref.read(currentUserProvider).roles;
  // Promote the lead to a Customer first (the quotation needs a customer id),
  // then open an empty quotation drafted against it.
  final customer =
      await engine.save(HubDocumentConversion.leadToCustomer(doc), roles);
  final quote = HubDocumentConversion.quotationForCustomer(
      customerId: customer.id, company: doc.company);
  await _saveAndOpen(context, ref, engine, quote);
}

// MARK: - Helpers

/// Sums fulfilled qty per item across the *submitted* downstream documents of
/// [downstreamDocType] that link back to [sourceId] via [linkField] — the
/// `deliveredByItem` / `billedByItem` map the remaining-qty converters consume.
Future<Map<String, double>> _fulfilledByItem(
  DocumentEngine engine,
  String downstreamDocType,
  String linkField,
  String sourceId,
) async {
  final docs = await engine.list(downstreamDocType, filters: {linkField: sourceId});
  final submitted = docs.where((d) => d.docStatus == 1);
  return HubDocumentConversion.fulfilledByItem(submitted);
}

/// Saves [draft] and navigates to it. For remaining-qty conversions a fully
/// fulfilled source nets to zero lines — in that case nothing is saved and
/// [emptyMessage] is shown instead.
Future<void> _saveAndOpen(
  BuildContext context,
  WidgetRef ref,
  DocumentEngine engine,
  Document draft, {
  String? emptyMessage,
}) async {
  if (emptyMessage != null && (draft.children['items']?.isEmpty ?? true)) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(emptyMessage)));
    }
    return;
  }
  final roles = ref.read(currentUserProvider).roles;
  final saved = await engine.save(draft, roles);
  if (context.mounted) context.go('/form/${saved.docType}/${saved.id}');
}
