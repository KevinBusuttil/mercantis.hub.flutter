import 'dart:convert';

import 'package:mercantis_core/mercantis_core.dart';
import 'package:sqflite_common/sqflite.dart' show DatabaseExecutor;

import 'ledger_derivation.dart';
import 'ledger_values.dart' show isTrue;

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
    if (_movesStock(doc.docType, doc.payload)) {
      final blocker = await _failedStockPosting(uow.db, doc);
      if (blocker != null) {
        throw DocumentEngineError.validationFailed([
          ValidationError(
            stage: 'owed_postings',
            fieldKey: 'docstatus',
            message: 'The ledger postings of ${blocker.docType} ${blocker.id} '
                'failed and are still owed. Stock documents are paused until '
                'they post, so every movement is costed against the stock it '
                'really met. Close and reopen Atlas to retry them.',
          ),
        ]);
      }
    }
    await uow.recordPostingBatch(PostingBatch(
      id: postingBatchId(doc.docType, doc.id, action),
      sourceType: doc.docType,
      sourceId: doc.id,
      status: PostingStatus.pending,
    ));
  }
}

bool _movesStock(String docType, Map<String, dynamic> payload) =>
    LedgerDerivation.stockSources.contains(docType) ||
    isTrue(payload['update_stock']);

/// The first stock-moving voucher, other than [doc], whose ledger posting
/// failed and is still owed. Recovery replays it at the next start; a stock
/// movement posted before then would have been costed without it (the
/// moving average it met would be wrong), so such movements wait.
Future<({String docType, String id})?> _failedStockPosting(
    DatabaseExecutor db, Document doc) async {
  final rows = await db.rawQuery(
      'SELECT b.source_type, b.source_id, d.payload FROM posting_batches b '
      'LEFT JOIN documents d ON d.doctype = b.source_type AND d.id = b.source_id '
      "WHERE b.status = ? AND b.id LIKE 'LEDGER:%'",
      [PostingStatus.failed.name]);
  for (final r in rows) {
    final type = '${r['source_type']}';
    final id = '${r['source_id']}';
    if (type == doc.docType && id == doc.id) continue;
    Map<String, dynamic> payload = const {};
    try {
      payload = Map<String, dynamic>.from(
          jsonDecode('${r['payload'] ?? '{}'}') as Map);
    } catch (_) {}
    if (_movesStock(type, payload)) return (docType: type, id: id);
  }
  return null;
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
