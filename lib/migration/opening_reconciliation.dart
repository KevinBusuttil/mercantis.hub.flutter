import 'package:mercantis_core/mercantis_core.dart';

import '../ledger/ledger_values.dart';
import 'opening_take_on.dart';
import 'take_on_templates.dart';

const _roles = {'System Manager'};

/// The areas an opening position is reconciled in.
enum ReconciliationArea { trialBalance, receivables, payables, stock, bankCash }

/// One compared figure: the previous system's (from the take-on files) and
/// Atlas's (from the posted ledger, as at the opening date).
class ReconciliationLine {
  ReconciliationLine({
    required this.area,
    required this.key,
    required this.label,
    required this.expectedCents,
    required this.actualCents,
    this.expectedQty,
    this.actualQty,
    this.vouchers = const [],
    this.note,
  });

  final ReconciliationArea area;

  /// Account id, party code or `item@warehouse`.
  final String key;
  final String label;
  final int expectedCents;
  final int actualCents;

  /// Stock only.
  final num? expectedQty;
  final num? actualQty;

  /// Drill-down: the Atlas vouchers that make up [actualCents].
  final List<String> vouchers;

  /// Why a line is an exception when the amounts alone do not say.
  final String? note;

  int get differenceCents => actualCents - expectedCents;
  num get differenceQty => (actualQty ?? 0) - (expectedQty ?? 0);

  bool get matches =>
      differenceCents == 0 && _qtyEqual(expectedQty, actualQty) && note == null;
}

/// The opening-position reconciliation (M1.3): what the old system said
/// against what Atlas holds at the opening date, line by line, exact to the
/// cent. Nothing here adjusts anything. A difference is reported, never
/// absorbed.
class OpeningReconciliation {
  OpeningReconciliation(this.openingDate, this.lines);

  final String openingDate;
  final List<ReconciliationLine> lines;

  List<ReconciliationLine> get exceptions =>
      [for (final l in lines) if (!l.matches) l];

  bool get reconciled => exceptions.isEmpty;

  List<ReconciliationLine> area(ReconciliationArea a) =>
      [for (final l in lines) if (l.area == a) l];

  /// A posting date as `YYYY-MM-DD`, whether stored as an ISO string or as
  /// epoch milliseconds (both are accepted by the ledger).
  static String? _day(Object? v) {
    final DateTime? d = v is int
        ? DateTime.fromMillisecondsSinceEpoch(v)
        : v is String
            ? DateTime.tryParse(v.trim())
            : null;
    if (d == null) return null;
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year.toString().padLeft(4, '0')}-${two(d.month)}-${two(d.day)}';
  }

  /// Totals per area as (expected, actual) cents.
  (int, int) totals(ReconciliationArea a) {
    var e = 0, x = 0;
    for (final l in area(a)) {
      e += l.expectedCents;
      x += l.actualCents;
    }
    return (e, x);
  }

  /// Compare [plan] (built from the take-on files; rows that were rejected
  /// still count as the previous system's figures, so anything that did not
  /// make it into Atlas shows as a difference) with the books.
  static Future<OpeningReconciliation> compute(
      DocumentEngine engine, TakeOnPlan plan) async {
    final date = plan.openingDate;
    bool asAt(Document d) {
      final day = _day(d.payload['posting_date']);
      return day != null && day.compareTo(date) <= 0;
    }

    final gl = [
      for (final d in await engine.list('GL Entry', userRoles: _roles))
        if (asAt(d)) d,
    ];
    final accounts = {
      for (final a in await engine.list('Account', userRoles: _roles)) a.id: a,
    };
    final glByAccount = <String, int>{};
    final glVouchers = <String, Set<String>>{};
    final partyBalance = <String, int>{};
    final partyVouchers = <String, Set<String>>{};
    for (final d in gl) {
      final p = d.payload;
      final account = '${p['account'] ?? ''}';
      final net = _cents(asNum(p['debit'])) - _cents(asNum(p['credit']));
      glByAccount[account] = (glByAccount[account] ?? 0) + net;
      (glVouchers[account] ??= {}).add('${p['voucher_type']} ${p['voucher_no']}');
      final party = asNonEmpty(p['party']);
      final type = '${accounts[account]?.payload['account_type'] ?? ''}';
      if (party != null && (type == 'Receivable' || type == 'Payable')) {
        final k = '$type:$party';
        partyBalance[k] = (partyBalance[k] ?? 0) + net;
        (partyVouchers[k] ??= {}).add('${p['voucher_type']} ${p['voucher_no']}');
      }
    }

    String accountLabel(String id) =>
        '${accounts[id]?.payload['account_name'] ?? id}';
    final lines = <ReconciliationLine>[];

    // Trial balance: every account in the file, plus every account Atlas has
    // a balance on that the file does not mention.
    final tb = plan[TakeOnSection.trialBalance]!;
    if (tb.rows.isNotEmpty) {
      final expected = <String, int>{};
      for (final r in tb.rows) {
        if (r.targetId == null) {
          lines.add(ReconciliationLine(
              area: ReconciliationArea.trialBalance,
              key: r.v('account'),
              label: r.v('account'),
              expectedCents: _netCents(r),
              actualCents: 0,
              note: 'Line ${r.line}: ${r.problems.join(' ')}'));
          continue;
        }
        expected[r.targetId!] = (expected[r.targetId!] ?? 0) + r.cents;
      }
      final keys = {
        ...expected.keys,
        for (final e in glByAccount.entries)
          if (e.value != 0) e.key,
      }.where((k) => k != OpeningTakeOn.equityAccount).toList()
        ..sort();
      for (final k in keys) {
        lines.add(ReconciliationLine(
          area: ReconciliationArea.trialBalance,
          key: k,
          label: accountLabel(k),
          expectedCents: expected[k] ?? 0,
          actualCents: glByAccount[k] ?? 0,
          vouchers: (glVouchers[k] ?? const <String>{}).toList()..sort(),
        ));
      }
      // Opening Balance Equity must net to zero once every section is in:
      // anything left there is an opening balance with no counterpart.
      final obe = glByAccount[OpeningTakeOn.equityAccount] ?? 0;
      lines.add(ReconciliationLine(
        area: ReconciliationArea.trialBalance,
        key: OpeningTakeOn.equityAccount,
        label: '${OpeningTakeOn.equityAccount} (must be zero)',
        expectedCents: expected[OpeningTakeOn.equityAccount] ?? 0,
        actualCents: obe,
        vouchers: (glVouchers[OpeningTakeOn.equityAccount] ?? const <String>{})
            .toList()
          ..sort(),
      ));
    }

    // Receivables and payables, per party.
    for (final receivable in const [true, false]) {
      final sp = plan[receivable
          ? TakeOnSection.receivables
          : TakeOnSection.payables]!;
      if (sp.rows.isEmpty) continue;
      final type = receivable ? 'Receivable' : 'Payable';
      final partyKey = receivable ? 'customer_code' : 'supplier_code';
      final expected = <String, int>{};
      for (final r in sp.rows) {
        final party = r.v(partyKey);
        expected[party] = (expected[party] ?? 0) + r.cents;
      }
      final parties = {
        ...expected.keys,
        for (final k in partyBalance.keys)
          if (k.startsWith('$type:') && partyBalance[k] != 0)
            k.substring(type.length + 1),
      }.toList()
        ..sort();
      for (final party in parties) {
        final bal = partyBalance['$type:$party'] ?? 0;
        lines.add(ReconciliationLine(
          area: receivable
              ? ReconciliationArea.receivables
              : ReconciliationArea.payables,
          key: party,
          label: party,
          expectedCents: expected[party] ?? 0,
          // Payables are credit balances; show both sides as amounts owed.
          actualCents: receivable ? bal : -bal,
          vouchers: (partyVouchers['$type:$party'] ?? const <String>{})
              .toList()
            ..sort(),
        ));
      }
    }

    // Stock, per item and warehouse, from the stock ledger.
    final stock = plan[TakeOnSection.openingStock]!;
    if (stock.rows.isNotEmpty) {
      final qty = <String, num>{};
      final value = <String, int>{};
      final vouchers = <String, Set<String>>{};
      for (final d in await engine.list('Stock Ledger Entry', userRoles: _roles)) {
        if (!asAt(d)) continue;
        final p = d.payload;
        final k = '${p['item']}@${p['warehouse']}';
        final q = asNum(p['qty_change']);
        qty[k] = (qty[k] ?? 0) + q;
        value[k] = (value[k] ?? 0) + _cents(q * asNum(p['valuation_rate']));
        (vouchers[k] ??= {}).add('${p['voucher_type']} ${p['voucher_no']}');
      }
      final expQty = <String, num>{};
      final expValue = <String, int>{};
      for (final r in stock.rows) {
        final k = '${r.v('item_code')}@${r.v('warehouse_code')}';
        expQty[k] = (expQty[k] ?? 0) + r.qty;
        expValue[k] = (expValue[k] ?? 0) + r.cents;
      }
      final keys = {
        ...expQty.keys,
        for (final k in qty.keys)
          if (!_qtyEqual(qty[k], 0)) k,
      }.toList()
        ..sort();
      for (final k in keys) {
        lines.add(ReconciliationLine(
          area: ReconciliationArea.stock,
          key: k,
          label: k.replaceFirst('@', ' in '),
          expectedCents: expValue[k] ?? 0,
          actualCents: value[k] ?? 0,
          expectedQty: expQty[k] ?? 0,
          actualQty: qty[k] ?? 0,
          vouchers: (vouchers[k] ?? const <String>{}).toList()..sort(),
        ));
      }
      // The stock sub-ledger must agree with the stock control accounts.
      var stockGl = 0;
      for (final e in glByAccount.entries) {
        if ('${accounts[e.key]?.payload['account_type']}' == 'Stock') {
          stockGl += e.value;
        }
      }
      final stockLedger = value.values.fold(0, (a, b) => a + b);
      lines.add(ReconciliationLine(
        area: ReconciliationArea.stock,
        key: 'stock-ledger-vs-gl',
        label: 'Stock ledger against stock accounts',
        expectedCents: stockGl,
        actualCents: stockLedger,
      ));
    }

    // Bank and cash: the statement against the GL.
    for (final r in plan[TakeOnSection.bankBalances]!.rows) {
      final id = r.targetId;
      lines.add(ReconciliationLine(
        area: ReconciliationArea.bankCash,
        key: id ?? r.v('account'),
        label: id == null ? r.v('account') : accountLabel(id),
        expectedCents: r.cents,
        actualCents: id == null ? 0 : glByAccount[id] ?? 0,
        vouchers: id == null
            ? const []
            : ((glVouchers[id] ?? const <String>{}).toList()..sort()),
        note: r.status == TakeOnRowStatus.rejected
            ? 'Line ${r.line}: ${r.problems.join(' ')}'
            : null,
      ));
    }

    return OpeningReconciliation(date, lines);
  }
}

/// Debit minus credit of a trial-balance row whose account could not be
/// matched (0 where the amounts are unreadable too).
int _netCents(TakeOnRow r) {
  int part(String k) => r.v(k).isEmpty ? 0 : parseCents(r.v(k)) ?? 0;
  return part('debit') - part('credit');
}

int _cents(num v) => (v * 100).round();

/// Quantities are compared at 6 decimals, the precision they are entered at.
bool _qtyEqual(num? a, num? b) =>
    ((a ?? 0) * 1000000).round() == ((b ?? 0) * 1000000).round();
