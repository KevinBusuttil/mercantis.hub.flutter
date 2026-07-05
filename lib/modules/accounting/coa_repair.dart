import 'package:mercantis_core/mercantis_core.dart';

import '../../ledger/ledger_values.dart';
import '../../onboarding/hub_seeder.dart';

/// What a Repair Chart of Accounts run changed.
class CoaRepairSummary {
  const CoaRepairSummary({
    required this.accountsCreated,
    required this.defaultsRewired,
    this.accountsReparented = 0,
    this.mastersCreated = 0,
    this.mastersReparented = 0,
  });

  /// Starter accounts that were missing and got re-created.
  final int accountsCreated;

  /// Company default-account fields that were blank/dangling and got re-pointed
  /// at an existing account.
  final int defaultsRewired;

  /// Existing starter accounts that had no parent and were slotted under their
  /// root group — the back-fill that turns a flat chart into the grouped tree.
  final int accountsReparented;

  /// Starter tree-master nodes (item / customer / supplier groups, territories,
  /// cost centres) that were missing and got created.
  final int mastersCreated;

  /// Existing starter tree-master nodes that had no parent and were slotted
  /// under their root — the same flat→grouped back-fill as the accounts.
  final int mastersReparented;

  bool get repairedAnything =>
      accountsCreated > 0 ||
      defaultsRewired > 0 ||
      accountsReparented > 0 ||
      mastersCreated > 0 ||
      mastersReparented > 0;
}

/// Repair Chart of Accounts (H10 — the Swift Tools ▸ Repair COA command).
///
/// Restores starter master data that has drifted: it re-creates any missing
/// starter account (so postings always have somewhere to land), re-wires each
/// `Company` default-account field that is blank or dangling, and restores the
/// starter tree masters (item / customer / supplier groups, territories, cost
/// centres) — creating missing nodes and slotting parentless ones back under
/// their root. Idempotent — healthy data is left untouched, and anything the
/// user has already parented themselves is respected.
class ChartOfAccountsRepair {
  ChartOfAccountsRepair({required this.engine, this.roles = const {'System Manager'}});

  final DocumentEngine engine;
  final Set<String> roles;

  Future<CoaRepairSummary> repair() async {
    var created = 0;
    var rewired = 0;
    var reparented = 0;

    // 1. Re-create any missing starter account (groups first, per HubChart
    //    ordering, so a parent exists before the child that points at it).
    for (final a in HubChart.accounts) {
      if (await engine.fetch('Account', a.id) != null) continue;
      await engine.save(
        Document(id: a.id, docType: 'Account', payload: {
          'account_name': a.name,
          'root_type': a.rootType,
          if (a.accountType.isNotEmpty) 'account_type': a.accountType,
          'is_group': a.isGroup ? '1' : '0',
          if (a.parent != null) 'parent_account': a.parent,
        }),
        roles,
      );
      created++;
    }

    // 1b. Back-fill the hierarchy on a chart that was seeded flat (before
    //     grouping): slot each starter account that has no parent under its
    //     root group. Leaves an account the user has already parented alone, so
    //     it's idempotent and non-destructive.
    for (final a in HubChart.accounts) {
      if (a.parent == null) continue;
      final doc = await engine.fetch('Account', a.id);
      if (doc == null) continue;
      if (asNonEmpty(doc.payload['parent_account']) != null) continue;
      doc.payload['parent_account'] = a.parent;
      await engine.save(doc, roles);
      reparented++;
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

    // 3. Restore the starter tree masters the same way: create missing nodes
    //    (roots first, per node ordering) then back-fill blank parents.
    var mastersCreated = 0;
    var mastersReparented = 0;
    for (final m in HubChart.treeMasters) {
      for (final n in m.nodes) {
        if (await engine.fetch(m.docType, n.id) != null) continue;
        await engine.save(
          Document(id: n.id, docType: m.docType, payload: {
            m.nameField: n.id,
            'is_group': n.isGroup ? '1' : '0',
            if (n.parent != null) m.parentField: n.parent,
          }),
          roles,
        );
        mastersCreated++;
      }
      for (final n in m.nodes) {
        if (n.parent == null) continue;
        final doc = await engine.fetch(m.docType, n.id);
        if (doc == null) continue;
        if (asNonEmpty(doc.payload[m.parentField]) != null) continue;
        doc.payload[m.parentField] = n.parent;
        await engine.save(doc, roles);
        mastersReparented++;
      }
    }

    return CoaRepairSummary(
      accountsCreated: created,
      defaultsRewired: rewired,
      accountsReparented: reparented,
      mastersCreated: mastersCreated,
      mastersReparented: mastersReparented,
    );
  }
}
