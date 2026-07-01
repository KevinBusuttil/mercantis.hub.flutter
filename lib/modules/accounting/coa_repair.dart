import 'package:mercantis_core/mercantis_core.dart';

import '../../ledger/ledger_values.dart';
import '../../onboarding/hub_seeder.dart';

/// What a Repair Chart of Accounts run changed.
class CoaRepairSummary {
  const CoaRepairSummary({required this.accountsCreated, required this.defaultsRewired});

  /// Starter accounts that were missing and got re-created.
  final int accountsCreated;

  /// Company default-account fields that were blank/dangling and got re-pointed
  /// at an existing account.
  final int defaultsRewired;

  bool get repairedAnything => accountsCreated > 0 || defaultsRewired > 0;
}

/// Repair Chart of Accounts (H10 — the Swift Tools ▸ Repair COA command).
///
/// Restores a chart that has drifted: it re-creates any missing starter account
/// (so postings always have somewhere to land) and re-wires each `Company`
/// default-account field that is blank or points at an account that no longer
/// exists. Idempotent — a healthy chart is left untouched.
class ChartOfAccountsRepair {
  ChartOfAccountsRepair({required this.engine, this.roles = const {'System Manager'}});

  final DocumentEngine engine;
  final Set<String> roles;

  Future<CoaRepairSummary> repair() async {
    var created = 0;
    var rewired = 0;

    // 1. Re-create any missing starter account.
    for (final a in HubChart.accounts) {
      if (await engine.fetch('Account', a.id) != null) continue;
      await engine.save(
        Document(id: a.id, docType: 'Account', payload: {
          'account_name': a.name,
          'root_type': a.rootType,
          'account_type': a.accountType,
          'is_group': '0',
        }),
        roles,
      );
      created++;
    }

    // 2. Re-wire each company's default-account fields that are blank or point
    //    at an account that no longer exists.
    for (final company in await engine.list('Company', userRoles: roles)) {
      var changed = false;
      for (final entry in HubChart.companyDefaults.entries) {
        final current = asNonEmpty(company.payload[entry.key]);
        final valid =
            current != null && await engine.fetch('Account', current) != null;
        if (valid) continue;
        // Only re-point when the intended default account actually exists.
        if (await engine.fetch('Account', entry.value) == null) continue;
        company.payload[entry.key] = entry.value;
        changed = true;
        rewired++;
      }
      if (changed) await engine.save(company, roles);
    }

    return CoaRepairSummary(accountsCreated: created, defaultsRewired: rewired);
  }
}
