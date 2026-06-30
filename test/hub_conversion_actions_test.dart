import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';
import 'package:mercantis_hub_app/modules/selling/hub_conversion_actions.dart';

/// H3 — which one-click conversion actions surface on which source document.
/// Pure gating (no engine / UI); the conversions themselves are covered by
/// hub_document_conversion_test.dart.
void main() {
  DocType type(String id) => DocType(id: id, name: id);
  Document doc(String type,
          {String id = 'X1', int status = 1,
          Map<String, dynamic> payload = const {}}) =>
      Document(id: id, docType: type, docStatus: status, payload: Map.of(payload));

  List<String> actionIds(Document d, String typeId) =>
      hubConversionActionsFor(d, type(typeId)).map((a) => a.id).toList();

  group('submittable sources (only when Submitted)', () {
    test('Quotation → Sales Order', () {
      expect(actionIds(doc('Quotation'), 'Quotation'),
          ['quotation-to-sales-order']);
    });

    test('Sales Order → Delivery + Invoice', () {
      expect(actionIds(doc('Sales Order'), 'Sales Order'),
          ['sales-order-to-delivery', 'sales-order-to-invoice']);
    });

    test('Delivery Note → Invoice + Return', () {
      expect(actionIds(doc('Delivery Note'), 'Delivery Note'),
          ['delivery-to-invoice', 'delivery-return']);
    });

    test('Purchase Order → Receipt + Invoice', () {
      expect(actionIds(doc('Purchase Order'), 'Purchase Order'),
          ['purchase-order-to-receipt', 'purchase-order-to-invoice']);
    });

    test('Purchase Receipt → Invoice + Return', () {
      expect(actionIds(doc('Purchase Receipt'), 'Purchase Receipt'),
          ['receipt-to-invoice', 'receipt-return']);
    });

    test('invoices and POS offer a Create Return action', () {
      expect(actionIds(doc('Sales Invoice'), 'Sales Invoice'),
          ['sales-invoice-return']);
      expect(actionIds(doc('Purchase Invoice'), 'Purchase Invoice'),
          ['purchase-invoice-return']);
      expect(actionIds(doc('POS Invoice'), 'POS Invoice'),
          ['pos-invoice-return']);
    });

    test('a return document itself offers nothing (no return-of-a-return)', () {
      expect(
          actionIds(doc('Sales Invoice', payload: {'is_return': 1}),
              'Sales Invoice'),
          isEmpty);
      expect(
          actionIds(doc('Delivery Note', payload: {'is_return': 1}),
              'Delivery Note'),
          isEmpty);
    });

    test('a draft (docStatus 0) source offers nothing', () {
      expect(actionIds(doc('Sales Order', status: 0), 'Sales Order'), isEmpty);
    });

    test('an unsaved source offers nothing', () {
      expect(actionIds(doc('Quotation', id: ''), 'Quotation'), isEmpty);
    });
  });

  group('Lead (master record — saved, not submitted)', () {
    test('a saved Lead offers Customer + Quotation', () {
      expect(actionIds(doc('Lead', status: 0), 'Lead'),
          ['lead-to-customer', 'lead-to-quotation']);
    });

    test('an unsaved Lead offers nothing', () {
      expect(actionIds(doc('Lead', id: '', status: 0), 'Lead'), isEmpty);
    });
  });

  test('an unrelated DocType offers nothing', () {
    expect(actionIds(doc('Payment Entry'), 'Payment Entry'), isEmpty);
  });

  test('the primary CTA is the quote→order conversion', () {
    final actions = hubConversionActionsFor(doc('Quotation'), type('Quotation'));
    expect(actions.single.style, WorkflowActionStyle.primary);
  });
}
