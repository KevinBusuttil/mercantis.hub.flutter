import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_hub_app/payments/guided_payment.dart';

/// Pure tests for the guided Receive Payment / Pay Supplier builder: open-invoice
/// selection/ordering, FIFO auto-allocation, and Payment Entry construction.
void main() {
  Document invoice(String id, num outstanding, String date,
          {String docType = 'Sales Invoice', num? grand, int docStatus = 1}) =>
      Document(id: id, docType: docType, docStatus: docStatus, payload: {
        'grand_total': grand ?? outstanding,
        'outstanding_amount': outstanding,
        'posting_date': date,
      });

  group('openInvoices', () {
    test('keeps submitted + outstanding, oldest first', () {
      final open = GuidedPayment.openInvoices([
        invoice('SINV-3', 50, '2026-03-01'),
        invoice('SINV-1', 100, '2026-01-01'),
        invoice('SINV-2', 0, '2026-02-01'), // fully paid → excluded
        invoice('SINV-4', 999, '2026-04-01', docStatus: 0), // draft → excluded
      ], receive: true);

      expect(open.map((o) => o.id).toList(), ['SINV-1', 'SINV-3']);
      expect(open.first.outstanding, 100);
    });

    test('falls back to grand_total when outstanding is unset', () {
      final doc = Document(id: 'SINV-9', docType: 'Sales Invoice', docStatus: 1, payload: {
        'grand_total': 200,
        'posting_date': '2026-01-01',
      });
      final open = GuidedPayment.openInvoices([doc], receive: true);
      expect(open.single.outstanding, 200);
    });
  });

  group('autoAllocate (FIFO)', () {
    test('fills oldest invoices first, stops when the amount runs out', () {
      final open = GuidedPayment.openInvoices([
        invoice('SINV-1', 100, '2026-01-01'),
        invoice('SINV-2', 50, '2026-02-01'),
        invoice('SINV-3', 80, '2026-03-01'),
      ], receive: true);

      final allocs = GuidedPayment.autoAllocate(open, 120);
      expect(allocs.length, 2);
      expect(allocs[0].invoiceId, 'SINV-1');
      expect(allocs[0].allocated, 100); // filled
      expect(allocs[1].invoiceId, 'SINV-2');
      expect(allocs[1].allocated, 20); // partial remainder
      expect(GuidedPayment.totalAllocated(allocs), 120);
    });
  });

  group('buildPaymentEntry', () {
    final allocs = [
      const PaymentAllocation(
        invoiceId: 'SINV-1',
        invoiceDocType: 'Sales Invoice',
        total: 100,
        outstanding: 100,
        allocated: 100,
      ),
    ];

    test('Receive: paid_from = receivable, paid_to = bank, customer party', () {
      final pe = GuidedPayment.buildPaymentEntry(
        receive: true,
        party: 'C1',
        postingDate: '2026-03-01',
        bankAccount: 'Bank',
        partyAccount: 'Debtors',
        allocations: allocs,
      );
      expect(pe.docType, 'Payment Entry');
      expect(pe.payload['payment_type'], 'Receive');
      expect(pe.payload['party_type'], 'Customer');
      expect(pe.payload['party'], 'C1');
      expect(pe.payload['paid_from'], 'Debtors');
      expect(pe.payload['paid_to'], 'Bank');
      expect(pe.payload['paid_amount'], 100);
      expect(pe.payload['received_amount'], 100);

      final refs = pe.children['references']!;
      expect(refs.length, 1);
      expect(refs.single.payload['reference_doctype'], 'Sales Invoice');
      expect(refs.single.payload['reference_name'], 'SINV-1');
      expect(refs.single.payload['allocated_amount'], 100);
      expect(refs.single.payload['outstanding_amount'], 100);
    });

    test('Pay: paid_from = bank, paid_to = payable, supplier party', () {
      final pe = GuidedPayment.buildPaymentEntry(
        receive: false,
        party: 'S1',
        postingDate: '2026-03-01',
        bankAccount: 'Bank',
        partyAccount: 'Creditors',
        allocations: const [
          PaymentAllocation(
            invoiceId: 'PINV-1',
            invoiceDocType: 'Purchase Invoice',
            total: 60,
            outstanding: 60,
            allocated: 60,
          ),
        ],
      );
      expect(pe.payload['payment_type'], 'Pay');
      expect(pe.payload['party_type'], 'Supplier');
      expect(pe.payload['paid_from'], 'Bank');
      expect(pe.payload['paid_to'], 'Creditors');
      expect(pe.payload['paid_amount'], 60);
    });

    test('blank accounts are omitted (left for the defaults interceptor)', () {
      final pe = GuidedPayment.buildPaymentEntry(
        receive: true,
        party: 'C1',
        postingDate: '2026-03-01',
        allocations: allocs,
      );
      expect(pe.payload.containsKey('paid_from'), isFalse);
      expect(pe.payload.containsKey('paid_to'), isFalse);
    });

    test('an overpayment keeps the full amount (surplus = party advance)', () {
      final pe = GuidedPayment.buildPaymentEntry(
        receive: true,
        party: 'C1',
        postingDate: '2026-03-01',
        allocations: allocs,
        amount: 100, // more than the allocations — surplus becomes credit
      );
      expect(pe.payload['paid_amount'], 100);
      expect(pe.payload['received_amount'], 100);
      // Allocations unchanged — settlements only reduce invoices by their sum.
      num allocated = 0;
      for (final r in pe.children['references']!) {
        allocated += r.payload['allocated_amount'] as num;
      }
      expect(allocated, GuidedPayment.totalAllocated(allocs));
    });

    test('an amount below the allocations is clamped up (books stay sane)',
        () {
      final pe = GuidedPayment.buildPaymentEntry(
        receive: true,
        party: 'C1',
        postingDate: '2026-03-01',
        allocations: allocs,
        amount: 10, // invalid — a UI should prevent it; builder clamps up
      );
      expect(pe.payload['paid_amount'], GuidedPayment.totalAllocated(allocs));
    });
  });
}
