import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

import '../../ledger/ledger_values.dart';

/// Advances an ISO date by one billing period. Monthly/quarterly/yearly
/// clamp the day to the target month's length (a Jan-31 monthly retainer
/// bills Feb-28, then Mar-28 — deterministic and never skips a month).
String nextBillingDate(String isoDate, String frequency) {
  final d = DateTime.parse(isoDate);
  DateTime next;
  switch (frequency) {
    case 'Weekly':
      next = d.add(const Duration(days: 7));
    case 'Quarterly':
      next = _addMonths(d, 3);
    case 'Yearly':
      next = _addMonths(d, 12);
    case 'Monthly':
    default:
      next = _addMonths(d, 1);
  }
  return '${next.year.toString().padLeft(4, '0')}-'
      '${next.month.toString().padLeft(2, '0')}-'
      '${next.day.toString().padLeft(2, '0')}';
}

DateTime _addMonths(DateTime d, int months) {
  final zeroBased = d.month - 1 + months;
  final year = d.year + zeroBased ~/ 12;
  final month = zeroBased % 12 + 1;
  final lastDay = DateTime(year, month + 1, 0).day;
  return DateTime(year, month, d.day > lastDay ? lastDay : d.day);
}

/// The outcome of one generation run.
class RecurringRunResult {
  const RecurringRunResult({required this.generated, required this.failures});

  /// Ids of the Sales Invoices created (drafts unless auto_submit).
  final List<String> generated;

  /// Template id → error message, also stamped on the template's
  /// `last_error` so the failure is visible where the user looks.
  final Map<String, String> failures;
}

/// Generates the Sales Invoices that recurring templates owe as of a date
/// (Phase 1A/7 — retainers). Runs at boot and can be invoked on demand; each
/// elapsed period yields one invoice (catch-up capped at [maxPerTemplate] so
/// a template forgotten for years cannot flood the book). Drafts land in the
/// approvals inbox like any other draft; auto_submit posts them straight
/// through the ledger.
class RecurringInvoiceService {
  RecurringInvoiceService(
      {required this.engine, this.roles = const {'System Manager'}});

  final DocumentEngine engine;
  final Set<String> roles;

  static const maxPerTemplate = 24;

  Future<RecurringRunResult> generateDue({required String asOf}) async {
    final generated = <String>[];
    final failures = <String, String>{};

    final templates =
        await engine.list('Recurring Invoice', userRoles: roles);
    for (final header in templates) {
      if (!isTrue(header.payload['active'])) continue;
      // list() doesn't hydrate the items child table.
      final template = await engine.fetch('Recurring Invoice', header.id);
      if (template == null) continue;
      try {
        var next = asNonEmpty(template.payload['next_invoice_date']);
        final end = asNonEmpty(template.payload['end_date']);
        var count = 0;
        var changed = false;
        while (next != null &&
            next.compareTo(asOf) <= 0 &&
            (end == null || next.compareTo(end) <= 0) &&
            count < maxPerTemplate) {
          final invoice = _buildInvoice(template, postingDate: next);
          final saved = await engine.save(invoice, roles);
          if (isTrue(template.payload['auto_submit'])) {
            await engine.submit(saved, roles);
          }
          generated.add(saved.id);
          template.payload['last_generated_on'] = next;
          next = nextBillingDate(next, '${template.payload['frequency']}');
          template.payload['next_invoice_date'] = next;
          changed = true;
          count++;
        }
        if (changed || asNonEmpty(template.payload['last_error']) != null) {
          template.payload['last_error'] = '';
          await engine.save(template, roles);
        }
      } catch (e) {
        failures[template.id] = '$e';
        template.payload['last_error'] = '$e';
        try {
          await engine.save(template, roles);
        } catch (_) {/* keep the run going */}
      }
    }
    return RecurringRunResult(generated: generated, failures: failures);
  }

  Document _buildInvoice(Document template, {required String postingDate}) {
    final invoice = Document(
      id: '',
      docType: 'Sales Invoice',
      company: template.company,
      payload: {
        'customer': template.payload['customer'],
        'posting_date': postingDate,
        if (asNonEmpty(template.payload['tax_code']) != null)
          'tax_code': template.payload['tax_code'],
        if (asNonEmpty(template.payload['currency']) != null)
          'currency': template.payload['currency'],
        'recurring_invoice': template.id,
      },
    );
    final rows = template.children['items'] ?? const <ChildRow>[];
    invoice.children['items'] = [
      for (var i = 0; i < rows.length; i++)
        ChildRow(
          id: '', parentId: '', parentDocType: 'Sales Invoice',
          tableName: 'items', rowIndex: i,
          payload: {
            'item': rows[i].payload['item'],
            'qty': rows[i].payload['qty'],
            'rate': rows[i].payload['rate'],
            if (asNonEmpty(rows[i].payload['tax_code']) != null)
              'tax_code': rows[i].payload['tax_code'],
          },
        ),
    ];
    return invoice;
  }
}

/// Boot hook: generate whatever is due today. Failures are stamped on the
/// templates (last_error) — visible right where the user manages them.
final recurringInvoiceRunProvider =
    FutureProvider<RecurringRunResult>((ref) async {
  final engine = await ref.watch(documentEngineProvider.future);
  final service = RecurringInvoiceService(engine: engine);
  return service.generateDue(
      asOf: DateTime.now().toIso8601String().split('T').first);
});
