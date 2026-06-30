/// Pure bank reconciliation matcher (H1 — the heart of the Swift Hub
/// `BankMatchingService`). Given the unreconciled statement lines and the
/// candidate accounting vouchers (each already reduced to a signed amount from
/// the bank account's perspective), it proposes one-to-one matches ranked by
/// confidence. Database-free, so the matching rules can be tested exactly.
library;

/// A statement line awaiting reconciliation. [amount] is signed: positive money
/// in (a deposit), negative money out (a withdrawal).
class BankTxn {
  const BankTxn({
    required this.id,
    required this.date,
    required this.amount,
    this.reference,
    this.description,
  });

  final String id;
  final String date; // ISO yyyy-MM-dd
  final num amount;
  final String? reference;
  final String? description;
}

/// A posted voucher that could clear a statement line. [amount] is signed from
/// the bank account's perspective (a received payment is positive, a paid one
/// negative), so it compares directly with [BankTxn.amount].
class MatchCandidate {
  const MatchCandidate({
    required this.id,
    required this.voucherType,
    required this.date,
    required this.amount,
    this.reference,
  });

  final String id;
  final String voucherType; // Payment Entry / Journal Entry
  final String date; // ISO yyyy-MM-dd
  final num amount;
  final String? reference;
}

/// A proposed reconciliation of one line against one voucher, with a 0–1
/// confidence [score] (amount always agrees; date closeness and a reference
/// hit raise it).
class BankMatch {
  const BankMatch({
    required this.lineId,
    required this.voucherId,
    required this.voucherType,
    required this.score,
  });

  final String lineId;
  final String voucherId;
  final String voucherType;
  final double score;
}

abstract final class BankMatcher {
  /// Proposes matches between [lines] and [candidates]. A pair is only eligible
  /// when the amounts agree (to the cent) and the dates are within
  /// [dateWindowDays]; among eligible pairs the highest-scoring are assigned
  /// greedily so each line and each voucher is used at most once.
  static List<BankMatch> match(
    List<BankTxn> lines,
    List<MatchCandidate> candidates, {
    int dateWindowDays = 5,
  }) {
    final pairs = <_ScoredPair>[];
    for (final line in lines) {
      for (final cand in candidates) {
        final score = _score(line, cand, dateWindowDays);
        if (score != null) pairs.add(_ScoredPair(line.id, cand, score));
      }
    }
    // Best matches first; ties broken deterministically by ids.
    pairs.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      final byLine = a.lineId.compareTo(b.lineId);
      if (byLine != 0) return byLine;
      return a.candidate.id.compareTo(b.candidate.id);
    });

    final usedLines = <String>{};
    final usedVouchers = <String>{};
    final matches = <BankMatch>[];
    for (final p in pairs) {
      if (usedLines.contains(p.lineId) ||
          usedVouchers.contains(p.candidate.id)) {
        continue;
      }
      usedLines.add(p.lineId);
      usedVouchers.add(p.candidate.id);
      matches.add(BankMatch(
        lineId: p.lineId,
        voucherId: p.candidate.id,
        voucherType: p.candidate.voucherType,
        score: p.score,
      ));
    }
    return matches;
  }

  /// The match score for one (line, candidate), or null when ineligible
  /// (amounts disagree or the dates are too far apart). 0.6 for the amount,
  /// up to 0.2 for date closeness, 0.2 for a reference hit.
  static double? _score(BankTxn line, MatchCandidate cand, int windowDays) {
    if (((line.amount - cand.amount).abs()) > 0.005) return null;
    final days = _dayGap(line.date, cand.date);
    if (days == null || days > windowDays) return null;

    var score = 0.6;
    score += 0.2 * (1 - days / windowDays);
    if (_referenceHit(line, cand)) score += 0.2;
    return score;
  }

  static bool _referenceHit(BankTxn line, MatchCandidate cand) {
    final ref = cand.reference?.trim().toLowerCase();
    if (ref == null || ref.isEmpty) return false;
    final lineRef = line.reference?.trim().toLowerCase();
    if (lineRef != null && (lineRef == ref || lineRef.contains(ref))) return true;
    final desc = line.description?.toLowerCase();
    return desc != null && desc.contains(ref);
  }

  /// Whole-day gap between two ISO dates, or null if either is unparseable.
  static int? _dayGap(String a, String b) {
    final da = DateTime.tryParse(a);
    final db = DateTime.tryParse(b);
    if (da == null || db == null) return null;
    return da.difference(db).inDays.abs();
  }
}

class _ScoredPair {
  const _ScoredPair(this.lineId, this.candidate, this.score);
  final String lineId;
  final MatchCandidate candidate;
  final double score;
}
