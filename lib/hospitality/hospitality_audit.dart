import 'package:mercantis_core/mercantis_core.dart';

import '../ledger/ledger_values.dart';
import 'tab_service.dart';

const _systemRoles = {'System Manager'};

/// One line of the void/comp audit: something that left the money trail
/// on purpose, with who/what/why/how-much attached.
class HospitalityAuditEntry {
  const HospitalityAuditEntry({
    required this.kind,
    required this.id,
    required this.detail,
    required this.reason,
    required this.value,
    this.when,
  });

  /// 'Voided tab' | 'Comped line' | 'Cancelled invoice'.
  final String kind;
  final String id;
  final String detail;
  final String reason;
  final num value;
  final DateTime? when;
}

class HospitalityAudit {
  const HospitalityAudit({
    required this.voids,
    required this.comps,
    required this.cancellations,
  });

  final List<HospitalityAuditEntry> voids;
  final List<HospitalityAuditEntry> comps;
  final List<HospitalityAuditEntry> cancellations;

  num get voidValue =>
      round2(voids.fold<num>(0, (s, e) => s + e.value));
  num get compValue =>
      round2(comps.fold<num>(0, (s, e) => s + e.value));
  num get cancelValue =>
      round2(cancellations.fold<num>(0, (s, e) => s + e.value));
}

/// V2-5: the giveaway trail in one query. Everything that reduced or
/// erased a bill outside a normal sale — voided tabs (with the value
/// walked away from), comped lines (on ANY tab, whatever became of it),
/// and cancelled fiscal invoices. This is the report the Thirteenth
/// Schedule auditor — and the owner counting shrinkage — asks for.
Future<HospitalityAudit> buildHospitalityAudit(DocumentEngine engine,
    {Set<String> roles = _systemRoles}) async {
  final voids = <HospitalityAuditEntry>[];
  final comps = <HospitalityAuditEntry>[];
  final cancellations = <HospitalityAuditEntry>[];

  for (final header in await engine.list('POS Tab', userRoles: roles)) {
    final tab = await engine.fetch('POS Tab', header.id) ?? header;
    final where = asNonEmpty(tab.payload['table']) ?? 'Bar';
    final server = asNonEmpty(tab.payload['server']);
    final when = tab.modifiedAt ?? tab.createdAt;

    if ('${tab.payload['status']}' == 'Void') {
      voids.add(HospitalityAuditEntry(
        kind: 'Voided tab',
        id: tab.id,
        detail: server == null ? where : '$where · $server',
        reason: '${tab.payload['void_reason'] ?? ''}',
        value: TabService.tabTotal(tab),
        when: when,
      ));
    }

    for (final row in tab.children['items'] ?? const <ChildRow>[]) {
      if (!isTrue(row.payload['comp'])) continue;
      comps.add(HospitalityAuditEntry(
        kind: 'Comped line',
        id: tab.id,
        detail: '${asNum(row.payload['qty'])} × ${row.payload['item']}'
            '${server == null ? '' : ' · $server'}',
        reason: '${row.payload['comp_reason'] ?? ''}',
        value: round2(asNum(row.payload['qty']) *
            (asNum(row.payload['rate']) +
                asNum(row.payload['modifier_amount']))),
        when: when,
      ));
    }
  }

  for (final inv in await engine.list('POS Invoice', userRoles: roles)) {
    if (inv.docStatus != 2) continue;
    cancellations.add(HospitalityAuditEntry(
      kind: 'Cancelled invoice',
      id: inv.id,
      detail: asNonEmpty(inv.payload['official_number']) ?? inv.id,
      reason: '',
      value: asNum(inv.payload['grand_total']),
      when: inv.modifiedAt ?? inv.createdAt,
    ));
  }

  int newestFirst(HospitalityAuditEntry a, HospitalityAuditEntry b) =>
      (b.when ?? DateTime(0)).compareTo(a.when ?? DateTime(0));
  voids.sort(newestFirst);
  comps.sort(newestFirst);
  cancellations.sort(newestFirst);

  return HospitalityAudit(
      voids: voids, comps: comps, cancellations: cancellations);
}
