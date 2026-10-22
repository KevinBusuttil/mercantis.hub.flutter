import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

import 'money_format.dart';

/// Whether a figure is good, bad or neutral news — drives colour and the
/// words screen readers hear, never the number itself.
enum SummaryTone { neutral, good, bad }

class SummaryFigure {
  const SummaryFigure(this.label, this.value, {this.tone = SummaryTone.neutral});
  final String label;
  final String value;
  final SummaryTone tone;
}

/// One line of a summary group; [location] drills down to the records.
class SummaryLine {
  const SummaryLine(this.label, this.value, {this.detail, this.location});
  final String label;
  final String value;
  final String? detail;
  final String? location;
}

class SummaryGroup {
  const SummaryGroup(this.title, this.lines, {this.total, this.more = 0});
  final String title;
  final List<SummaryLine> lines;
  final SummaryLine? total;

  /// Lines left out of a long group (shown in the detailed table).
  final int more;
}

/// The phone-first reading of a statement: headline figures, then what needs
/// attention, then the main groups with drill-down. The detailed table stays
/// one tap away. Derived only from the [ReportResult] — the same numbers the
/// table shows, never recomputed.
class ReportSummary {
  const ReportSummary({
    required this.figures,
    this.exceptions = const [],
    this.groups = const [],
    this.allClear,
  });

  final List<SummaryFigure> figures;
  final List<String> exceptions;
  final List<SummaryGroup> groups;

  /// Said when there is nothing to flag ("Everyone is within 30 days").
  final String? allClear;
}

const _groupLimit = 6;

/// The summary for [r], or null when the report has no summary form (it is
/// shown as a table).
ReportSummary? summariseReport(ReportResult r) => switch (r.reportId) {
      'profit_and_loss' => _profitAndLoss(r),
      'balance_sheet' => _balanceSheet(r),
      'cash_flow_overview' => _cashFlow(r),
      'ar_aging' => _aging(r, receivable: true),
      'ap_aging' => _aging(r, receivable: false),
      'gross_margin_by_item' => _grossMargin(r),
      'stock_valuation' => _stockValuation(r),
      'project_profitability' => _projects(r),
      _ => null,
    };

num _n(String? cell) => parseAmount(cell) ?? 0;

SummaryGroup _group(String title, List<SummaryLine> lines, {SummaryLine? total}) =>
    SummaryGroup(
      title,
      lines.take(_groupLimit).toList(),
      total: total,
      more: lines.length > _groupLimit ? lines.length - _groupLimit : 0,
    );

String _ledger(String account) =>
    '/w/finance/account-ledger?account=${Uri.encodeQueryComponent(account)}';

ReportSummary _profitAndLoss(ReportResult r) {
  num income = 0, expenses = 0;
  final inc = <SummaryLine>[], exp = <SummaryLine>[];
  for (final row in r.rows) {
    final (section, account, amount) = (row[0], row[1] ?? '', _n(row[2]));
    if (account == 'Total income') {
      income = amount;
    } else if (account == 'Total expenses') {
      expenses = amount;
    } else if (section == 'Income') {
      inc.add(SummaryLine(account, formatMoney(amount), location: _ledger(account)));
    } else if (section == 'Expenses') {
      exp.add(SummaryLine(account, formatMoney(amount), location: _ledger(account)));
    }
  }
  final profit = income - expenses;
  final margin = income == 0 ? null : profit / income * 100;
  return ReportSummary(
    figures: [
      SummaryFigure(profit < 0 ? 'Loss' : 'Profit', formatMoney(profit),
          tone: profit < 0 ? SummaryTone.bad : SummaryTone.good),
      SummaryFigure('Income', formatMoney(income)),
      SummaryFigure('Expenses', formatMoney(expenses)),
      if (margin != null)
        SummaryFigure('Margin', '${margin.toStringAsFixed(1)}%',
            tone: margin < 0 ? SummaryTone.bad : SummaryTone.neutral),
    ],
    exceptions: [
      if (profit < 0)
        'Expenses are ${formatMoney(-profit)} more than income this period.',
      if (income == 0 && expenses > 0) 'No income has been posted yet.',
    ],
    groups: [
      _group('Where the money came from', inc),
      _group('Where it went', exp),
    ],
  );
}

ReportSummary _balanceSheet(ReportResult r) {
  final totals = <String, num>{};
  final lines = <String, List<SummaryLine>>{};
  num liabilitiesAndEquity = 0;
  for (final row in r.rows) {
    final (section, account, amount) = (row[0] ?? '', row[1] ?? '', _n(row[2]));
    if (account == 'Liabilities + equity') {
      liabilitiesAndEquity = amount;
    } else if (account.startsWith('Total ')) {
      totals[section] = amount;
    } else {
      (lines[section] ??= []).add(SummaryLine(account, formatMoney(amount),
          location: account == 'Current period profit' ? null : _ledger(account)));
    }
  }
  final assets = totals['Asset'] ?? 0;
  final gap = assets - liabilitiesAndEquity;
  return ReportSummary(
    figures: [
      SummaryFigure('You own', formatMoney(assets)),
      SummaryFigure('You owe', formatMoney(totals['Liability'] ?? 0)),
      SummaryFigure('Net worth', formatMoney(totals['Equity'] ?? 0),
          tone: (totals['Equity'] ?? 0) < 0 ? SummaryTone.bad : SummaryTone.neutral),
    ],
    exceptions: [
      if (gap.abs() >= 0.01)
        'Assets and liabilities + equity differ by ${formatMoney(gap.abs())}. '
            'Your accountant can trace this in the Trial Balance.',
    ],
    allClear: gap.abs() < 0.01 ? 'The balance sheet balances.' : null,
    groups: [
      _group('What you own', lines['Asset'] ?? const []),
      _group('What you owe', lines['Liability'] ?? const []),
      _group('Owner\'s equity', lines['Equity'] ?? const []),
    ],
  );
}

ReportSummary _cashFlow(ReportResult r) {
  num inTotal = 0, outTotal = 0;
  final lines = <SummaryLine>[];
  for (final row in r.rows) {
    if (row[0] == 'Net cash movement') {
      inTotal = _n(row[1]);
      outTotal = _n(row[2]);
    } else {
      lines.add(SummaryLine(row[0] ?? '', formatMoney(_n(row[3])),
          detail: 'In ${formatMoney(_n(row[1]))} · out ${formatMoney(_n(row[2]))}'));
    }
  }
  final net = inTotal - outTotal;
  return ReportSummary(
    figures: [
      SummaryFigure('Net change', formatMoney(net),
          tone: net < 0 ? SummaryTone.bad : SummaryTone.good),
      SummaryFigure('Money in', formatMoney(inTotal)),
      SummaryFigure('Money out', formatMoney(outTotal)),
    ],
    exceptions: [
      if (net < 0) 'More money went out than came in (${formatMoney(-net)}).',
    ],
    groups: [_group('By source', lines)],
  );
}

ReportSummary _aging(ReportResult r, {required bool receivable}) {
  final docType = receivable ? 'Sales Invoice' : 'Purchase Invoice';
  final partyKey = receivable ? 'customer' : 'supplier';
  num total = 0, over30 = 0, over90 = 0;
  final lines = <SummaryLine>[];
  final late = <String>[];
  for (final (i, row) in r.rows.indexed) {
    final party = row[0] ?? '';
    final (b1, b2, b3, all) = (_n(row[2]), _n(row[3]), _n(row[4]), _n(row[5]));
    if (i == r.rows.length - 1) {
      // The last row is the total (a party may itself be called "Total").
      total = all;
      over30 = b1 + b2 + b3;
      over90 = b3;
      continue;
    }
    if (b3 > 0) late.add('$party: ${formatMoney(b3)} more than 90 days late');
    final overdue = b1 + b2 + b3;
    lines.add(SummaryLine(
      party,
      formatMoney(all),
      detail: overdue > 0
          ? '${formatMoney(overdue)} more than 30 days late'
          : 'None more than 30 days late',
      location: listLocation(docType,
          title: receivable ? 'Invoices · $party' : 'Bills · $party',
          filter: {partyKey: party}),
    ));
  }
  return ReportSummary(
    figures: [
      SummaryFigure(receivable ? 'Owed to you' : 'You owe', formatMoney(total)),
      SummaryFigure('30+ days late', formatMoney(over30),
          tone: over30 > 0 ? SummaryTone.bad : SummaryTone.good),
      SummaryFigure('90+ days late', formatMoney(over90),
          tone: over90 > 0 ? SummaryTone.bad : SummaryTone.good),
    ],
    exceptions: late,
    allClear: late.isEmpty
        ? (receivable
            ? 'No customer is more than 90 days late.'
            : 'No supplier bill is more than 90 days old.')
        : null,
    groups: [
      _group(receivable ? 'Who owes you' : 'Who you owe', lines),
    ],
  );
}

ReportSummary _grossMargin(ReportResult r) {
  final lines = <SummaryLine>[];
  final negative = <String>[];
  List<String?>? total;
  for (final row in r.rows) {
    if (row[0] == 'Total') {
      total = row;
      continue;
    }
    final margin = _n(row[3]);
    if (margin < 0) negative.add('${row[0]} sells below cost (${formatMoney(margin)}).');
    lines.add(SummaryLine(row[0] ?? '', formatMoney(margin),
        detail: 'Sales ${formatMoney(_n(row[1]))} · margin ${row[4] ?? '—'}',
        location: '/form/Item/${Uri.encodeComponent(row[0] ?? '')}'));
  }
  lines.sort((a, b) => (parseAmount(b.value) ?? 0).compareTo(parseAmount(a.value) ?? 0));
  return ReportSummary(
    figures: [
      SummaryFigure('Gross margin', formatMoney(_n(total?[3]))),
      SummaryFigure('Margin %', total?[4] ?? '—'),
      SummaryFigure('Sales', formatMoney(_n(total?[1]))),
    ],
    exceptions: negative,
    groups: [_group('By product', lines)],
  );
}

ReportSummary _stockValuation(ReportResult r) {
  final lines = <SummaryLine>[];
  final negative = <String>[];
  num total = 0;
  for (final row in r.rows) {
    if (row[0] == 'Total') {
      total = _n(row[3]);
      continue;
    }
    final qty = parseAmount(row[1]) ?? 0;
    if (qty < 0) negative.add('${row[0]} shows ${row[1]} in stock — count it.');
    lines.add(SummaryLine(row[0] ?? '', formatMoney(_n(row[3])),
        detail: '${row[1]} on hand',
        location: '/form/Item/${Uri.encodeComponent(row[0] ?? '')}'));
  }
  lines.sort((a, b) => (parseAmount(b.value) ?? 0).compareTo(parseAmount(a.value) ?? 0));
  return ReportSummary(
    figures: [
      SummaryFigure('Stock value', formatMoney(total)),
      SummaryFigure('Products', '${lines.length}'),
    ],
    exceptions: negative,
    groups: [_group('Most value', lines)],
  );
}

ReportSummary _projects(ReportResult r) {
  final lines = <SummaryLine>[];
  final losing = <String>[];
  num invoiced = 0, margin = 0, unbilled = 0;
  for (final row in r.rows) {
    if (row[0] == 'Total') continue;
    invoiced += _n(row[1]);
    margin += _n(row[5]);
    unbilled += _n(row[4]);
    if (_n(row[5]) < 0) losing.add('${row[0]} is losing ${formatMoney(-_n(row[5]))}.');
    lines.add(SummaryLine(row[0] ?? '', formatMoney(_n(row[5])),
        detail: 'Invoiced ${formatMoney(_n(row[1]))} · ${row[3] ?? '0'} h'));
  }
  return ReportSummary(
    figures: [
      SummaryFigure('Margin', formatMoney(margin),
          tone: margin < 0 ? SummaryTone.bad : SummaryTone.good),
      SummaryFigure('Invoiced', formatMoney(invoiced)),
      SummaryFigure('Unbilled time', formatMoney(unbilled)),
    ],
    exceptions: [
      ...losing,
      if (unbilled > 0) '${formatMoney(unbilled)} of time is not invoiced yet.',
    ],
    groups: [_group('By project', lines)],
  );
}
