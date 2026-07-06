import 'package:mercantis_core/mercantis_core.dart';

import '../../ledger/ledger_values.dart';

/// The customer-facing quotation lifecycle (Phase 1A), derived — like
/// [InvoiceStatus] — rather than stored, so Expired needs no scheduler: a
/// quote past its `valid_till` reads as Expired the moment you look at it.
///
/// Precedence: Cancelled > Draft > Converted > Accepted > Rejected >
/// Expired > Sent > Open. An accepted or converted quote never expires;
/// rejection sticks even past the validity date.
abstract final class QuotationStatus {
  static const draft = 'Draft';
  static const open = 'Open'; // submitted, not yet sent
  static const sent = 'Sent';
  static const accepted = 'Accepted';
  static const rejected = 'Rejected';
  static const expired = 'Expired';
  static const converted = 'Converted';
  static const cancelled = 'Cancelled';

  /// Pure status rule. Dates are ISO strings (string compare is valid).
  /// [workflowState] folds the pre-existing internal workflow in: 'Ordered'
  /// reads as Converted, 'Lost' as Rejected. [hasDownstream] is the lineage
  /// signal (a Sales Order/Invoice created from this quote).
  static String compute({
    required int docStatus,
    String? workflowState,
    String? sentOn,
    String? acceptedOn,
    String? rejectedOn,
    String? validTill,
    String? asOf,
    bool hasDownstream = false,
  }) {
    if (docStatus == 2) return cancelled;
    if (docStatus == 0) return draft;
    if (hasDownstream || workflowState == 'Ordered') return converted;
    if (acceptedOn != null) return accepted;
    if (rejectedOn != null || workflowState == 'Lost') return rejected;
    if (validTill != null && asOf != null && asOf.compareTo(validTill) > 0) {
      return expired;
    }
    return sentOn != null ? sent : open;
  }

  /// [compute] from a document's fields, [asOf] defaulting to today.
  /// Downstream conversion is read from the workflow state only — pass
  /// [hasDownstream] when the caller has checked lineage.
  static String of(Document doc, {String? asOf, bool hasDownstream = false}) {
    return compute(
      docStatus: doc.docStatus,
      workflowState: asNonEmpty(doc.payload['workflow_state']),
      sentOn: asNonEmpty(doc.payload['sent_on']),
      acceptedOn: asNonEmpty(doc.payload['accepted_on']),
      rejectedOn: asNonEmpty(doc.payload['rejected_on']),
      validTill: asNonEmpty(doc.payload['valid_till']),
      asOf: asOf ?? DateTime.now().toIso8601String().split('T').first,
      hasDownstream: hasDownstream,
    );
  }
}

/// Engine-backed queries over quotation statuses.
class QuotationStatusService {
  QuotationStatusService(
      {required this.engine, this.roles = const {'System Manager'}});

  final DocumentEngine engine;
  final Set<String> roles;

  /// The derived status of one quotation, lineage-aware: a submitted Sales
  /// Order back-linking the quote makes it Converted even if the workflow
  /// wasn't advanced.
  Future<String> statusOf(String id, {String? asOf}) async {
    final doc = await engine.fetch('Quotation', id);
    if (doc == null) return QuotationStatus.draft;
    final downstream = await engine.list('Sales Order',
        filters: {'quotation': id}, userRoles: roles);
    return QuotationStatus.of(doc,
        asOf: asOf, hasDownstream: downstream.any((d) => d.docStatus == 1));
  }

  /// Submitted quotations past their validity date (not accepted, rejected
  /// or converted) — the follow-up list.
  Future<List<Document>> expired({required String asOf}) async {
    final all = await engine.list('Quotation', userRoles: roles);
    return [
      for (final q in all)
        if (QuotationStatus.of(q, asOf: asOf) == QuotationStatus.expired) q,
    ];
  }
}
