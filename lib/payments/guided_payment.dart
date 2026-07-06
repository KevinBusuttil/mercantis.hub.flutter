import 'package:mercantis_core/mercantis_core.dart';

import '../ledger/ledger_values.dart';

/// An open (submitted, not fully paid) invoice a payment can be allocated to.
class OpenInvoice {
  final String id;
  final String docType; // 'Sales Invoice' or 'Purchase Invoice'
  final num total; // grand_total
  final num outstanding; // outstanding_amount (falls back to grand_total)
  final DateTime? date; // posting_date, for FIFO ordering

  const OpenInvoice({
    required this.id,
    required this.docType,
    required this.total,
    required this.outstanding,
    this.date,
  });
}

/// One invoice ↔ payment allocation row (becomes a Payment Entry reference).
class PaymentAllocation {
  final String invoiceId;
  final String invoiceDocType;
  final num total;
  final num outstanding;
  final num allocated;

  const PaymentAllocation({
    required this.invoiceId,
    required this.invoiceDocType,
    required this.total,
    required this.outstanding,
    required this.allocated,
  });
}

/// Pure helpers behind the guided Receive Payment / Pay Supplier flows (ported
/// from the Swift `GuidedPaymentBuilder`). They turn a party's open invoices and
/// an amount into the allocations + the Payment Entry document; submitting that
/// document drives the existing ledger derivation (GL legs, party subledger,
/// Settlement rows, invoice `outstanding_amount` upkeep).
abstract final class GuidedPayment {
  /// The source invoice DocType for a direction.
  static String invoiceDocType({required bool receive}) =>
      receive ? 'Sales Invoice' : 'Purchase Invoice';

  /// The party field/type for a direction.
  static String partyField({required bool receive}) => receive ? 'customer' : 'supplier';
  static String partyType({required bool receive}) => receive ? 'Customer' : 'Supplier';

  /// Filters a party's invoices to those still open (submitted, outstanding > 0)
  /// and sorts them oldest-first by posting date — the order a payment fills.
  static List<OpenInvoice> openInvoices(List<Document> invoices, {required bool receive}) {
    final docType = invoiceDocType(receive: receive);
    final open = <OpenInvoice>[];
    for (final inv in invoices) {
      if (inv.docStatus != 1) continue;
      final total = asNum(inv.payload['grand_total']);
      final raw = inv.payload['outstanding_amount'];
      final outstanding = raw == null ? total : asNum(raw);
      if (outstanding <= 0.0001) continue;
      open.add(OpenInvoice(
        id: inv.id,
        docType: docType,
        total: total,
        outstanding: outstanding,
        date: _asDate(inv.payload['posting_date']),
      ));
    }
    open.sort((a, b) =>
        (a.date ?? DateTime(9999)).compareTo(b.date ?? DateTime(9999)));
    return open;
  }

  /// Spreads [amount] across [invoices] oldest-first (FIFO), allocating
  /// `min(remaining, outstanding)` to each until the amount is used up. Returns
  /// only the invoices that received a positive allocation. Convenience for the
  /// "auto-allocate" button; the user may still edit per-row amounts.
  static List<PaymentAllocation> autoAllocate(List<OpenInvoice> invoices, num amount) {
    var remaining = round2(amount);
    final out = <PaymentAllocation>[];
    for (final inv in invoices) {
      if (remaining <= 0.0001) break;
      final take = round2(remaining < inv.outstanding ? remaining : inv.outstanding);
      if (take <= 0.0001) continue;
      out.add(PaymentAllocation(
        invoiceId: inv.id,
        invoiceDocType: inv.docType,
        total: inv.total,
        outstanding: inv.outstanding,
        allocated: take,
      ));
      remaining = round2(remaining - take);
    }
    return out;
  }

  /// Sum of allocated amounts, rounded to currency precision.
  static num totalAllocated(Iterable<PaymentAllocation> allocations) =>
      round2(allocations.fold<num>(0, (s, a) => s + a.allocated));

  /// Builds the draft Payment Entry for the given allocations. Accounts:
  /// Receive → paid_from = receivable (party), paid_to = bank/cash;
  /// Pay → paid_from = bank/cash, paid_to = payable (party). Blank accounts are
  /// still filled by the Business Profile defaults interceptor on save, so the
  /// builder works even before accounts are chosen.
  ///
  /// [amount] is the money actually received/paid. When it exceeds the
  /// allocations, the surplus is NOT dropped: the Payment Entry carries the
  /// full amount, so the ledger books the whole receipt against the party —
  /// the unallocated remainder becomes a customer/supplier advance (credit)
  /// applicable to future invoices. Omitted (or below the allocations, which
  /// a UI shouldn't allow), it falls back to the allocated total so the
  /// books can never settle more than was paid.
  static Document buildPaymentEntry({
    required bool receive,
    required String party,
    required String postingDate,
    String? currency,
    String? bankAccount,
    String? partyAccount,
    String? company,
    required List<PaymentAllocation> allocations,
    num? amount,
  }) {
    final allocated = totalAllocated(allocations);
    final total =
        (amount != null && round2(amount) > allocated) ? round2(amount) : allocated;
    final paidFrom = receive ? partyAccount : bankAccount;
    final paidTo = receive ? bankAccount : partyAccount;

    final doc = Document(
      id: '',
      docType: 'Payment Entry',
      company: company,
      payload: {
        'payment_type': receive ? 'Receive' : 'Pay',
        'posting_date': postingDate,
        'party_type': partyType(receive: receive),
        'party': party,
        if (asNonEmpty(paidFrom) != null) 'paid_from': paidFrom,
        if (asNonEmpty(paidTo) != null) 'paid_to': paidTo,
        'paid_amount': total,
        'received_amount': total,
        if (asNonEmpty(currency) != null) 'currency': currency,
      },
    );
    doc.children['references'] = [
      for (var i = 0; i < allocations.length; i++)
        ChildRow(
          id: '',
          parentId: '',
          parentDocType: 'Payment Entry',
          tableName: 'references',
          rowIndex: i,
          payload: {
            'reference_doctype': allocations[i].invoiceDocType,
            'reference_name': allocations[i].invoiceId,
            'total_amount': allocations[i].total,
            'outstanding_amount': allocations[i].outstanding,
            'allocated_amount': round2(allocations[i].allocated),
          },
        ),
    ];
    return doc;
  }

  static DateTime? _asDate(dynamic v) {
    if (v is DateTime) return v;
    if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
    if (v is String && v.isNotEmpty) return DateTime.tryParse(v);
    return null;
  }
}
