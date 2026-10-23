import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

import '../ledger/hub_interceptors.dart';
import '../ledger/ledger_derivation.dart';
import '../ledger/ledger_values.dart';
import 'team_posting_service.dart';
import 'team_session.dart';

/// Engine-level posting authority for Atlas Team.
///
/// In a Team company the server is the only engine allowed to produce
/// official accounting. The form's Submit/Cancel already route the
/// backend-posted doctypes to the server ([TeamOfficialPosting]), but many
/// other flows submit through [DocumentEngine.submit] directly: guided
/// payments, recurring invoices, channel imports, rental and booking
/// deposits, construction valuations, depreciation journals, manufacturing,
/// opening take-on. Each of those would post GL and stock on this device
/// alone and replicate the result as if it were official, which the server
/// now refuses. This interceptor closes every such path at the engine, so no
/// caller can bypass it:
///
/// * Submitting or cancelling any ledger-posting doctype locally is refused
///   while connected to Team. The message says how to post it instead: from
///   its form, or not yet at all for the doctypes the server cannot post.
/// * **POS Invoice** keeps its deliberate offline policy. The till posts the
///   sale locally (checkout must never need the network) and the Team sync
///   confirms it with the server afterwards ([confirmPendingTillSales]).
///   That only stays unique across registers when the sale carries its
///   till's own receipt series, so a POS sale without one is refused. A
///   till sale is reversed with a return, never cancelled locally.
///
/// Inactive (a no-op) whenever no Team session exists: Solo is unaffected.
class TeamPostingAuthorityGuard extends DocumentInterceptor {
  const TeamPostingAuthorityGuard(this.isTeam);

  /// Whether this install is connected to Atlas Team right now.
  final bool Function() isTeam;

  @override
  Future<void> beforeSubmit(
      DocumentEngine engine, Document doc, DocType docType) async {
    if (!isTeam()) return;
    final refusal = teamLocalSubmitRefusal(doc);
    if (refusal != null) throw _refuse(refusal);
  }

  @override
  Future<void> inLifecycleTransaction(DocumentEngine engine, Document doc,
      DocType docType, UnitOfWork uow, LifecycleAction action) async {
    if (action != LifecycleAction.cancel || !isTeam()) return;
    if (!LedgerDerivation.postingSources.contains(doc.docType)) return;
    throw _refuse(doc.docType == 'POS Invoice'
        ? 'A till sale is part of the Team books once it is made. Reverse it '
            'with a return from the till instead of cancelling it.'
        : teamPostedDocTypes.contains(doc.docType)
            ? 'In Atlas Team, ${doc.docType} is cancelled by the Team server. '
                'Cancel it from its form while connected.'
            : _unsupported(doc.docType));
  }

  static DocumentEngineError _refuse(String message) =>
      DocumentEngineError.validationFailed([
        ValidationError(
            stage: 'team_authority', fieldKey: 'docstatus', message: message),
      ]);
}

/// Why this device may not submit [doc] locally in a Team company, or null
/// when it may. Pure: the guard's decision, exposed for tests and for
/// screens that want to explain before the user presses Submit.
String? teamLocalSubmitRefusal(Document doc) {
  if (!LedgerDerivation.postingSources.contains(doc.docType)) return null;
  if (doc.docType == 'POS Invoice') {
    return asNonEmpty(doc.payload['till_series']) == null
        ? 'In Atlas Team every till needs its own receipt series, so receipts '
            'from different registers can never share a number. Set the '
            'receipt series on this till\'s POS profile, then take the sale.'
        : null;
  }
  if (teamPostedDocTypes.contains(doc.docType)) {
    return 'In Atlas Team, ${doc.docType} is posted by the Team server so '
        'every device sees the same official books. Submit it from the '
        '${doc.docType} form while connected.';
  }
  return _unsupported(doc.docType);
}

String _unsupported(String docType) =>
    '$docType cannot be posted in Atlas Team yet. The Team server does not '
    'post it, and posting it on this device alone would give each device '
    'different books. Keep it as a draft for now.';

/// The Hub's interceptors plus the Team guard, which reads the live Team
/// session at call time (connecting or disconnecting does not rebuild the
/// engine).
final teamAwareInterceptorsOverride =
    documentInterceptorsProvider.overrideWith((ref) => [
          TeamPostingAuthorityGuard(
              () => ref.read(teamSessionProvider) != null),
          ...hubInterceptors,
        ]);
