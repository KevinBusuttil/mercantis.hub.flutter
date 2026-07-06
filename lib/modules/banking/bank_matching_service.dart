import 'package:mercantis_core/mercantis_core.dart';

import '../../ledger/ledger_values.dart';
import 'bank_matcher.dart';

/// Wires the pure [BankMatcher] to the engine and runs the reconciliation flow:
/// it loads a bank account's unreconciled statement lines and the submitted
/// Payment Entries / Journal Entries that touch the account's ledger account,
/// proposes matches, applies an accepted one by flagging the line Reconciled,
/// and computes the book (ledger) balance vs the statement to drive a
/// `Bank Reconciliation`.
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

    return BankMatcher.match(txns, await _bankMovements(gl),
        dateWindowDays: dateWindowDays);
  }

  /// The book (ledger) balance on the bank account's ledger account from its
  /// submitted vouchers, optionally only those on/before [asOf]. Compared with
  /// the statement closing balance to reconcile.
  Future<num> ledgerBalance(String bankAccountId, {String? asOf}) async {
    final account = await engine.fetch('Bank Account', bankAccountId);
    final gl = asNonEmpty(account?.payload['gl_account']);
    if (gl == null) return 0;
    num bal = 0;
    for (final m in await _bankMovements(gl)) {
      if (asOf == null || m.date.compareTo(asOf) <= 0) bal += m.amount;
    }
    return round2(bal);
  }

  /// Saves a `Bank Reconciliation` for the account: the statement closing
  /// balance against the computed ledger balance, and the difference that must
  /// reach zero to clear (`ledger − statement`).
  Future<Document> reconcile({
    required String bankAccountId,
    required num statementClosingBalance,
    num statementOpeningBalance = 0,
    String? fromDate,
    String? toDate,
  }) async {
    final ledger = await ledgerBalance(bankAccountId, asOf: toDate);
    return engine.save(
      Document(id: '', docType: 'Bank Reconciliation', payload: {
        'bank_account': bankAccountId,
        if (fromDate != null) 'from_date': fromDate,
        if (toDate != null) 'to_date': toDate,
        'statement_opening_balance': statementOpeningBalance,
        'statement_closing_balance': statementClosingBalance,
        'ledger_balance': ledger,
        'difference': round2(ledger - statementClosingBalance),
      }),
      roles,
    );
  }

  /// Every submitted voucher movement across the ledger account [gl], reduced to
  /// a signed amount from the account's perspective: money *into* the account is
  /// positive, *out* is negative. Covers Payment Entries (paid_to / paid_from)
  /// and Journal Entry lines (debit − credit on the account).
  Future<List<MatchCandidate>> _bankMovements(String gl) async {
    final out = <MatchCandidate>[];

    for (final p in await engine.list('Payment Entry', userRoles: roles)) {
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

    // Paid Expenses credit the bank/cash account directly (money out).
    for (final e in await engine.list('Expense', userRoles: roles)) {
      if (e.docStatus != 1) continue;
      if (!isTrue(e.payload['is_paid'])) continue;
      if (asNonEmpty(e.payload['paid_from']) != gl) continue;
      final gross = asNum(e.payload['gross_amount']) != 0
          ? asNum(e.payload['gross_amount'])
          : asNum(e.payload['net_amount']) + asNum(e.payload['tax_amount']);
      if (gross == 0) continue;
      out.add(MatchCandidate(
        id: e.id,
        voucherType: 'Expense',
        date: '${e.payload['posting_date']}',
        amount: -gross,
        reference: asNonEmpty(e.payload['description']),
      ));
    }

    // Journal Entries hold the account in a child table, which list() doesn't
    // hydrate — fetch each submitted JE to read its lines.
    for (final j in await engine.list('Journal Entry', userRoles: roles)) {
      if (j.docStatus != 1) continue;
      final full = await engine.fetch('Journal Entry', j.id) ?? j;
      num signed = 0;
      String? reference;
      for (final row in full.children['accounts'] ?? const <ChildRow>[]) {
        if (asNonEmpty(row.payload['account']) != gl) continue;
        signed += asNum(row.payload['debit']) - asNum(row.payload['credit']);
        reference ??= asNonEmpty(row.payload['reference_name']);
      }
      if (signed == 0) continue;
      out.add(MatchCandidate(
        id: full.id,
        voucherType: 'Journal Entry',
        date: '${full.payload['posting_date']}',
        amount: signed,
        reference: reference,
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

  /// Manually reconciles [lineId] (Phase 4 workbench): with a voucher when
  /// the user knows what cleared it, or bare for lines that need no voucher
  /// (bank fees already journalled, opening rows, ...). Same idempotent
  /// semantics as [apply].
  Future<void> markReconciled(String lineId,
      {String? voucherType, String? voucherId}) async {
    final line = await engine.fetch('Bank Statement Line', lineId);
    if (line == null) return;
    line.payload['status'] = 'Reconciled';
    if (voucherType != null) line.payload['matched_voucher_type'] = voucherType;
    if (voucherId != null) line.payload['matched_voucher'] = voucherId;
    await engine.save(line, roles);
  }
}
