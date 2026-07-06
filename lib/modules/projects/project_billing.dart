import 'package:mercantis_core/mercantis_core.dart';

import '../../ledger/ledger_values.dart';

/// What a project-billing run would invoice: unbilled billable hours and
/// unbilled billable expenses.
class ProjectBillingPreview {
  const ProjectBillingPreview({
    required this.timesheets,
    required this.expenses,
    required this.timeValue,
    required this.expenseValue,
  });

  final List<Document> timesheets;
  final List<Document> expenses;
  final num timeValue;
  final num expenseValue;

  num get total => timeValue + expenseValue;
  bool get isEmpty => timesheets.isEmpty && expenses.isEmpty;
}

/// Turns a project's unbilled billable work into a draft Sales Invoice
/// (Phase 6): one line per timesheet (hours × rate, rate falling back to the
/// project default) and one per billable expense (net amount, passed through).
/// After the draft is saved, every source row is stamped `billed` with the
/// invoice id, so a second run bills nothing — the retainer-safe property.
class ProjectBilling {
  ProjectBilling({required this.engine, this.roles = const {'System Manager'}});

  final DocumentEngine engine;
  final Set<String> roles;

  Future<ProjectBillingPreview> preview(String projectId) async {
    final project = await engine.fetch('Project', projectId);
    final defaultRate = asNum(project?.payload['default_billing_rate']);

    final timesheets = <Document>[];
    num timeValue = 0;
    for (final t in await engine.list('Timesheet',
        filters: {'project': projectId}, userRoles: roles)) {
      if (!isTrue(t.payload['billable'])) continue;
      if (isTrue(t.payload['billed'])) continue;
      timesheets.add(t);
      final rate = _numOr(t.payload['billing_rate'], defaultRate);
      timeValue += asNum(t.payload['hours']) * rate;
    }

    final expenses = <Document>[];
    num expenseValue = 0;
    for (final e in await engine.list('Expense',
        filters: {'project': projectId}, userRoles: roles)) {
      if (e.docStatus != 1) continue; // only real (submitted) costs
      if (!isTrue(e.payload['billable'])) continue;
      if (isTrue(e.payload['billed'])) continue;
      expenses.add(e);
      expenseValue += asNum(e.payload['net_amount']);
    }

    return ProjectBillingPreview(
      timesheets: timesheets,
      expenses: expenses,
      timeValue: timeValue,
      expenseValue: expenseValue,
    );
  }

  /// The generic service items billing lines post against (invoice lines
  /// require an Item). Created on demand, deterministic ids — same pattern
  /// as the capture module's Uncategorised item.
  static const timeItem = 'Professional Services';
  static const expenseItem = 'Billable Expense';

  Future<void> _ensureItem(String id) async {
    if (await engine.fetch('Item', id) != null) return;
    await engine.save(
      Document(id: id, docType: 'Item', payload: {
        'item_code': id,
        'item_name': id,
        'item_type': 'Service',
        'stock_uom': 'Nos',
      }),
      roles,
    );
  }

  /// Creates the draft invoice and stamps every source row billed. Returns
  /// null when there is nothing to bill.
  Future<Document?> createInvoice(String projectId,
      {required String postingDate}) async {
    final project = await engine.fetch('Project', projectId);
    if (project == null) return null;
    final customer = asNonEmpty(project.payload['customer']);
    if (customer == null) {
      throw StateError('Project $projectId has no customer to invoice.');
    }
    final work = await preview(projectId);
    if (work.isEmpty) return null;
    if (work.timesheets.isNotEmpty) await _ensureItem(timeItem);
    if (work.expenses.isNotEmpty) await _ensureItem(expenseItem);

    final defaultRate = asNum(project.payload['default_billing_rate']);
    final invoice = Document(
      id: '',
      docType: 'Sales Invoice',
      company: project.company,
      payload: {
        'customer': customer,
        'posting_date': postingDate,
        'project': projectId,
      },
    );
    final lines = <ChildRow>[];
    ChildRow row(Map<String, dynamic> payload) => ChildRow(
          id: '', parentId: '', parentDocType: 'Sales Invoice',
          tableName: 'items', rowIndex: lines.length,
          payload: payload,
        );
    for (final t in work.timesheets) {
      final hours = asNum(t.payload['hours']);
      final rate = _numOr(t.payload['billing_rate'], defaultRate);
      lines.add(row({
        'item': timeItem,
        'description': asNonEmpty(t.payload['description']) ??
            'Work on ${t.payload['activity_date']}',
        'qty': hours,
        'rate': rate,
      }));
    }
    for (final e in work.expenses) {
      lines.add(row({
        'item': expenseItem,
        'description':
            asNonEmpty(e.payload['description']) ?? 'Expense ${e.id}',
        'qty': 1,
        'rate': asNum(e.payload['net_amount']),
      }));
    }
    invoice.children['items'] = lines;
    final saved = await engine.save(invoice, roles);

    for (final t in work.timesheets) {
      t.payload['billed'] = 1;
      t.payload['sales_invoice'] = saved.id;
      await engine.save(t, roles);
    }
    for (final e in work.expenses) {
      e.payload['billed'] = 1;
      e.payload['billed_on'] = saved.id;
      await engine.applyOnSubmitUpdate(e, roles);
    }
    return saved;
  }

  static num _numOr(dynamic v, num fallback) {
    if (v is num && v != 0) return v;
    if (v is String) {
      final parsed = num.tryParse(v.trim());
      if (parsed != null && parsed != 0) return parsed;
    }
    return fallback;
  }
}
