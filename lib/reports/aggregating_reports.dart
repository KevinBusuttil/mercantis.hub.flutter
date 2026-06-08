import 'package:mercantis_core/mercantis_core.dart';

import '../ledger/ledger_values.dart';

/// App-side aggregating financial reports (Trial Balance, AR/AP aging).
///
/// The Core [ReportEngine] only does flat select + format over a single
/// DocType; grouping/summing reports are layered on top here, post-processing
/// the documents the store returns — the same pattern the `DashboardEngine`
/// uses. Each method returns a plain [ReportResult] so the existing report
/// viewer renders it unchanged.
///
/// Ported from the Swift `HubReports` Trial Balance / Customer Aging; AP aging
/// is the symmetric supplier report (the Swift app only shipped AR aging).
class HubAggregatingReports {
  final DocumentListFn _list;
  final ReportValueFormatter _formatter;

  HubAggregatingReports(this._list, {ReportValueFormatter? formatter})
      : _formatter = formatter ?? const ReportValueFormatter();

  /// Root-type display/sort order; anything else sorts last as "Unclassified".
  static const _rootOrder = ['Asset', 'Liability', 'Equity', 'Income', 'Expense', 'Unclassified'];

  static const _tbColumns = [
    ReportColumn(fieldKey: 'root_type', label: 'Type'),
    ReportColumn(fieldKey: 'account', label: 'Account'),
    ReportColumn(fieldKey: 'debit', label: 'Debit', type: 'currency'),
    ReportColumn(fieldKey: 'credit', label: 'Credit', type: 'currency'),
    ReportColumn(fieldKey: 'balance', label: 'Balance', type: 'currency'),
  ];

  /// Trial Balance: sum every GL Entry's debit/credit per account, classified by
  /// the Account master's `root_type`. Reversal rows are **included** (their
  /// debit/credit are already swapped), so a healthy ledger's Debit and Credit
  /// totals are equal — the proof the books balance. A grand-total row is
  /// appended.
  Future<ReportResult> trialBalance({Set<String>? userRoles}) async {
    final entries = await _list('GL Entry', userRoles: userRoles);
    final accounts = await _list('Account', userRoles: userRoles);
    final rootByAccount = {
      for (final a in accounts) a.id: asNonEmpty(a.payload['root_type']) ?? 'Unclassified',
    };

    final totals = <String, _DebitCredit>{};
    for (final e in entries) {
      final account = asNonEmpty(e.payload['account']);
      if (account == null) continue;
      final t = totals.putIfAbsent(account, _DebitCredit.new);
      t.debit += asNum(e.payload['debit']);
      t.credit += asNum(e.payload['credit']);
    }

    int rootIndex(String account) {
      final i = _rootOrder.indexOf(rootByAccount[account] ?? 'Unclassified');
      return i == -1 ? _rootOrder.length : i;
    }

    final ordered = totals.keys.toList()
      ..sort((l, r) {
        final byRoot = rootIndex(l).compareTo(rootIndex(r));
        return byRoot != 0 ? byRoot : l.compareTo(r);
      });

    num totalDebit = 0, totalCredit = 0;
    final rows = <List<String?>>[];
    for (final account in ordered) {
      final t = totals[account]!;
      totalDebit += t.debit;
      totalCredit += t.credit;
      rows.add([
        rootByAccount[account] ?? 'Unclassified',
        account,
        _money(t.debit),
        _money(t.credit),
        _money(t.debit - t.credit),
      ]);
    }
    rows.add(['', 'Total', _money(totalDebit), _money(totalCredit), _money(totalDebit - totalCredit)]);

    return ReportResult(reportId: 'trial_balance', name: 'Trial Balance', columns: _tbColumns, rows: rows);
  }

  /// Accounts Receivable aging — open Sales Invoices bucketed by how overdue
  /// they are relative to [asOf] (default: today).
  Future<ReportResult> arAging({DateTime? asOf, Set<String>? userRoles}) => _aging(
        docType: 'Sales Invoice',
        partyField: 'customer',
        partyLabel: 'Customer',
        reportId: 'ar_aging',
        name: 'AR Aging',
        asOf: asOf,
        userRoles: userRoles,
      );

  /// Accounts Payable aging — open Purchase Invoices, symmetric to [arAging].
  Future<ReportResult> apAging({DateTime? asOf, Set<String>? userRoles}) => _aging(
        docType: 'Purchase Invoice',
        partyField: 'supplier',
        partyLabel: 'Supplier',
        reportId: 'ap_aging',
        name: 'AP Aging',
        asOf: asOf,
        userRoles: userRoles,
      );

  Future<ReportResult> _aging({
    required String docType,
    required String partyField,
    required String partyLabel,
    required String reportId,
    required String name,
    DateTime? asOf,
    Set<String>? userRoles,
  }) async {
    final today = _dateOnly(asOf ?? DateTime.now());
    final invoices = await _list(docType, userRoles: userRoles);

    final byParty = <String, _AgingBuckets>{};
    for (final inv in invoices) {
      if (inv.docStatus != 1) continue; // only submitted
      final outstanding = asNum(inv.payload['outstanding_amount']);
      if (outstanding <= 0) continue; // skip fully paid / unposted
      final party = asNonEmpty(inv.payload[partyField]) ?? '(unknown)';
      final due = _asDate(inv.payload['due_date']) ?? _asDate(inv.payload['posting_date']) ?? today;
      final days = today.difference(due).inDays; // future due → ≤0 → current
      byParty.putIfAbsent(party, _AgingBuckets.new).add(days, outstanding);
    }

    final ordered = byParty.entries.toList()
      ..sort((a, b) => b.value.total.compareTo(a.value.total));

    final total = _AgingBuckets();
    final rows = <List<String?>>[];
    for (final e in ordered) {
      final b = e.value;
      total.merge(b);
      rows.add([e.key, _money(b.b0), _money(b.b1), _money(b.b2), _money(b.b3), _money(b.total)]);
    }
    rows.add(['Total', _money(total.b0), _money(total.b1), _money(total.b2), _money(total.b3), _money(total.total)]);

    return ReportResult(
      reportId: reportId,
      name: name,
      columns: [
        ReportColumn(fieldKey: 'party', label: partyLabel),
        const ReportColumn(fieldKey: 'b0', label: '0–30 days', type: 'currency'),
        const ReportColumn(fieldKey: 'b1', label: '31–60 days', type: 'currency'),
        const ReportColumn(fieldKey: 'b2', label: '61–90 days', type: 'currency'),
        const ReportColumn(fieldKey: 'b3', label: '90+ days', type: 'currency'),
        const ReportColumn(fieldKey: 'total', label: 'Outstanding', type: 'currency'),
      ],
      rows: rows,
    );
  }

  String? _money(num value) => _formatter.format(value, type: 'currency');

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

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

class _DebitCredit {
  num debit = 0;
  num credit = 0;
}

class _AgingBuckets {
  num b0 = 0; // 0–30
  num b1 = 0; // 31–60
  num b2 = 0; // 61–90
  num b3 = 0; // 90+

  num get total => b0 + b1 + b2 + b3;

  void add(int days, num amount) {
    if (days <= 30) {
      b0 += amount;
    } else if (days <= 60) {
      b1 += amount;
    } else if (days <= 90) {
      b2 += amount;
    } else {
      b3 += amount;
    }
  }

  void merge(_AgingBuckets other) {
    b0 += other.b0;
    b1 += other.b1;
    b2 += other.b2;
    b3 += other.b3;
  }
}
