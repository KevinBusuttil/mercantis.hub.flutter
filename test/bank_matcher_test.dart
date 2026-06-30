import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_hub_app/modules/banking/bank_matcher.dart';

/// H1 — the pure bank reconciliation matcher.
void main() {
  BankTxn txn(String id, num amount,
          {String date = '2026-06-10', String? ref, String? desc}) =>
      BankTxn(id: id, date: date, amount: amount, reference: ref, description: desc);

  MatchCandidate cand(String id, num amount,
          {String date = '2026-06-10', String? ref}) =>
      MatchCandidate(
          id: id, voucherType: 'Payment Entry', date: date, amount: amount, reference: ref);

  test('same-day exact amount matches, and a reference hit scores highest', () {
    final m = BankMatcher.match(
      [txn('L1', 100, ref: 'INV-9')],
      [cand('P1', 100, ref: 'INV-9')],
    );
    expect(m.single.voucherId, 'P1');
    expect(m.single.score, 1.0); // 0.6 amount + 0.2 same-day + 0.2 ref
  });

  test('a mismatched amount is never matched', () {
    expect(BankMatcher.match([txn('L1', 100)], [cand('P1', 101)]), isEmpty);
  });

  test('signs matter: a deposit matches an inbound payment, not an outbound', () {
    expect(BankMatcher.match([txn('L1', 50)], [cand('P1', -50)]), isEmpty);
    expect(BankMatcher.match([txn('L1', -50)], [cand('P1', -50)]).length, 1);
  });

  test('dates beyond the window do not match; closer dates score higher', () {
    expect(
        BankMatcher.match([txn('L1', 100, date: '2026-06-01')],
            [cand('P1', 100, date: '2026-06-20')]),
        isEmpty);

    final near = BankMatcher.match([txn('L1', 100, date: '2026-06-10')],
        [cand('P1', 100, date: '2026-06-12')]); // 2 days
    expect(near.single.score, closeTo(0.6 + 0.2 * (1 - 2 / 5), 1e-9));
  });

  test('a reference found in the description also counts', () {
    final m = BankMatcher.match(
      [txn('L1', 100, desc: 'Payment ref PAY-7 received')],
      [cand('P1', 100, ref: 'PAY-7')],
    );
    expect(m.single.score, 1.0);
  });

  test('assignment is one-to-one, best pair first', () {
    // Two equal-amount lines and two candidates; L1 has the reference, so it
    // takes the referenced candidate and L2 gets the other.
    final m = BankMatcher.match(
      [txn('L1', 100, ref: 'X'), txn('L2', 100)],
      [cand('P1', 100, ref: 'X'), cand('P2', 100)],
    );
    final byLine = {for (final x in m) x.lineId: x.voucherId};
    expect(byLine, {'L1': 'P1', 'L2': 'P2'});
  });

  test('a line with no candidate is simply left out', () {
    final m = BankMatcher.match(
      [txn('L1', 100), txn('L2', 999)],
      [cand('P1', 100)],
    );
    expect(m.map((x) => x.lineId), ['L1']);
  });
}
