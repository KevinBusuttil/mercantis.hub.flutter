import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

import '../ledger/ledger_values.dart';

/// The owner's daily questions, answered live from the document store
/// (Phase 1A): how much cash do I have, who's overdue, what bills are due,
/// how is this month going, and how much VAT am I sitting on. Pure over an
/// injected list function (same harness as HubAggregatingReports) so every
/// number is testable without a database.
class OwnerKpi {
  const OwnerKpi({required this.amount, this.caption});

  final num amount;

  /// Optional context line ("3 invoices", "quarter to date").
  final String? caption;
}

class OwnerKpis {
  OwnerKpis(this._list, {DateTime Function()? now})
      : _now = now ?? DateTime.now;

  final DocumentListFn _list;
  final DateTime Function() _now;

  /// Cash position: GL balance of every account whose type is Cash or Bank.
  Future<OwnerKpi> cashPosition({Set<String>? userRoles}) async {
    final accounts = await _list('Account', userRoles: userRoles);
    final cashAccounts = {
      for (final a in accounts)
        if (const {'Cash', 'Bank'}.contains('${a.payload['account_type'] ?? ''}'))
          a.id,
    };
    num balance = 0;
    for (final e in await _list('GL Entry', userRoles: userRoles)) {
      if (!cashAccounts.contains(asNonEmpty(e.payload['account']))) continue;
      balance += asNum(e.payload['debit']) - asNum(e.payload['credit']);
    }
    return OwnerKpi(
        amount: balance,
        caption: cashAccounts.isEmpty ? 'no cash/bank accounts' : null);
  }

  /// Total outstanding on submitted Sales Invoices past their due date.
  Future<OwnerKpi> overdueReceivables({Set<String>? userRoles}) =>
      _dueInvoices('Sales Invoice',
          overdueOnly: true, horizonDays: 0, userRoles: userRoles);

  /// Total outstanding on submitted Purchase Invoices due within
  /// [horizonDays] (default a week) or already overdue.
  Future<OwnerKpi> billsDue({int horizonDays = 7, Set<String>? userRoles}) =>
      _dueInvoices('Purchase Invoice',
          overdueOnly: false, horizonDays: horizonDays, userRoles: userRoles);

  Future<OwnerKpi> _dueInvoices(String docType,
      {required bool overdueOnly,
      required int horizonDays,
      Set<String>? userRoles}) async {
    final today = _today();
    final cutoff = today.add(Duration(days: horizonDays));
    num total = 0;
    var count = 0;
    for (final inv in await _list(docType, userRoles: userRoles)) {
      if (inv.docStatus != 1) continue;
      final outstanding = asNum(inv.payload['outstanding_amount']);
      if (outstanding <= 0) continue;
      final due = _asDate(inv.payload['due_date']) ??
          _asDate(inv.payload['posting_date']);
      if (due == null) continue;
      final qualifies =
          overdueOnly ? due.isBefore(today) : !due.isAfter(cutoff);
      if (!qualifies) continue;
      total += outstanding;
      count++;
    }
    return OwnerKpi(
        amount: total,
        caption: count == 0
            ? (overdueOnly ? 'nothing overdue' : 'nothing due')
            : '$count invoice${count == 1 ? '' : 's'}');
  }

  /// Grand total of this calendar month's submitted Sales + POS invoices
  /// (returns net out through their negative totals).
  Future<OwnerKpi> salesThisMonth({Set<String>? userRoles}) async {
    final today = _today();
    final monthStart = DateTime(today.year, today.month);
    num total = 0;
    for (final docType in const ['Sales Invoice', 'POS Invoice']) {
      for (final inv in await _list(docType, userRoles: userRoles)) {
        if (inv.docStatus != 1) continue;
        final posted = _asDate(inv.payload['posting_date']);
        if (posted == null ||
            posted.isBefore(monthStart) ||
            posted.isAfter(today)) {
          continue;
        }
        total += asNum(inv.payload['grand_total']);
      }
    }
    return OwnerKpi(amount: total, caption: 'month to date');
  }

  /// Net VAT position for the current quarter: output tax collected minus
  /// input tax paid, from the Tax Transaction subledger (reversals net out).
  /// Positive = owed to the tax authority.
  Future<OwnerKpi> vatEstimate({Set<String>? userRoles}) async {
    final today = _today();
    final quarterStart =
        DateTime(today.year, ((today.month - 1) ~/ 3) * 3 + 1);
    num net = 0;
    for (final t in await _list('Tax Transaction', userRoles: userRoles)) {
      final posted = _asDate(t.payload['posting_date']);
      if (posted == null ||
          posted.isBefore(quarterStart) ||
          posted.isAfter(today)) {
        continue;
      }
      final amount = asNum(t.payload['tax_amount']);
      switch ('${t.payload['party_type'] ?? ''}') {
        case 'Customer':
          net += amount; // output VAT collected
        case 'Supplier':
          net -= amount; // input VAT reclaimable
      }
    }
    return OwnerKpi(amount: net, caption: 'quarter to date');
  }

  DateTime _today() {
    final n = _now();
    return DateTime(n.year, n.month, n.day);
  }

  static DateTime? _asDate(dynamic v) {
    DateTime? d;
    if (v is DateTime) {
      d = v;
    } else if (v is int) {
      d = DateTime.fromMillisecondsSinceEpoch(v);
    } else if (v is String && v.isNotEmpty) {
      d = DateTime.tryParse(v);
    }
    return d == null ? null : DateTime(d.year, d.month, d.day);
  }
}

final ownerKpisProvider = FutureProvider<OwnerKpis>((ref) async {
  final engine = await ref.watch(documentEngineProvider.future);
  return OwnerKpis(engine.list);
});

final cashPositionKpiProvider = FutureProvider.autoDispose<OwnerKpi>((ref) async {
  final kpis = await ref.watch(ownerKpisProvider.future);
  return kpis.cashPosition(userRoles: ref.watch(currentUserProvider).roles);
});

final overdueKpiProvider = FutureProvider.autoDispose<OwnerKpi>((ref) async {
  final kpis = await ref.watch(ownerKpisProvider.future);
  return kpis.overdueReceivables(
      userRoles: ref.watch(currentUserProvider).roles);
});

final billsDueKpiProvider = FutureProvider.autoDispose<OwnerKpi>((ref) async {
  final kpis = await ref.watch(ownerKpisProvider.future);
  return kpis.billsDue(userRoles: ref.watch(currentUserProvider).roles);
});

final salesMonthKpiProvider = FutureProvider.autoDispose<OwnerKpi>((ref) async {
  final kpis = await ref.watch(ownerKpisProvider.future);
  return kpis.salesThisMonth(userRoles: ref.watch(currentUserProvider).roles);
});

final vatEstimateKpiProvider = FutureProvider.autoDispose<OwnerKpi>((ref) async {
  final kpis = await ref.watch(ownerKpisProvider.future);
  return kpis.vatEstimate(userRoles: ref.watch(currentUserProvider).roles);
});
