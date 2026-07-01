import 'package:mercantis_core/mercantis_core.dart';

import '../../ledger/ledger_values.dart';

/// The lifecycle status shown for an invoice, derived from its doc status,
/// outstanding balance, and due date (H2 — ported from the Swift
/// `InvoiceStatusService`).
abstract final class InvoiceStatus {
  static const draft = 'Draft';
  static const unpaid = 'Unpaid';
  static const partlyPaid = 'Partly Paid';
  static const paid = 'Paid';
  static const overdue = 'Overdue';
  static const cancelled = 'Cancelled';
  static const returned = 'Return';

  /// Pure status rule. A cancelled/draft/return invoice reports that directly;
  /// a submitted one is Paid once nothing is outstanding, Overdue when past its
  /// [dueDate] with a balance, and otherwise Partly Paid or Unpaid depending on
  /// whether anything has been settled. Amounts are compared with a cent of
  /// tolerance. [asOf] and [dueDate] are ISO dates (string compare is valid).
  static String compute({
    required int docStatus,
    required num grandTotal,
    required num outstanding,
    String? dueDate,
    String? asOf,
    bool isReturn = false,
  }) {
    if (docStatus == 2) return cancelled;
    if (docStatus == 0) return draft;
    if (isReturn) return returned;
    if (outstanding <= 0.005) return paid;
    if (dueDate != null && asOf != null && asOf.compareTo(dueDate) > 0) {
      return overdue;
    }
    return outstanding < grandTotal - 0.005 ? partlyPaid : unpaid;
  }
}

/// Computes invoice statuses off the engine: the derived status of one invoice,
/// and the list of a doctype's overdue invoices as of a date.
class InvoiceStatusService {
  InvoiceStatusService({required this.engine, this.roles = const {'System Manager'}});

  final DocumentEngine engine;
  final Set<String> roles;

  Future<String> statusOf(String docType, String id, {String? asOf}) async {
    final inv = await engine.fetch(docType, id);
    if (inv == null) return InvoiceStatus.draft;
    return _status(inv, asOf);
  }

  /// Submitted invoices of [docType] that are past due with a balance as of
  /// [asOf], newest-due first.
  Future<List<Document>> overdue(String docType, {required String asOf}) async {
    final all = await engine.list(docType, userRoles: roles);
    final out = [
      for (final inv in all)
        if (_status(inv, asOf) == InvoiceStatus.overdue) inv,
    ];
    out.sort((a, b) =>
        '${b.payload['due_date']}'.compareTo('${a.payload['due_date']}'));
    return out;
  }

  String _status(Document inv, String? asOf) => InvoiceStatus.compute(
        docStatus: inv.docStatus,
        grandTotal: asNum(inv.payload['grand_total']),
        outstanding: asNum(inv.payload['outstanding_amount']),
        dueDate: asNonEmpty(inv.payload['due_date']),
        asOf: asOf,
        isReturn: isTrue(inv.payload['is_return']),
      );
}
