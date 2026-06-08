import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_hub_app/payments/pos_checkout.dart';

/// Pure tests for the POS checkout builder: tender/change math and POS Invoice
/// construction.
void main() {
  group('tender math', () {
    const tenders = [PosTender(type: 'Cash', amount: 30), PosTender(type: 'Card', amount: 20)];

    test('tendered sums all payments', () {
      expect(PosCheckout.tendered(tenders), 50);
    });

    test('isFullyPaid compares against grand total', () {
      expect(PosCheckout.isFullyPaid(tenders, 50), isTrue);
      expect(PosCheckout.isFullyPaid(tenders, 60), isFalse);
    });

    test('change is the overpayment, never negative', () {
      expect(PosCheckout.change(tenders, 45), 5);
      expect(PosCheckout.change(tenders, 50), 0);
      expect(PosCheckout.change(tenders, 70), 0);
    });
  });

  group('buildPosInvoice', () {
    test('maps cart + tenders to a POS Invoice draft', () {
      final doc = PosCheckout.buildPosInvoice(
        postingDate: '2026-01-01',
        warehouse: 'WH1',
        cashAccount: 'Bank',
        incomeAccount: 'Sales',
        customer: 'C1',
        lines: const [
          PosCartLine(item: 'ITM', qty: 2, rate: 500, taxCode: 'VAT 18%'),
        ],
        tenders: const [PosTender(type: 'Cash', amount: 1180)],
      );

      expect(doc.docType, 'POS Invoice');
      expect(doc.payload['posting_date'], '2026-01-01');
      expect(doc.payload['set_warehouse'], 'WH1');
      expect(doc.payload['cash_account'], 'Bank');
      expect(doc.payload['income_account'], 'Sales');
      expect(doc.payload['customer'], 'C1');
      expect(doc.payload['paid_amount'], 1180);

      final items = doc.children['items']!;
      expect(items.length, 1);
      expect(items.single.payload['item'], 'ITM');
      expect(items.single.payload['qty'], 2);
      expect(items.single.payload['rate'], 500);
      expect(items.single.payload['tax_code'], 'VAT 18%');

      final tenders = doc.children['tenders']!;
      expect(tenders.single.payload['tender_type'], 'Cash');
      expect(tenders.single.payload['amount'], 1180);
    });
  });
}
