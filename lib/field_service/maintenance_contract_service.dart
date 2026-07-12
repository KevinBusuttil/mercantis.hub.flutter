import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

import '../ledger/ledger_values.dart';
import '../modules/selling/recurring_invoice_service.dart'
    show nextBillingDate;

/// The outcome of one contract-generation run.
class ContractRunResult {
  const ContractRunResult({required this.generated, required this.failures});

  /// Ids of the Jobs created (drafts — the dispatch board's queue).
  final List<String> generated;

  /// Contract id → error, also stamped on the contract's `last_error`.
  final Map<String, String> failures;
}

/// V1-5: generates the Jobs that active Maintenance Contracts owe as of a
/// date. Same shape as [RecurringInvoiceService]: runs at boot and on
/// demand, one job per elapsed period (catch-up capped so a contract
/// forgotten for years cannot flood dispatch), failures stamped where the
/// user manages contracts. Generated jobs are drafts — they appear in the
/// dispatch board's "waiting for a slot" queue for a human to assign.
class MaintenanceContractService {
  MaintenanceContractService(
      {required this.engine, this.roles = const {'System Manager'}});

  final DocumentEngine engine;
  final Set<String> roles;

  static const maxPerContract = 12;

  Future<ContractRunResult> generateDue({required String asOf}) async {
    final generated = <String>[];
    final failures = <String, String>{};

    final headers =
        await engine.list('Maintenance Contract', userRoles: roles);
    for (final header in headers) {
      if (!isTrue(header.payload['active'])) continue;
      // list() doesn't hydrate the template child tables.
      final contract =
          await engine.fetch('Maintenance Contract', header.id);
      if (contract == null) continue;
      try {
        var next = asNonEmpty(contract.payload['next_job_date']);
        final end = asNonEmpty(contract.payload['end_date']);
        var count = 0;
        var changed = false;
        while (next != null &&
            next.compareTo(asOf) <= 0 &&
            (end == null || next.compareTo(end) <= 0) &&
            count < maxPerContract) {
          final saved = await engine.save(_buildJob(contract, due: next), roles);
          generated.add(saved.id);
          contract.payload['last_generated_on'] = next;
          next = nextBillingDate(next, '${contract.payload['frequency']}');
          contract.payload['next_job_date'] = next;
          changed = true;
          count++;
        }
        if (changed || asNonEmpty(contract.payload['last_error']) != null) {
          contract.payload['last_error'] = '';
          await engine.save(contract, roles);
        }
      } catch (e) {
        failures[contract.id] = '$e';
        contract.payload['last_error'] = '$e';
        try {
          await engine.save(contract, roles);
        } catch (_) {/* keep the run going */}
      }
    }
    return ContractRunResult(generated: generated, failures: failures);
  }

  Document _buildJob(Document contract, {required String due}) {
    final job = Document(
      id: '',
      docType: 'Job',
      company: contract.company,
      payload: {
        'subject': '${contract.payload['subject']} — due $due',
        'customer': contract.payload['customer'],
        'maintenance_contract': contract.id,
        'priority': contract.payload['priority'],
        'address': contract.payload['address'],
        'description': contract.payload['description'],
        'status': 'Draft',
      },
    );
    // The contract's template tables copy onto the job verbatim.
    for (final table in const ['checklist', 'materials', 'labour']) {
      final rows = contract.children[table] ?? const <ChildRow>[];
      if (rows.isEmpty) continue;
      job.children[table] = [
        for (var i = 0; i < rows.length; i++)
          ChildRow(
            id: '', parentId: '', parentDocType: 'Job',
            tableName: table, rowIndex: i,
            payload: Map<String, dynamic>.from(rows[i].payload)
              ..remove('done'), // a fresh job starts unticked
          ),
      ];
    }
    return job;
  }
}

/// Boot hook, alongside recurring invoices: whatever jobs contracts owe
/// today land in dispatch before anyone asks.
final maintenanceContractRunProvider =
    FutureProvider<ContractRunResult>((ref) async {
  final engine = await ref.watch(documentEngineProvider.future);
  final service = MaintenanceContractService(engine: engine);
  return service.generateDue(
      asOf: DateTime.now().toIso8601String().split('T').first);
});
