import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_hub_app/modules/selling/hub_document_conversion.dart';

/// H3 — one-click document conversion (pure Document→Document builders).
void main() {
  final dateRe = RegExp(r'^\d{4}-\d{2}-\d{2}$');

  ChildRow line(String parent, int i, Map<String, dynamic> payload) => ChildRow(
        id: 'r$i',
        parentId: 'src',
        parentDocType: parent,
        tableName: 'items',
        rowIndex: i,
        payload: payload,
      );

  Document doc(String id, String type,
          {Map<String, dynamic> payload = const {}, List<ChildRow> items = const []}) =>
      Document(
        id: id,
        docType: type,
        company: 'ACME',
        payload: Map<String, dynamic>.from(payload),
        children: {'items': items},
      );

  group('quotationToSalesOrder', () {
    test('carries header + all lines and links back to the quote', () {
      final quote = doc('QTN-1', 'Quotation', payload: {
        'customer': 'CUST-1',
        'currency': 'EUR',
        'delivery_date': '2026-07-01',
      }, items: [
        line('Quotation', 0, {'item': 'ITEM-A', 'qty': 2, 'rate': 10, 'uom': 'Nos'}),
        line('Quotation', 1, {'item': 'ITEM-B', 'qty': 3, 'rate': 5}),
      ]);

      final so = HubDocumentConversion.quotationToSalesOrder(quote);

      expect(so.docType, 'Sales Order');
      expect(so.docStatus, 0);
      expect(so.payload['workflow_state'], 'Draft');
      expect(so.company, 'ACME');
      expect(so.payload['customer'], 'CUST-1');
      expect(so.payload['currency'], 'EUR');
      expect(so.payload['quotation'], 'QTN-1');
      expect(so.payload['transaction_date'], matches(dateRe));
      final items = so.children['items']!;
      expect(items.length, 2);
      expect(items[0].payload['item'], 'ITEM-A');
      expect(items[0].payload['qty'], 2);
      expect(items[0].parentDocType, 'Sales Order');
      expect(items[1].payload['item'], 'ITEM-B');
    });
  });

  group('salesOrderToInvoice (remaining qty)', () {
    final order = doc('SO-1', 'Sales Order', payload: {
      'customer': 'CUST-1',
      'currency': 'EUR',
      'tax_code': 'VAT-STD',
    }, items: [
      line('Sales Order', 0, {'item': 'ITEM-A', 'qty': 10, 'rate': 4}),
      line('Sales Order', 1, {'item': 'ITEM-B', 'qty': 5, 'rate': 9}),
    ]);

    test('defaults each line to the unbilled balance, dropping billed lines', () {
      final inv = HubDocumentConversion.salesOrderToInvoice(order,
          billedByItem: {'ITEM-A': 4, 'ITEM-B': 5});

      expect(inv.docType, 'Sales Invoice');
      expect(inv.payload['posting_date'], matches(dateRe));
      expect(inv.payload['sales_order'], 'SO-1');
      expect(inv.payload['tax_code'], 'VAT-STD');
      final items = inv.children['items']!;
      expect(items.length, 1); // ITEM-B fully billed → dropped
      expect(items[0].payload['item'], 'ITEM-A');
      expect(items[0].payload['qty'], 6); // 10 ordered − 4 billed
    });

    test('nothing billed → full quantities carried', () {
      final inv = HubDocumentConversion.salesOrderToInvoice(order);
      expect(inv.children['items']!.map((r) => r.payload['qty']), [10, 5]);
    });
  });

  group('salesOrderToDelivery', () {
    test('links each line back to the order and carries the remaining qty', () {
      final order = doc('SO-9', 'Sales Order', payload: {'customer': 'C'}, items: [
        line('Sales Order', 0, {'item': 'ITEM-A', 'qty': 8, 'rate': 1}),
      ]);
      final dn = HubDocumentConversion.salesOrderToDelivery(order,
          deliveredByItem: {'ITEM-A': 3});
      expect(dn.docType, 'Delivery Note');
      expect(dn.payload['sales_order'], 'SO-9');
      final row = dn.children['items']!.single;
      expect(row.payload['qty'], 5);
      expect(row.payload['sales_order'], 'SO-9'); // per-line back-link
    });
  });

  group('deliveryToInvoice', () {
    test('bills shipped lines verbatim and threads the order link', () {
      final dn = doc('DN-1', 'Delivery Note', payload: {
        'customer': 'CUST-1',
        'sales_order': 'SO-1',
      }, items: [
        line('Delivery Note', 0, {'item': 'ITEM-A', 'qty': 7, 'rate': 2}),
      ]);
      final inv = HubDocumentConversion.deliveryToInvoice(dn);
      expect(inv.docType, 'Sales Invoice');
      expect(inv.payload['delivery_note'], 'DN-1');
      expect(inv.payload['sales_order'], 'SO-1');
      expect(inv.children['items']!.single.payload['qty'], 7);
    });
  });

  group('buying', () {
    test('purchaseOrderToReceipt nets received qty + back-links', () {
      final po = doc('PO-1', 'Purchase Order', payload: {'supplier': 'SUP-1'}, items: [
        line('Purchase Order', 0, {'item': 'ITEM-A', 'qty': 12, 'rate': 3}),
      ]);
      final rec = HubDocumentConversion.purchaseOrderToReceipt(po,
          receivedByItem: {'ITEM-A': 12});
      expect(rec.docType, 'Purchase Receipt');
      expect(rec.payload['purchase_order'], 'PO-1');
      expect(rec.children['items'], isEmpty); // fully received → no lines
    });

    test('receiptToInvoice carries lines and threads the PO link', () {
      final rec = doc('PR-1', 'Purchase Receipt', payload: {
        'supplier': 'SUP-1',
        'purchase_order': 'PO-1',
      }, items: [
        line('Purchase Receipt', 0, {'item': 'ITEM-A', 'qty': 4, 'rate': 3}),
      ]);
      final inv = HubDocumentConversion.receiptToInvoice(rec);
      expect(inv.docType, 'Purchase Invoice');
      expect(inv.payload['purchase_receipt'], 'PR-1');
      expect(inv.payload['purchase_order'], 'PO-1');
      expect(inv.children['items']!.single.payload['qty'], 4);
    });
  });

  group('leadToCustomer', () {
    test('a company lead becomes a Company customer', () {
      final lead = doc('LEAD-1', 'Lead', payload: {
        'first_name': 'Jane',
        'company_name': 'Globex',
      });
      final cust = HubDocumentConversion.leadToCustomer(lead);
      expect(cust.docType, 'Customer');
      expect(cust.id, isEmpty); // engine assigns via naming series
      expect(cust.payload['customer_type'], 'Company');
      expect(cust.payload['customer_name'], 'Globex');
    });

    test('an individual lead is named from first/last name', () {
      final lead = doc('LEAD-2', 'Lead',
          payload: {'first_name': 'Jane', 'last_name': 'Doe'});
      final cust = HubDocumentConversion.leadToCustomer(lead);
      expect(cust.payload['customer_type'], 'Individual');
      expect(cust.payload['customer_name'], 'Jane Doe');
    });
  });

  group('remainingLines (greedy netting)', () {
    test('consumes the fulfilled pool greedily across same-item lines', () {
      final rows = [
        line('Sales Order', 0, {'item': 'A', 'qty': 3, 'rate': 1}),
        line('Sales Order', 1, {'item': 'A', 'qty': 4, 'rate': 1}),
      ];
      final out = HubDocumentConversion.remainingLines(
        rows,
        fulfilledByItem: {'A': 5},
        carryKeys: const ['item', 'rate'],
        targetDocType: 'Sales Invoice',
      );
      // line0 fully consumed (3 of 5), line1 keeps 2 of 4.
      expect(out.length, 1);
      expect(out.single.payload['qty'], 2);
      expect(out.single.rowIndex, 0);
    });
  });

  group('fulfilledByItem', () {
    test('sums qty per item across downstream documents', () {
      final dn1 = doc('DN-1', 'Delivery Note', items: [
        line('Delivery Note', 0, {'item': 'A', 'qty': 3}),
        line('Delivery Note', 1, {'item': 'B', 'qty': 1}),
      ]);
      final dn2 = doc('DN-2', 'Delivery Note', items: [
        line('Delivery Note', 0, {'item': 'A', 'qty': 2}),
      ]);
      final totals = HubDocumentConversion.fulfilledByItem([dn1, dn2]);
      expect(totals['A'], 5);
      expect(totals['B'], 1);
    });
  });

  group('quotationForCustomer', () {
    test('builds an empty quotation draft with the optional opportunity', () {
      final q = HubDocumentConversion.quotationForCustomer(
          customerId: 'CUST-1', opportunityId: 'OPP-1', company: 'ACME');
      expect(q.docType, 'Quotation');
      expect(q.payload['customer'], 'CUST-1');
      expect(q.payload['opportunity'], 'OPP-1');
      expect(q.payload['transaction_date'], matches(dateRe));
      expect(q.children['items'], isEmpty);

      final q2 = HubDocumentConversion.quotationForCustomer(
          customerId: 'CUST-1', company: 'ACME');
      expect(q2.payload.containsKey('opportunity'), isFalse);
    });
  });

  group('returns (H6)', () {
    test('salesInvoiceReturn negates qty, flags is_return, links the original',
        () {
      final inv = doc('SINV-1', 'Sales Invoice', payload: {
        'customer': 'CUST-1',
        'currency': 'EUR',
        'debit_to': 'Debtors',
        'income_account': 'Sales',
        'tax_code': 'VAT-STD',
      }, items: [
        line('Sales Invoice', 0, {'item': 'ITEM-A', 'qty': 3, 'rate': 10, 'uom': 'Nos'}),
        line('Sales Invoice', 1, {'item': 'ITEM-B', 'qty': 2, 'rate': 5}),
      ]);

      final ret = HubDocumentConversion.salesInvoiceReturn(inv);

      expect(ret.docType, 'Sales Invoice');
      expect(ret.docStatus, 0);
      expect(ret.payload['is_return'], 1);
      expect(ret.payload['return_against'], 'SINV-1');
      expect(ret.payload['customer'], 'CUST-1');
      expect(ret.payload['debit_to'], 'Debtors');
      final items = ret.children['items']!;
      expect(items.length, 2);
      expect(items[0].payload['qty'], -3); // negated
      expect(items[0].payload['rate'], 10); // rate unchanged
      expect(items[1].payload['qty'], -2);
      expect(items[0].parentDocType, 'Sales Invoice');
    });

    test('purchaseInvoiceReturn mirrors it on the buying side', () {
      final inv = doc('PINV-1', 'Purchase Invoice', payload: {
        'supplier': 'SUP-1',
        'credit_to': 'Creditors',
        'expense_account': 'Cost of Goods',
      }, items: [
        line('Purchase Invoice', 0, {'item': 'ITEM-A', 'qty': 4, 'rate': 7}),
      ]);

      final ret = HubDocumentConversion.purchaseInvoiceReturn(inv);

      expect(ret.docType, 'Purchase Invoice');
      expect(ret.payload['is_return'], 1);
      expect(ret.payload['return_against'], 'PINV-1');
      expect(ret.payload['supplier'], 'SUP-1');
      expect(ret.payload['credit_to'], 'Creditors');
      expect(ret.children['items']!.single.payload['qty'], -4);
    });

    test('deliveryReturn negates qty and links the original delivery', () {
      final dn = doc('DN-1', 'Delivery Note', payload: {
        'customer': 'CUST-1',
        'set_warehouse': 'WH',
      }, items: [
        line('Delivery Note', 0, {'item': 'ITEM-A', 'qty': 5, 'rate': 10, 'warehouse': 'WH'}),
      ]);

      final ret = HubDocumentConversion.deliveryReturn(dn);

      expect(ret.docType, 'Delivery Note');
      expect(ret.payload['is_return'], 1);
      expect(ret.payload['return_against'], 'DN-1');
      expect(ret.payload['set_warehouse'], 'WH');
      expect(ret.children['items']!.single.payload['qty'], -5);
    });

    test('purchaseReceiptReturn and posInvoiceReturn negate + link', () {
      final pr = doc('PR-1', 'Purchase Receipt', payload: {
        'supplier': 'SUP-1', 'set_warehouse': 'WH',
      }, items: [
        line('Purchase Receipt', 0, {'item': 'ITEM-A', 'qty': 6, 'rate': 4}),
      ]);
      final prRet = HubDocumentConversion.purchaseReceiptReturn(pr);
      expect(prRet.payload['is_return'], 1);
      expect(prRet.payload['return_against'], 'PR-1');
      expect(prRet.children['items']!.single.payload['qty'], -6);

      final pos = doc('POS-1', 'POS Invoice', payload: {
        'customer': 'CUST-1', 'set_warehouse': 'WH', 'cash_account': 'Cash',
      }, items: [
        line('POS Invoice', 0, {'item': 'ITEM-A', 'qty': 2, 'rate': 15}),
      ]);
      final posRet = HubDocumentConversion.posInvoiceReturn(pos);
      expect(posRet.payload['is_return'], 1);
      expect(posRet.payload['return_against'], 'POS-1');
      expect(posRet.payload['cash_account'], 'Cash');
      expect(posRet.children['items']!.single.payload['qty'], -2);
    });
  });
}
