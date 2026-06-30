import 'package:mercantis_core/mercantis_core.dart';

import '../../ledger/ledger_values.dart';
import 'bank_matcher.dart';

/// Wires the pure [BankMatcher] to the engine: it loads a bank account's
/// unreconciled statement lines and the submitted Payment Entries that touch
/// the account's ledger account, proposes matches, and applies an accepted one
/// by flagging the line Reconciled against its voucher.
///
/// (Journal Entry candidates are a planned follow-up; the matcher already
/// supports them — only the candidate loader here is Payment-Entry-only.)
class BankMatchingService {
  BankMatchingService({required this.engine, this.roles = const {'System Manager'}});

  final DocumentEngine engine;
  final Set<String> roles;

  /// Proposed matches for [bankAccountId]'s unreconciled lines against its
  /// submitted payments, ranked by confidence.
  Future<List<BankMatch>> suggest(String bankAccountId,
      {int dateWindowDays = 5}) async {
    final account = await engine.fetch('Bank Account', bankAccountId);
    final gl = asNonEmpty(account?.payload['gl_account']);
    if (gl == null) return const [];

    final lines = await engine.list('Bank Statement Line',
        filters: {'bank_account': bankAccountId}, userRoles: roles);
    final txns = [
      for (final l in lines)
        if (l.payload['status'] == 'Unreconciled')
          BankTxn(
            id: l.id,
            date: '${l.payload['posting_date']}',
            // Recompute from deposit/withdrawal so a stale `amount` can't lie.
            amount: asNum(l.payload['deposit']) - asNum(l.payload['withdrawal']),
            reference: asNonEmpty(l.payload['reference_number']),
            description: asNonEmpty(l.payload['description']),
          ),
    ];
    if (txns.isEmpty) return const [];

    return BankMatcher.match(txns, await _paymentCandidates(gl),
        dateWindowDays: dateWindowDays);
  }

  /// Submitted Payment Entries that move money across the ledger account [gl],
  /// reduced to a signed amount from the account's perspective: a payment
  /// *into* the account (paid_to) is positive, one *out of* it (paid_from) is
  /// negative.
  Future<List<MatchCandidate>> _paymentCandidates(String gl) async {
    final payments = await engine.list('Payment Entry', userRoles: roles);
    final out = <MatchCandidate>[];
    for (final p in payments) {
      if (p.docStatus != 1) continue;
      final amount = asNum(p.payload['paid_amount']);
      final num signed;
      if (asNonEmpty(p.payload['paid_to']) == gl) {
        signed = amount;
      } else if (asNonEmpty(p.payload['paid_from']) == gl) {
        signed = -amount;
      } else {
        continue;
      }
      out.add(MatchCandidate(
        id: p.id,
        voucherType: 'Payment Entry',
        date: '${p.payload['posting_date']}',
        amount: signed,
        reference: asNonEmpty(p.payload['reference_no']),
      ));
    }
    return out;
  }

  /// Accepts a proposed [match]: flags the statement line Reconciled and records
  /// which voucher cleared it. Idempotent — re-applying the same match is a
  /// no-op beyond re-stamping the fields.
  Future<void> apply(BankMatch match) async {
    final line = await engine.fetch('Bank Statement Line', match.lineId);
    if (line == null) return;
    line.payload['status'] = 'Reconciled';
    line.payload['matched_voucher_type'] = match.voucherType;
    line.payload['matched_voucher'] = match.voucherId;
    await engine.save(line, roles);
  }
}
