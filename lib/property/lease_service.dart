import 'package:mercantis_core/mercantis_core.dart';

import '../ledger/ledger_values.dart';

const _systemRoles = {'System Manager'};

/// One rent-roll line: the tenancy, what it bills, when it bills next,
/// and what the tenant owes right now.
class RentRollLine {
  const RentRollLine({
    required this.lease,
    required this.propertyName,
    required this.tenant,
    required this.rent,
    required this.frequency,
    this.nextInvoiceDate,
    required this.arrears,
  });

  final Document lease;
  final String propertyName;
  final String tenant;
  final num rent;
  final String frequency;
  final String? nextInvoiceDate;

  /// Outstanding balance across the rent invoices this lease generated.
  final num arrears;
}

/// V5: the tenancy lifecycle. Activation takes the S4 deposit and writes
/// the Recurring Invoice template — from then on the EXISTING boot
/// runner bills the rent each period; ending the lease deactivates the
/// template. Arrears are computed, never stored: the outstanding
/// balances of the invoices the template generated.
class LeaseService {
  LeaseService(this._engine, {Set<String> roles = _systemRoles})
      : _roles = roles;

  final DocumentEngine _engine;
  final Set<String> _roles;

  /// Draft → Active: optional tenancy deposit (submitted — Dr cash / Cr
  /// liability), then the rent template. auto-submit is ON by default —
  /// rent is contractual, not a judgement call; pass false to route the
  /// drafts through the approvals inbox instead.
  Future<Document> activate(
    String leaseId, {
    num depositAmount = 0,
    String? cashAccount,
    String? depositAccount,
    String? taxCode,
    bool autoSubmit = true,
  }) async {
    final lease = await _require(leaseId, expected: 'Draft');
    final property =
        await _engine.fetch('Property', '${lease.payload['property']}');
    if (property == null) {
      throw StateError(
          'Lease $leaseId points at a missing property '
          '${lease.payload['property']}.');
    }
    final rent = asNum(lease.payload['monthly_rent']);
    if (rent <= 0) {
      throw StateError('Lease $leaseId has no rent amount.');
    }

    if (depositAmount > 0) {
      final deposit = await _engine.submit(
          await _engine.save(
              // The lease's company rides onto everything it creates —
              // in multi-company books the defaults interceptor would
              // otherwise stamp the FIRST company (Codex, PR #169).
              Document(id: '', docType: 'Customer Deposit',
                  company: lease.company, payload: {
                'customer': lease.payload['tenant'],
                'posting_date':
                    DateTime.now().toIso8601String().split('T').first,
                'amount': depositAmount,
                if (cashAccount != null) 'cash_account': cashAccount,
                if (depositAccount != null)
                  'deposit_account': depositAccount,
                'remarks': 'Tenancy deposit for ${lease.id} — '
                    '${property.payload['property_name']}',
              }),
              _roles),
          _roles);
      lease.payload['deposit'] = deposit.id;
    }

    final template = Document(id: '', docType: 'Recurring Invoice',
        company: lease.company,
        payload: {
          'customer': lease.payload['tenant'],
          'frequency': asNonEmpty(lease.payload['frequency']) ?? 'Monthly',
          'start_date': lease.payload['starts_on'],
          'next_invoice_date': lease.payload['starts_on'],
          if (asNonEmpty(lease.payload['ends_on']) != null)
            'end_date': lease.payload['ends_on'],
          'active': 1,
          if (autoSubmit) 'auto_submit': 1,
          if (taxCode != null) 'tax_code': taxCode,
        });
    template.children['items'] = [
      ChildRow(
        id: '', parentId: '', parentDocType: 'Recurring Invoice',
        tableName: 'items', rowIndex: 0,
        payload: {
          'item': lease.payload['rent_item'],
          'qty': 1,
          'rate': rent,
        },
      ),
    ];
    final saved = await _engine.save(template, _roles);

    lease.payload['recurring_invoice'] = saved.id;
    lease.payload['status'] = 'Active';
    return _engine.save(lease, _roles);
  }

  /// Active → Ended: the rent template deactivates so no further period
  /// bills; already-generated invoices stand. The deposit's refund (or
  /// offset against damages) is a manual Payment Entry — a judgement
  /// call, not automation.
  Future<Document> end(String leaseId, {DateTime? asOf}) async {
    final lease = await _require(leaseId, expected: 'Active');
    final when =
        (asOf ?? DateTime.now()).toIso8601String().split('T').first;
    final templateId = asNonEmpty(lease.payload['recurring_invoice']);
    if (templateId != null) {
      final template =
          await _engine.fetch('Recurring Invoice', templateId);
      if (template != null) {
        template.payload['active'] = 0;
        template.payload['end_date'] = when;
        await _engine.save(template, _roles);
      }
    }
    lease.payload['status'] = 'Ended';
    if (asNonEmpty(lease.payload['ends_on']) == null) {
      lease.payload['ends_on'] = when;
    }
    return _engine.save(lease, _roles);
  }

  /// Every Active lease with its billing state and arrears, biggest
  /// arrears first — the landlord's morning list.
  Future<List<RentRollLine>> rentRoll() async {
    final leases = [
      for (final l in await _engine.list('Lease', userRoles: _roles))
        if ('${l.payload['status']}' == 'Active') l,
    ];
    if (leases.isEmpty) return const [];

    final propertyNames = <String, String>{
      for (final p in await _engine.list('Property', userRoles: _roles))
        p.id: '${p.payload['property_name']}',
    };
    // One pass over invoices: template id → outstanding total. An
    // invoice the settlement machinery hasn't touched yet has no
    // outstanding_amount key — nothing is settled, so it owes in full.
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

    final lines = <RentRollLine>[];
    for (final lease in leases) {
      final templateId = asNonEmpty(lease.payload['recurring_invoice']);
      String? nextDate;
      if (templateId != null) {
        final template =
            await _engine.fetch('Recurring Invoice', templateId);
        nextDate = asNonEmpty(template?.payload['next_invoice_date']);
      }
      lines.add(RentRollLine(
        lease: lease,
        propertyName: propertyNames['${lease.payload['property']}'] ??
            '${lease.payload['property']}',
        tenant: '${lease.payload['tenant']}',
        rent: asNum(lease.payload['monthly_rent']),
        frequency: asNonEmpty(lease.payload['frequency']) ?? 'Monthly',
        nextInvoiceDate: nextDate,
        arrears: round2(
            templateId == null ? 0 : outstandingByTemplate[templateId] ?? 0),
      ));
    }
    lines.sort((a, b) => b.arrears.compareTo(a.arrears));
    return lines;
  }

  Future<Document> _require(String leaseId,
      {required String expected}) async {
    final lease = await _engine.fetch('Lease', leaseId);
    if (lease == null) throw StateError('Lease $leaseId not found.');
    if ('${lease.payload['status']}' != expected) {
      throw StateError(
          'Lease $leaseId is ${lease.payload['status']}, not $expected.');
    }
    return lease;
  }
}
