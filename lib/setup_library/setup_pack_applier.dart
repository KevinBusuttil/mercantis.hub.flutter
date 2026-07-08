import 'dart:convert';

import 'package:mercantis_core/mercantis_core.dart';

import '../ledger/ledger_values.dart';
import 'setup_pack.dart';

/// One line of the recorded diff.
class PackChange {
  const PackChange(this.action, this.docType, this.id);

  /// `created` | `skipped` (already present) | `default-set` | `rule-added`.
  final String action;
  final String docType;
  final String id;

  Map<String, dynamic> toJson() =>
      {'action': action, 'doctype': docType, 'id': id};
}

/// The outcome of one apply: every change, inspectable and persisted.
class PackApplyResult {
  const PackApplyResult({
    required this.applicationId,
    required this.changes,
    required this.moduleToggles,
    required this.alreadyApplied,
  });

  final String applicationId;
  final List<PackChange> changes;

  /// Module visibility the pack implies — the caller applies these through
  /// HubSettings (settings have their own persistence and provider).
  final Map<String, bool> moduleToggles;

  /// True when this exact pack version had already been applied: the run
  /// was a recorded no-op.
  final bool alreadyApplied;

  int get created =>
      changes.where((c) => c.action != 'skipped').length;
  int get skipped =>
      changes.where((c) => c.action == 'skipped').length;
}

/// Applies a [SetupPack] idempotently (acceptance criteria 3, 5, 6):
/// masters are ensured-if-absent (a pack never overwrites what the user
/// already has), blank company default accounts are filled, the pack's
/// rules are saved with `built-in` provenance, and the whole run is
/// recorded as a `Setup Pack Application` — the user-visible "what did
/// this pack change" and the ledger upgrades consult.
class SetupPackApplier {
  SetupPackApplier({required this.engine, this.roles = const {'System Manager'}});

  final DocumentEngine engine;
  final Set<String> roles;

  Future<PackApplyResult> apply(SetupPack pack) async {
    // Same pack, same version, already recorded → a no-op, recorded again
    // is noise; return the fact instead.
    final previous = await engine.list('Setup Pack Application',
        filters: {'pack_id': pack.id, 'pack_version': pack.version},
        userRoles: roles);
    if (previous.isNotEmpty) {
      return PackApplyResult(
        applicationId: previous.first.id,
        changes: const [],
        moduleToggles: pack.moduleToggles,
        alreadyApplied: true,
      );
    }

    final changes = <PackChange>[];

    // 1. Masters: ensure-if-absent, in pack order (accounts before the
    // things that link to them — the pack author controls ordering).
    for (final master in pack.masters) {
      if (await engine.fetch(master.docType, master.id) != null) {
        changes.add(PackChange('skipped', master.docType, master.id));
        continue;
      }
      await engine.save(
        Document(
            id: master.id,
            docType: master.docType,
            payload: Map<String, dynamic>.from(master.payload)),
        roles,
      );
      changes.add(PackChange('created', master.docType, master.id));
    }

    // 2. Company defaults: fill blanks only — an owner's explicit account
    // choice always outranks a pack.
    if (pack.companyDefaults.isNotEmpty) {
      final companies = await engine.list('Company', userRoles: roles);
      if (companies.isNotEmpty) {
        final company = companies.first;
        var touched = false;
        for (final entry in pack.companyDefaults.entries) {
          if (asNonEmpty(company.payload[entry.key]) != null) continue;
          company.payload[entry.key] = entry.value;
          changes.add(PackChange('default-set', 'Company',
              '${company.id}.${entry.key}=${entry.value}'));
          touched = true;
        }
        if (touched) await engine.save(company, roles);
      }
    }

    // 3. Rules: contributed with built-in provenance and the pack stamped,
    // deterministic ids so re-application can't duplicate them.
    for (var i = 0; i < pack.rules.length; i++) {
      final id = 'RULE-${pack.id}-$i';
      if (await engine.fetch('Setup Rule', id) != null) {
        changes.add(PackChange('skipped', 'Setup Rule', id));
        continue;
      }
      await engine.save(
        Document(id: id, docType: 'Setup Rule', payload: {
          ...pack.rules[i],
          'provenance': 'built-in',
          'source_pack': '${pack.id}@${pack.version}',
        }),
        roles,
      );
      changes.add(PackChange('rule-added', 'Setup Rule', id));
    }

    // 4. The recorded diff.
    final application = await engine.save(
      Document(id: '', docType: 'Setup Pack Application', payload: {
        'pack_id': pack.id,
        'pack_version': pack.version,
        'applied_at': DateTime.now().toIso8601String(),
        'created_count': changes.where((c) => c.action != 'skipped').length,
        'skipped_count': changes.where((c) => c.action == 'skipped').length,
        'diff': jsonEncode([for (final c in changes) c.toJson()]),
      }),
      roles,
    );

    return PackApplyResult(
      applicationId: application.id,
      changes: changes,
      moduleToggles: pack.moduleToggles,
      alreadyApplied: false,
    );
  }
}
