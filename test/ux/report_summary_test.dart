import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_hub_app/reports/aggregating_reports.dart';
import 'package:mercantis_hub_app/reports/money_format.dart';
import 'package:mercantis_hub_app/reports/report_summary.dart';

import '../support/synthetic_business.dart';

/// Phone-first statements (brief §F): headline figures, exceptions, drill-down
/// — read from the same ReportResult the detailed table shows.
void main() {
  final biz = SyntheticBusiness(today: DateTime(2026, 10, 22));
  final reports = HubAggregatingReports(biz.list, fetch: biz.fetch);

  test('money formats with grouping and reads back', () {
    expect(formatMoney(10213.6), '€10,213.60');
    expect(formatMoney(-42), '-€42.00');
    expect(parseAmount('1,234.50'), 1234.5);
    expect(parseAmount('€9'), 9);
    expect(parseAmount('—'), isNull);
    expect(parseAmount(null), isNull);
  });

  test('P&L leads with profit, income, expenses and margin', () async {
    final r = await reports.profitAndLoss();
    final s = summariseReport(r)!;
    final income = parseAmount(r.rows.firstWhere((x) => x[1] == 'Total income')[2])!;
    final expenses =
        parseAmount(r.rows.firstWhere((x) => x[1] == 'Total expenses')[2])!;
    expect(s.figures.first.label, 'Profit');
    expect(s.figures.first.value, formatMoney(income - expenses));
    expect(s.figures.map((f) => f.label), containsAll(['Income', 'Expenses', 'Margin']));
    expect(s.groups.first.lines, isNotEmpty);
    // Accounts drill into their ledger.
    expect(s.groups.first.lines.first.location,
        startsWith('/w/finance/account-ledger?account='));
  });

  test('a loss is flagged, not hidden', () {
    final s = summariseReport(const ReportResultFixture(
      'profit_and_loss',
      [
        ['Income', 'Sales', '100.00'],
        ['Income', 'Total income', '100.00'],
        ['Expenses', 'Rent', '250.00'],
        ['Expenses', 'Total expenses', '250.00'],
        ['', 'Net profit', '-150.00'],
      ],
    ).result)!;
    expect(s.figures.first.label, 'Loss');
    expect(s.figures.first.tone, SummaryTone.bad);
    expect(s.exceptions.single, contains('€150.00'));
  });

  test('who owes you drills into that customer\'s invoices', () async {
    final r = await reports.arAging(asOf: DateTime(2026, 10, 22));
    final s = summariseReport(r)!;
    expect(s.figures.first.label, 'Owed to you');
    expect(s.figures.first.value, formatMoney(parseAmount(r.rows.last[5])!));
    final first = s.groups.single.lines.first;
    expect(first.location, startsWith('/list/Sales Invoice?'));
    expect(Uri.parse(first.location!).queryParameters['f.customer'], first.label);
  });

  test('long groups are capped with a pointer to the table', () {
    final rows = [
      for (var i = 0; i < 9; i++) ['C$i', '1.00', '0.00', '0.00', '0.00', '1.00'],
      ['Total', '9.00', '0.00', '0.00', '0.00', '9.00'],
    ];
    final s = summariseReport(ReportResultFixture('ar_aging', rows).result)!;
    expect(s.groups.single.lines.length, 6);
    expect(s.groups.single.more, 3);
    expect(s.allClear, isNotNull);
  });

  test('balance sheet says whether it balances', () async {
    final s = summariseReport(await reports.balanceSheet())!;
    expect(s.figures.map((f) => f.label), ['You own', 'You owe', 'Net worth']);
    expect(s.allClear ?? s.exceptions.single, isNotEmpty);
  });

  test('reports without a summary form stay tables', () async {
    expect(summariseReport(await reports.trialBalance()), isNull);
  });
}
