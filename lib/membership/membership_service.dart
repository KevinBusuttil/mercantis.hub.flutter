import 'package:mercantis_core/mercantis_core.dart';

import '../ledger/ledger_values.dart';

const _systemRoles = {'System Manager'};

/// One row of the members list: who, on what, billing state, arrears.
class MemberRollLine {
  const MemberRollLine({
    required this.membership,
    required this.member,
    required this.planName,
    required this.fee,
    required this.frequency,
    this.nextInvoiceDate,
    required this.arrears,
  });

  final Document membership;
  final String member;
  final String planName;
  final num fee;
  final String frequency;
  final String? nextInvoiceDate;
  final num arrears;
}

/// V7: the membership lifecycle over the Recurring Invoice engine.
/// Activation writes the fee template from the plan; pause switches the
/// template off; resume switches it back on with the next bill moved to
/// TODAY — a paused gap is deliberately never back-billed; cancel ends
/// the template for good. Arrears are computed from the invoices the
/// template generated, never stored.
class MembershipService {
  MembershipService(this._engine, {Set<String> roles = _systemRoles})
      : _roles = roles;

  final DocumentEngine _engine;
  final Set<String> _roles;

  /// Draft → Active: the plan's fee starts billing from [joined_on]
  /// (auto-submit — membership fees are contractual; pass false to
  /// route drafts through approvals).
  Future<Document> activate(String membershipId,
      {String? taxCode, bool autoSubmit = true}) async {
    final membership = await _require(membershipId, expected: {'Draft'});
    final plan = await _engine.fetch(
        'Membership Plan', '${membership.payload['plan']}');
    if (plan == null) {
      throw StateError(
          'Membership $membershipId points at a missing plan '
          '${membership.payload['plan']}.');
    }
    if (!(plan.payload['enabled'] == null ||
        isTrue(plan.payload['enabled']))) {
      throw StateError(
          'Plan ${plan.id} is disabled — pick a live plan.');
    }
    final fee = asNum(plan.payload['fee']);
    if (fee <= 0) {
      throw StateError('Plan ${plan.id} has no fee amount.');
    }

    // The membership's company rides onto the template (and from there
    // onto every generated fee invoice) — multi-company books must not
    // fall to the defaults interceptor's first company (Codex, PR #169).
    final template = Document(id: '', docType: 'Recurring Invoice',
        company: membership.company,
        payload: {
          'customer': membership.payload['member'],
          'frequency': asNonEmpty(plan.payload['frequency']) ?? 'Monthly',
          'start_date': membership.payload['joined_on'],
          'next_invoice_date': membership.payload['joined_on'],
          'active': 1,
          if (autoSubmit) 'auto_submit': 1,
          if (taxCode != null) 'tax_code': taxCode,
        });
    template.children['items'] = [
      ChildRow(
        id: '', parentId: '', parentDocType: 'Recurring Invoice',
        tableName: 'items', rowIndex: 0,
        payload: {
          'item': plan.payload['membership_item'],
          'qty': 1,
          'rate': fee,
        },
      ),
    ];
    final saved = await _engine.save(template, _roles);

    membership.payload['recurring_invoice'] = saved.id;
    membership.payload['status'] = 'Active';
    return _engine.save(membership, _roles);
  }

  /// Active → Paused: the template goes quiet. Invoices already raised
  /// stand.
  Future<Document> pause(String membershipId) async {
    final membership = await _require(membershipId, expected: {'Active'});
    await _setTemplateActive(membership, false);
    membership.payload['status'] = 'Paused';
    membership.payload['paused_on'] =
        DateTime.now().toIso8601String().split('T').first;
    return _engine.save(membership, _roles);
  }

  /// Paused → Active: the template wakes with its next bill moved to
  /// TODAY when it fell during the pause — the gap is a gift, not a
  /// debt; the runner must never catch-up-bill it.
  Future<Document> resume(String membershipId) async {
    final membership = await _require(membershipId, expected: {'Paused'});
    final today = DateTime.now().toIso8601String().split('T').first;
    final templateId =
        asNonEmpty(membership.payload['recurring_invoice']);
    if (templateId != null) {
      final template =
          await _engine.fetch('Recurring Invoice', templateId);
      if (template != null) {
        template.payload['active'] = 1;
        final next = asNonEmpty(template.payload['next_invoice_date']);
        if (next == null || next.compareTo(today) < 0) {
          template.payload['next_invoice_date'] = today;
        }
        await _engine.save(template, _roles);
      }
    }
    membership.payload['status'] = 'Active';
    membership.payload['paused_on'] = '';
    return _engine.save(membership, _roles);
  }

  /// Active/Paused → Cancelled: billing ends for good; the record and
  /// every raised invoice stay.
  Future<Document> cancel(String membershipId) async {
    final membership =
        await _require(membershipId, expected: {'Active', 'Paused'});
    await _setTemplateActive(membership, false,
        endDate: DateTime.now().toIso8601String().split('T').first);
    membership.payload['status'] = 'Cancelled';
    membership.payload['cancelled_on'] =
        DateTime.now().toIso8601String().split('T').first;
    return _engine.save(membership, _roles);
  }

  /// Every non-cancelled membership with its billing state and arrears,
  /// worst first.
  Future<List<MemberRollLine>> memberRoll() async {
    final memberships = [
      for (final m in await _engine.list('Membership', userRoles: _roles))
        if ('${m.payload['status']}' == 'Active' ||
            '${m.payload['status']}' == 'Paused')
          m,
    ];
    if (memberships.isEmpty) return const [];

    final planNames = <String, Document>{
      for (final p
          in await _engine.list('Membership Plan', userRoles: _roles))
        p.id: p,
    };
    final outstandingByTemplate = <String, num>{};
    for (final inv
        in await _engine.list('Sales Invoice', userRoles: _roles)) {
      if (inv.docStatus != 1) continue;
      final template = asNonEmpty(inv.payload['recurring_invoice']);
      if (template == null) continue;
      final owed = inv.payload.containsKey('outstanding_amount')
          ? asNum(inv.payload['outstanding_amount'])
          : asNum(inv.payload['grand_total']);
      outstandingByTemplate[template] =
          (outstandingByTemplate[template] ?? 0) + owed;
    }

    final lines = <MemberRollLine>[];
    for (final membership in memberships) {
      final plan = planNames['${membership.payload['plan']}'];
      final templateId =
          asNonEmpty(membership.payload['recurring_invoice']);
      String? nextDate;
      if (templateId != null &&
          '${membership.payload['status']}' == 'Active') {
        final template =
            await _engine.fetch('Recurring Invoice', templateId);
        nextDate = asNonEmpty(template?.payload['next_invoice_date']);
      }
      lines.add(MemberRollLine(
        membership: membership,
        member: '${membership.payload['member']}',
        planName: plan == null
            ? '${membership.payload['plan']}'
            : '${plan.payload['plan_name']}',
        fee: asNum(plan?.payload['fee']),
        frequency: asNonEmpty(plan?.payload['frequency']) ?? 'Monthly',
        nextInvoiceDate: nextDate,
        arrears: round2(
            templateId == null ? 0 : outstandingByTemplate[templateId] ?? 0),
      ));
    }
    lines.sort((a, b) => b.arrears.compareTo(a.arrears));
    return lines;
  }

  Future<void> _setTemplateActive(Document membership, bool active,
      {String? endDate}) async {
    final templateId =
        asNonEmpty(membership.payload['recurring_invoice']);
    if (templateId == null) return;
    final template = await _engine.fetch('Recurring Invoice', templateId);
    if (template == null) return;
    template.payload['active'] = active ? 1 : 0;
    if (endDate != null) template.payload['end_date'] = endDate;
    await _engine.save(template, _roles);
  }

  Future<Document> _require(String membershipId,
      {required Set<String> expected}) async {
    final membership =
        await _engine.fetch('Membership', membershipId);
    if (membership == null) {
      throw StateError('Membership $membershipId not found.');
    }
    if (!expected.contains('${membership.payload['status']}')) {
      throw StateError(
          'Membership $membershipId is ${membership.payload['status']}, '
          'not ${expected.join('/')}.');
    }
    return membership;
  }
}
