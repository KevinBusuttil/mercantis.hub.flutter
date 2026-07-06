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

  /// Hydrates one document with its child rows — `_list` alone returns
  /// headers only. Needed by [grossMarginByItem] for invoice lines; reports
  /// that can't fetch (fetch left null) simply skip line-level revenue.
  final Future<Document?> Function(String docType, String id)? _fetch;

  HubAggregatingReports(this._list,
      {ReportValueFormatter? formatter,
      Future<Document?> Function(String docType, String id)? fetch})
      : _formatter = formatter ?? const ReportValueFormatter(),
        _fetch = fetch;

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

  /// Profit & Loss: every Income and Expense account's GL balance (all time —
  /// year-end close zeroes a finished year into Retained Earnings, so the
  /// open period is what remains). Income reads credit−debit, expenses
  /// debit−credit; the closing row is net profit.
  Future<ReportResult> profitAndLoss({Set<String>? userRoles}) async {
    final entries = await _list('GL Entry', userRoles: userRoles);
    final accounts = await _list('Account', userRoles: userRoles);
    final rootByAccount = {
      for (final a in accounts)
        a.id: asNonEmpty(a.payload['root_type']) ?? 'Unclassified',
    };

    final income = <String, num>{};
    final expense = <String, num>{};
    for (final e in entries) {
      final account = asNonEmpty(e.payload['account']);
      if (account == null) continue;
      final net = asNum(e.payload['debit']) - asNum(e.payload['credit']);
      switch (rootByAccount[account]) {
        case 'Income':
          income[account] = (income[account] ?? 0) - net; // credit balance
        case 'Expense':
          expense[account] = (expense[account] ?? 0) + net; // debit balance
      }
    }

    List<String> ordered(Map<String, num> m) => m.keys.toList()
      ..sort((l, r) {
        final byAmount = (m[r] ?? 0).compareTo(m[l] ?? 0);
        return byAmount != 0 ? byAmount : l.compareTo(r);
      });

    final rows = <List<String?>>[];
    num totalIncome = 0, totalExpense = 0;
    for (final a in ordered(income)) {
      totalIncome += income[a]!;
      rows.add(['Income', a, _money(income[a]!)]);
    }
    rows.add(['Income', 'Total income', _money(totalIncome)]);
    for (final a in ordered(expense)) {
      totalExpense += expense[a]!;
      rows.add(['Expenses', a, _money(expense[a]!)]);
    }
    rows.add(['Expenses', 'Total expenses', _money(totalExpense)]);
    rows.add(['', 'Net profit', _money(totalIncome - totalExpense)]);

    return ReportResult(
      reportId: 'profit_and_loss',
      name: 'Profit & Loss',
      columns: const [
        ReportColumn(fieldKey: 'section', label: 'Section'),
        ReportColumn(fieldKey: 'account', label: 'Account'),
        ReportColumn(fieldKey: 'amount', label: 'Amount', type: 'currency'),
      ],
      rows: rows,
    );
  }

  /// Gross margin by item (needs Phase 1B perpetual inventory): revenue from
  /// submitted Sales / POS Invoice lines, COGS from the sale vouchers' costed
  /// Stock Ledger Entries (issues positive, returns negative — cancellations
  /// net out because reversal SLEs stay in the ledger). Service items appear
  /// with revenue and no COGS — 100% margin, correctly.
  Future<ReportResult> grossMarginByItem({Set<String>? userRoles}) async {
    const saleVouchers = {'Sales Invoice', 'Delivery Note', 'POS Invoice'};

    final cogs = <String, num>{};
    for (final s in await _list('Stock Ledger Entry', userRoles: userRoles)) {
      if (!saleVouchers.contains('${s.payload['voucher_type'] ?? ''}')) {
        continue;
      }
      final item = asNonEmpty(s.payload['item']);
      if (item == null) continue;
      cogs[item] = (cogs[item] ?? 0) -
          asNum(s.payload['qty_change']) * asNum(s.payload['valuation_rate']);
    }

    final revenue = <String, num>{};
    for (final docType in const ['Sales Invoice', 'POS Invoice']) {
      for (final header in await _list(docType, userRoles: userRoles)) {
        if (header.docStatus != 1) continue;
        var lines = header.children['items'];
        final fetch = _fetch;
        if ((lines == null || lines.isEmpty) && fetch != null) {
          lines = (await fetch(docType, header.id))?.children['items'];
        }
        for (final line in lines ?? const <ChildRow>[]) {
          final item = asNonEmpty(line.payload['item']);
          if (item == null) continue;
          final amount = line.payload.containsKey('amount')
              ? asNum(line.payload['amount'])
              : asNum(line.payload['qty']) * asNum(line.payload['rate']);
          revenue[item] = (revenue[item] ?? 0) + amount;
        }
      }
    }

    final items = {...revenue.keys, ...cogs.keys}.toList()
      ..sort((l, r) {
        final byMargin = ((revenue[r] ?? 0) - (cogs[r] ?? 0))
            .compareTo((revenue[l] ?? 0) - (cogs[l] ?? 0));
        return byMargin != 0 ? byMargin : l.compareTo(r);
      });

    num totalRevenue = 0, totalCogs = 0;
    final rows = <List<String?>>[];
    for (final item in items) {
      final rev = revenue[item] ?? 0;
      final cost = cogs[item] ?? 0;
      totalRevenue += rev;
      totalCogs += cost;
      rows.add([item, _money(rev), _money(cost), _money(rev - cost), _pct(rev - cost, rev)]);
    }
    rows.add([
      'Total',
      _money(totalRevenue),
      _money(totalCogs),
      _money(totalRevenue - totalCogs),
      _pct(totalRevenue - totalCogs, totalRevenue),
    ]);

    return ReportResult(
      reportId: 'gross_margin_by_item',
      name: 'Gross Margin by Item',
      columns: const [
        ReportColumn(fieldKey: 'item', label: 'Item'),
        ReportColumn(fieldKey: 'revenue', label: 'Revenue', type: 'currency'),
        ReportColumn(fieldKey: 'cogs', label: 'COGS', type: 'currency'),
        ReportColumn(fieldKey: 'margin', label: 'Margin', type: 'currency'),
        ReportColumn(fieldKey: 'margin_pct', label: 'Margin %'),
      ],
      rows: rows,
    );
  }

  /// Stock valuation summary: every Bin folded per item (qty, average rate,
  /// value) with a grand-total row — the totalled statement the flat Bin
  /// register can't give.
  Future<ReportResult> stockValuation({Set<String>? userRoles}) async {
    final bins = await _list('Bin', userRoles: userRoles);
    final qty = <String, num>{};
    final value = <String, num>{};
    for (final b in bins) {
      final item = asNonEmpty(b.payload['item']);
      if (item == null) continue;
      qty[item] = (qty[item] ?? 0) + asNum(b.payload['actual_qty']);
      value[item] = (value[item] ?? 0) + asNum(b.payload['stock_value']);
    }
    final items = value.keys.toList()
      ..sort((l, r) {
        final byValue = (value[r] ?? 0).compareTo(value[l] ?? 0);
        return byValue != 0 ? byValue : l.compareTo(r);
      });

    num totalValue = 0;
    final rows = <List<String?>>[];
    for (final item in items) {
      final q = qty[item] ?? 0;
      final v = value[item] ?? 0;
      totalValue += v;
      rows.add([item, '$q', q == 0 ? '—' : _money(v / q), _money(v)]);
    }
    rows.add(['Total', '', '', _money(totalValue)]);

    return ReportResult(
      reportId: 'stock_valuation',
      name: 'Stock Valuation',
      columns: const [
        ReportColumn(fieldKey: 'item', label: 'Item'),
        ReportColumn(fieldKey: 'qty', label: 'Qty'),
        ReportColumn(fieldKey: 'rate', label: 'Avg rate', type: 'currency'),
        ReportColumn(fieldKey: 'value', label: 'Value', type: 'currency'),
      ],
      rows: rows,
    );
  }

  /// The perpetual-inventory trust check: total Bin stock value vs the GL
  /// balance of every account whose `account_type` is `Stock`. A healthy
  /// ledger shows a difference of zero; anything else means postings and
  /// stock have drifted (e.g. pre-Phase-1B history without a take-on journal).
  Future<ReportResult> stockGlReconciliation({Set<String>? userRoles}) async {
    num binsValue = 0;
    for (final b in await _list('Bin', userRoles: userRoles)) {
      binsValue += asNum(b.payload['stock_value']);
    }

    final accounts = await _list('Account', userRoles: userRoles);
    final inventoryAccounts = {
      for (final a in accounts)
        if ('${a.payload['account_type'] ?? ''}' == 'Stock') a.id,
    };
    num glValue = 0;
    for (final e in await _list('GL Entry', userRoles: userRoles)) {
      if (!inventoryAccounts.contains(asNonEmpty(e.payload['account']))) {
        continue;
      }
      glValue += asNum(e.payload['debit']) - asNum(e.payload['credit']);
    }

    return ReportResult(
      reportId: 'stock_gl_reconciliation',
      name: 'Stock ↔ GL Reconciliation',
      columns: const [
        ReportColumn(fieldKey: 'measure', label: 'Measure'),
        ReportColumn(fieldKey: 'amount', label: 'Amount', type: 'currency'),
      ],
      rows: [
        ['Stock ledger value (all bins)', _money(binsValue)],
        [
          'GL inventory balance (${inventoryAccounts.isEmpty ? 'no Stock-type accounts' : inventoryAccounts.join(', ')})',
          _money(glValue),
        ],
        ['Difference', _money(binsValue - glValue)],
      ],
    );
  }

  /// Balance Sheet: every Asset / Liability / Equity account's GL balance,
  /// plus a "Current period profit" equity line (income − expense balances
  /// not yet closed to Retained Earnings) so the statement always balances:
  /// Assets = Liabilities + Equity.
  Future<ReportResult> balanceSheet({Set<String>? userRoles}) async {
    final entries = await _list('GL Entry', userRoles: userRoles);
    final accounts = await _list('Account', userRoles: userRoles);
    final rootByAccount = {
      for (final a in accounts)
        a.id: asNonEmpty(a.payload['root_type']) ?? 'Unclassified',
    };

    final balances = <String, Map<String, num>>{
      'Asset': {},
      'Liability': {},
      'Equity': {},
    };
    num profit = 0; // credit-positive income − debit-positive expense
    for (final e in entries) {
      final account = asNonEmpty(e.payload['account']);
      if (account == null) continue;
      final net = asNum(e.payload['debit']) - asNum(e.payload['credit']);
      switch (rootByAccount[account]) {
        case 'Asset':
          balances['Asset']![account] =
              (balances['Asset']![account] ?? 0) + net; // debit balance
        case 'Liability':
          balances['Liability']![account] =
              (balances['Liability']![account] ?? 0) - net; // credit balance
        case 'Equity':
          balances['Equity']![account] =
              (balances['Equity']![account] ?? 0) - net;
        case 'Income':
          profit -= net;
        case 'Expense':
          profit -= net; // expenses reduce profit (net is debit-positive)
      }
    }

    final rows = <List<String?>>[];
    final totals = <String, num>{};
    for (final section in const ['Asset', 'Liability', 'Equity']) {
      final byAccount = balances[section]!;
      final ordered = byAccount.keys.toList()
        ..sort((l, r) {
          final byAmount = (byAccount[r] ?? 0).compareTo(byAccount[l] ?? 0);
          return byAmount != 0 ? byAmount : l.compareTo(r);
        });
      num total = 0;
      for (final a in ordered) {
        final v = byAccount[a]!;
        if (v == 0) continue; // silent zero rows just add noise
        total += v;
        rows.add([section, a, _money(v)]);
      }
      if (section == 'Equity' && profit != 0) {
        total += profit;
        rows.add([section, 'Current period profit', _money(profit)]);
      }
      totals[section] = total;
      rows.add([section, 'Total ${section.toLowerCase()}s', _money(total)]);
    }
    rows.add([
      '',
      'Liabilities + equity',
      _money((totals['Liability'] ?? 0) + (totals['Equity'] ?? 0)),
    ]);

    return ReportResult(
      reportId: 'balance_sheet',
      name: 'Balance Sheet',
      columns: const [
        ReportColumn(fieldKey: 'section', label: 'Section'),
        ReportColumn(fieldKey: 'account', label: 'Account'),
        ReportColumn(fieldKey: 'amount', label: 'Amount', type: 'currency'),
      ],
      rows: rows,
    );
  }

  /// Cash Flow overview: every GL movement on Cash/Bank-type accounts,
  /// grouped by the voucher type that caused it — the owner-friendly
  /// "where did the money come from / go" view (a formal indirect-method
  /// statement is a later refinement).
  Future<ReportResult> cashFlowOverview({Set<String>? userRoles}) async {
    final accounts = await _list('Account', userRoles: userRoles);
    final cashAccounts = {
      for (final a in accounts)
        if (const {'Cash', 'Bank'}
            .contains('${a.payload['account_type'] ?? ''}'))
          a.id,
    };

    final inflow = <String, num>{};
    final outflow = <String, num>{};
    for (final e in await _list('GL Entry', userRoles: userRoles)) {
      if (!cashAccounts.contains(asNonEmpty(e.payload['account']))) continue;
      final voucher = asNonEmpty(e.payload['voucher_type']) ?? 'Other';
      final net = asNum(e.payload['debit']) - asNum(e.payload['credit']);
      if (net >= 0) {
        inflow[voucher] = (inflow[voucher] ?? 0) + net;
      } else {
        outflow[voucher] = (outflow[voucher] ?? 0) - net;
      }
    }

    final vouchers = {...inflow.keys, ...outflow.keys}.toList()
      ..sort((l, r) {
        num netOf(String v) => (inflow[v] ?? 0) - (outflow[v] ?? 0);
        final byNet = netOf(r).compareTo(netOf(l));
        return byNet != 0 ? byNet : l.compareTo(r);
      });

    num totalIn = 0, totalOut = 0;
    final rows = <List<String?>>[];
    for (final v in vouchers) {
      final i = inflow[v] ?? 0;
      final o = outflow[v] ?? 0;
      totalIn += i;
      totalOut += o;
      rows.add([v, _money(i), _money(o), _money(i - o)]);
    }
    rows.add(['Net cash movement', _money(totalIn), _money(totalOut), _money(totalIn - totalOut)]);

    return ReportResult(
      reportId: 'cash_flow_overview',
      name: 'Cash Flow Overview',
      columns: const [
        ReportColumn(fieldKey: 'source', label: 'Source'),
        ReportColumn(fieldKey: 'in', label: 'Money in', type: 'currency'),
        ReportColumn(fieldKey: 'out', label: 'Money out', type: 'currency'),
        ReportColumn(fieldKey: 'net', label: 'Net', type: 'currency'),
      ],
      rows: rows,
    );
  }

  /// Project profitability (Phase 6): per project — invoiced value (submitted
  /// Sales Invoices linked to the project), project costs (submitted Expenses
  /// linked to it, net), logged hours, the value of still-unbilled billable
  /// time, and margin = invoiced − costs.
  Future<ReportResult> projectProfitability({Set<String>? userRoles}) async {
    final projects = await _list('Project', userRoles: userRoles);
    final rateByProject = {
      for (final p in projects)
        p.id: asNum(p.payload['default_billing_rate']),
    };
    final nameByProject = {
      for (final p in projects)
        p.id: asNonEmpty(p.payload['project_name']) ?? p.id,
    };

    final invoiced = <String, num>{};
    for (final si in await _list('Sales Invoice', userRoles: userRoles)) {
      if (si.docStatus != 1) continue;
      final project = asNonEmpty(si.payload['project']);
      if (project == null) continue;
      invoiced[project] = (invoiced[project] ?? 0) + asNum(si.payload['grand_total']);
    }

    final costs = <String, num>{};
    for (final e in await _list('Expense', userRoles: userRoles)) {
      if (e.docStatus != 1) continue;
      final project = asNonEmpty(e.payload['project']);
      if (project == null) continue;
      costs[project] = (costs[project] ?? 0) + asNum(e.payload['net_amount']);
    }

    final hours = <String, num>{};
    final unbilled = <String, num>{};
    for (final t in await _list('Timesheet', userRoles: userRoles)) {
      final project = asNonEmpty(t.payload['project']);
      if (project == null) continue;
      final h = asNum(t.payload['hours']);
      hours[project] = (hours[project] ?? 0) + h;
      if (isTrue(t.payload['billable']) && !isTrue(t.payload['billed'])) {
        final rate = asNum(t.payload['billing_rate']) != 0
            ? asNum(t.payload['billing_rate'])
            : (rateByProject[project] ?? 0);
        unbilled[project] = (unbilled[project] ?? 0) + h * rate;
      }
    }

    final ids = nameByProject.keys.toList()
      ..sort((l, r) {
        num marginOf(String p) => (invoiced[p] ?? 0) - (costs[p] ?? 0);
        final byMargin = marginOf(r).compareTo(marginOf(l));
        return byMargin != 0 ? byMargin : l.compareTo(r);
      });

    final rows = <List<String?>>[
      for (final id in ids)
        [
          nameByProject[id],
          _money(invoiced[id] ?? 0),
          _money(costs[id] ?? 0),
          '${hours[id] ?? 0}',
          _money(unbilled[id] ?? 0),
          _money((invoiced[id] ?? 0) - (costs[id] ?? 0)),
        ],
    ];

    return ReportResult(
      reportId: 'project_profitability',
      name: 'Project Profitability',
      columns: const [
        ReportColumn(fieldKey: 'project', label: 'Project'),
        ReportColumn(fieldKey: 'invoiced', label: 'Invoiced', type: 'currency'),
        ReportColumn(fieldKey: 'costs', label: 'Costs', type: 'currency'),
        ReportColumn(fieldKey: 'hours', label: 'Hours'),
        ReportColumn(fieldKey: 'unbilled', label: 'Unbilled time', type: 'currency'),
        ReportColumn(fieldKey: 'margin', label: 'Margin', type: 'currency'),
      ],
      rows: rows,
    );
  }

  String _pct(num part, num whole) =>
      whole == 0 ? '—' : '${(part / whole * 100).toStringAsFixed(1)}%';

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
