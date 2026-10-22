import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_hub_app/dashboards/owner_kpis.dart';
import 'package:mercantis_hub_app/manifest/hub_dashboards.dart';
import 'package:mercantis_hub_app/manifest/hub_reports.dart';
import 'package:mercantis_hub_app/reports/aggregating_reports.dart';
import 'package:mercantis_hub_app/reports/report_providers.dart';

/// A small, fictional service business ("Harbour Lane Design") as an
/// in-memory document set. Production KPI, dashboard and report code runs
/// over it unchanged (they all take an injected list function), so widget
/// tests and screenshots show real computations over synthetic data — never
/// customer data and never hand-drawn numbers.
class SyntheticBusiness {
  SyntheticBusiness({DateTime? today}) : today = today ?? DateTime.now() {
    _build();
  }

  final DateTime today;
  final Map<String, List<Document>> _docs = {};

  String _d(int daysAgo) => today
      .subtract(Duration(days: daysAgo))
      .toIso8601String()
      .split('T')
      .first;

  void _add(String docType, String id, Map<String, dynamic> payload,
      {int docStatus = 0}) {
    (_docs[docType] ??= []).add(Document(
        id: id, docType: docType, payload: payload, docStatus: docStatus));
  }

  void _build() {
    const accounts = {
      'Bank - HLD': ('Asset', 'Bank'),
      'Cash - HLD': ('Asset', 'Cash'),
      'Debtors - HLD': ('Asset', 'Receivable'),
      'Creditors - HLD': ('Liability', 'Payable'),
      'VAT Payable - HLD': ('Liability', 'Tax'),
      'Capital - HLD': ('Equity', ''),
      'Design Fees - HLD': ('Income', 'Income Account'),
      'Consulting - HLD': ('Income', 'Income Account'),
      'Software - HLD': ('Expense', 'Expense Account'),
      'Rent - HLD': ('Expense', 'Expense Account'),
      'Travel - HLD': ('Expense', 'Expense Account'),
    };
    accounts.forEach((id, t) => _add('Account', id, {
          'account_name': id,
          'root_type': t.$1,
          'account_type': t.$2,
        }));

    var gl = 0;
    void post(String debit, String credit, num amount, int daysAgo) {
      _add('GL Entry', 'GLE-${++gl}', {
        'account': debit, 'debit': amount, 'credit': 0,
        'posting_date': _d(daysAgo),
      }, docStatus: 1);
      _add('GL Entry', 'GLE-${++gl}', {
        'account': credit, 'debit': 0, 'credit': amount,
        'posting_date': _d(daysAgo),
      }, docStatus: 1);
    }

    post('Bank - HLD', 'Capital - HLD', 5000, 120);
    post('Debtors - HLD', 'Design Fees - HLD', 8400, 60);
    post('Debtors - HLD', 'Consulting - HLD', 3150, 20);
    post('Bank - HLD', 'Debtors - HLD', 6900, 10);
    post('Software - HLD', 'Creditors - HLD', 420, 30);
    post('Rent - HLD', 'Bank - HLD', 1200, 15);
    post('Travel - HLD', 'Cash - HLD', 186.40, 4);
    post('Creditors - HLD', 'Bank - HLD', 300, 3);

    const customers = [
      'Blue Fig Café', 'Marsa Yacht Services', 'Studio Nove',
      'Gozo Craft Co.', 'Valletta Law Partners',
    ];
    for (final c in customers) {
      _add('Customer', c, {'customer_name': c});
    }

    var n = 0;
    void invoice(String customer, num total, num outstanding, int ageDays,
        {int termsDays = 30}) {
      final id = 'SINV-2026-${(++n).toString().padLeft(4, '0')}';
      _add('Sales Invoice', id, {
        'customer': customer,
        'posting_date': _d(ageDays),
        'due_date': _d(ageDays - termsDays),
        'grand_total': total,
        'outstanding_amount': outstanding,
        'currency': 'EUR',
      }, docStatus: 1);
    }

    invoice('Blue Fig Café', 1850, 0, 58);
    invoice('Marsa Yacht Services', 4200, 4200, 75);
    invoice('Studio Nove', 960, 960, 45);
    invoice('Gozo Craft Co.', 1390, 0, 25);
    invoice('Valletta Law Partners', 3150, 3150, 12);
    invoice('Blue Fig Café', 720, 720, 2);

    _add('Purchase Invoice', 'PINV-2026-0001', {
      'supplier': 'CloudDesk Ltd',
      'posting_date': _d(30),
      'due_date': _d(2),
      'grand_total': 420,
      'outstanding_amount': 120,
    }, docStatus: 1);

    _add('Tax Transaction', 'TT-1', {
      'posting_date': _d(12), 'party_type': 'Customer', 'tax_amount': 567,
    }, docStatus: 1);
    _add('Tax Transaction', 'TT-2', {
      'posting_date': _d(30), 'party_type': 'Supplier', 'tax_amount': 75.6,
    }, docStatus: 1);
  }

  /// [DocumentListFn]-compatible view over the synthetic set.
  Future<List<Document>> list(
    String docType, {
    Map<String, dynamic>? filters,
    String? whereExpression,
    List<({String field, bool ascending})>? sortBy,
    int? limit,
    int? offset,
    Set<String>? userRoles,
  }) async {
    var rows = List<Document>.of(_docs[docType] ?? const []);
    if (filters != null) {
      rows = rows
          .where((d) => filters.entries.every((f) => d.payload[f.key] == f.value))
          .toList();
    }
    if (limit != null) rows = rows.take(limit).toList();
    return rows;
  }

  Future<Document?> fetch(String docType, String id) async {
    for (final d in _docs[docType] ?? const <Document>[]) {
      if (d.id == id) return d;
    }
    return null;
  }

  /// Provider overrides that point the owner KPIs, dashboards and aggregating
  /// reports at this business (no database, no platform channels).
  List<Override> overrides() {
    final reportEngine = ReportEngine(list)..registerAll(HubReports.all());
    return [
      ownerKpisProvider.overrideWith((ref) async => OwnerKpis(list)),
      reportEngineProvider.overrideWith((ref) async => reportEngine),
      aggregatingReportsProvider
          .overrideWith((ref) async => HubAggregatingReports(list, fetch: fetch)),
      dashboardEngineProvider.overrideWith((ref) async =>
          DashboardEngine(list, reportEngine)..registerAll(HubDashboards.all())),
    ];
  }
}

/// A hand-built [ReportResult] for summary edge cases (losses, long lists).
class ReportResultFixture {
  const ReportResultFixture(this.reportId, this.rows);
  final String reportId;
  final List<List<String?>> rows;

  ReportResult get result => ReportResult(
        reportId: reportId,
        name: reportId,
        columns: [
          for (var i = 0; i < rows.first.length; i++)
            ReportColumn(fieldKey: 'c$i', label: 'c$i'),
        ],
        rows: rows,
      );
}
