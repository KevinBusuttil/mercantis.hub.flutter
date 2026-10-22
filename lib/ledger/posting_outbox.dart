import 'package:mercantis_core/mercantis_core.dart';

import 'ledger_derivation.dart';

/// The posting outbox: a durable "this voucher still owes its ledger rows"
/// marker, written in the SAME transaction that submits or cancels the
/// voucher.
///
/// Ledger derivation runs after the submit commits (it saves GL, subledger and
/// stock rows through the engine). A crash, a power cut or a failed write in
/// that window used to leave a submitted invoice with no GL at all, or only
/// some of its legs, and nothing recorded that it had happened. Now the
/// submit commits a `pending` posting batch; derivation marks it `posted`
/// when every row is written, or `failed` with the error. At startup
/// `LedgerDerivationService.recoverPendingPostings` re-runs every batch that
/// is not `posted`. Derived rows have deterministic ids, so a re-run
/// overwrites a partial attempt instead of duplicating it.
///
/// Vouchers submitted before the outbox existed have no batch and are never
/// touched by recovery.
class PostingOutboxInterceptor extends DocumentInterceptor {
  const PostingOutboxInterceptor();

  @override
  Future<void> inLifecycleTransaction(DocumentEngine engine, Document doc,
      DocType docType, UnitOfWork uow, LifecycleAction action) async {
    if (!LedgerDerivation.postingSources.contains(doc.docType)) return;
    await uow.recordPostingBatch(PostingBatch(
      id: postingBatchId(doc.docType, doc.id, action),
      sourceType: doc.docType,
      sourceId: doc.id,
      status: PostingStatus.pending,
    ));
  }
}

/// Deterministic outbox id for one lifecycle transition of a voucher.
String postingBatchId(String docType, String id, LifecycleAction action) =>
    'LEDGER:${action.name}:$docType:$id';

/// Parses an id made by [postingBatchId]; null for any other batch.
({LifecycleAction action, String docType, String id})? parsePostingBatchId(
    String batchId) {
  final parts = batchId.split(':');
  if (parts.length < 4 || parts[0] != 'LEDGER') return null;
  final action =
      LifecycleAction.values.where((a) => a.name == parts[1]).firstOrNull;
  if (action == null) return null;
  return (
    action: action,
    docType: parts[2],
    id: parts.sublist(3).join(':'),
  );
}
