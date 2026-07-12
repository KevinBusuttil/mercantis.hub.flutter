import 'package:mercantis_core/mercantis_core.dart';

import '../ledger/deposit_service.dart';
import '../ledger/ledger_values.dart';
import '../scheduling/scheduling_service.dart';

const _systemRoles = {'System Manager'};

/// One staff member's commission over a period: how many completed
/// bookings, the invoiced net they produced, and what they earned.
class CommissionLine {
  const CommissionLine({
    required this.resource,
    required this.appointments,
    required this.base,
    required this.commission,
  });

  final String resource;
  final int appointments;
  final num base;
  final num commission;
}

/// Phase 4: the appointments composition — booking with a deposit up
/// front, completion to a settled invoice, commission on the result.
/// Nothing here is new machinery: S1 books the slot (conflict-checked by
/// the interceptor), S4 holds the deposit as a liability and applies it
/// through a Receive Payment Entry, S8 prices the drafted invoice, and
/// S9 is a percentage over what the ledger already knows.
class BookingService {
  BookingService(this._engine, {Set<String> roles = _systemRoles})
      : _roles = roles;

  final DocumentEngine _engine;
  final Set<String> _roles;

  /// Books [serviceItem] on [resource] for [customer]. The appointment
  /// saves FIRST — if the slot clashes, nothing else is created. A
  /// [depositAmount] > 0 then takes an S4 Customer Deposit (submitted,
  /// so it posts Dr cash / Cr liability) and stamps it on the booking.
  Future<Document> book({
    required String resource,
    required String customer,
    required String serviceItem,
    required DateTime startsAt,
    required DateTime endsAt,
    String? subject,
    num qty = 1,
    num depositAmount = 0,
    String? cashAccount,
    String? depositAccount,
    String? modeOfPayment,
    String? notes,
  }) async {
    final appointment = await _engine.save(
        Document(id: '', docType: 'Appointment', payload: {
          'subject': subject ?? serviceItem,
          'resource': resource,
          'customer': customer,
          'starts_at': startsAt.toIso8601String(),
          'ends_at': endsAt.toIso8601String(),
          'status': 'Scheduled',
          'service_item': serviceItem,
          'qty': qty,
          if (notes != null && notes.isNotEmpty) 'notes': notes,
        }),
        _roles);
    if (depositAmount <= 0) return appointment;

    // The deposit inherits the booking's company (which the defaults
    // interceptor stamped at save) — multi-company books must not hold
    // the liability under the wrong company.
    final deposit = await _engine.submit(
        await _engine.save(
            Document(id: '', docType: 'Customer Deposit',
                company: appointment.company,
                payload: {
              'customer': customer,
              'posting_date':
                  DateTime.now().toIso8601String().split('T').first,
              'amount': depositAmount,
              if (cashAccount != null) 'cash_account': cashAccount,
              if (depositAccount != null) 'deposit_account': depositAccount,
              if (modeOfPayment != null) 'mode_of_payment': modeOfPayment,
              'remarks': 'Booking deposit for ${appointment.id}',
            }),
            _roles),
        _roles);

    appointment.payload['deposit'] = deposit.id;
    return _engine.save(appointment, _roles);
  }

  /// Completes a booking into money: drafts the invoice through the S1
  /// hook (S8 fills the rate), submits it, then auto-applies whatever
  /// remains of the booking deposit against it — a Receive Payment Entry
  /// whose paid_to is the deposit liability, so the GL moves prepayment
  /// onto the receivable without touching cash. Returns the submitted
  /// invoice.
  Future<Document> completeBooking(String appointmentId) async {
    final draft = await SchedulingService(_engine)
        .invoiceFor(appointmentId, roles: _roles);
    final invoice = await _engine.submit(draft, _roles);

    final appointment = await _engine.fetch('Appointment', appointmentId);
    final depositId = asNonEmpty(appointment?.payload['deposit']);
    if (depositId != null) {
      final deposit = await _engine.fetch('Customer Deposit', depositId);
      if (deposit != null && deposit.docStatus == 1) {
        final applied = await DepositService(_engine).applied(depositId);
        final remaining = asNum(deposit.payload['amount']) - applied;
        final due = asNum(invoice.payload['grand_total']);
        final apply = remaining < due ? remaining : due;
        if (apply > 0.005) {
          final application = await _engine.save(
              Document(id: '', docType: 'Payment Entry',
                  company: invoice.company,
                  payload: {
                'payment_type': 'Receive',
                'posting_date':
                    DateTime.now().toIso8601String().split('T').first,
                'deposit': depositId,
                if (asNonEmpty(invoice.payload['debit_to']) != null)
                  'paid_from': invoice.payload['debit_to'],
                'paid_amount': apply,
                'remarks': 'Booking deposit applied — $appointmentId',
              })
                ..children['references'] = [
                  ChildRow(
                    id: '', parentId: '', parentDocType: 'Payment Entry',
                    tableName: 'references', rowIndex: 0,
                    payload: {
                      'reference_doctype': 'Sales Invoice',
                      'reference_name': invoice.id,
                      'allocated_amount': apply,
                    },
                  ),
                ],
              _roles);
          await _engine.submit(application, _roles);
        }
      }
    }
    return invoice;
  }

  /// S9: commission per resource over [from, to] (posting-date strings,
  /// inclusive; null = unbounded). The base is the invoiced NET of each
  /// completed appointment's submitted invoice; an item-specific rule
  /// beats the general one; resources without an enabled rule earn
  /// nothing and don't appear.
  Future<List<CommissionLine>> computeCommissions(
      {String? from, String? to}) async {
    final rulesByResource = <String, List<Document>>{};
    for (final rule
        in await _engine.list('Commission Rule', userRoles: _roles)) {
      if (!(rule.payload['enabled'] == null ||
          isTrue(rule.payload['enabled']))) {
        continue;
      }
      rulesByResource
          .putIfAbsent('${rule.payload['resource']}', () => [])
          .add(rule);
    }
    if (rulesByResource.isEmpty) return const [];

    final count = <String, int>{};
    final base = <String, num>{};
    final commission = <String, num>{};

    for (final a
        in await _engine.list('Appointment', userRoles: _roles)) {
      final invoiceId = asNonEmpty(a.payload['sales_invoice']);
      if (invoiceId == null) continue;
      final resource = '${a.payload['resource']}';
      final rules = rulesByResource[resource];
      if (rules == null) continue;

      final invoice = await _engine.fetch('Sales Invoice', invoiceId);
      if (invoice == null || invoice.docStatus != 1) continue;
      final postingDate = '${invoice.payload['posting_date']}';
      if (from != null && postingDate.compareTo(from) < 0) continue;
      if (to != null && postingDate.compareTo(to) > 0) continue;

      final serviceItem = asNonEmpty(a.payload['service_item']);
      Document? match;
      for (final rule in rules) {
        final ruleItem = asNonEmpty(rule.payload['service_item']);
        if (ruleItem != null && ruleItem == serviceItem) {
          match = rule;
          break; // item-specific wins outright
        }
        if (ruleItem == null) match ??= rule;
      }
      if (match == null) continue;

      final net = asNum(invoice.payload['net_total']) != 0
          ? asNum(invoice.payload['net_total'])
          : asNum(invoice.payload['total']);
      count[resource] = (count[resource] ?? 0) + 1;
      base[resource] = (base[resource] ?? 0) + net;
      commission[resource] = (commission[resource] ?? 0) +
          net * asNum(match.payload['percent']) / 100;
    }

    final lines = [
      for (final resource in count.keys)
        CommissionLine(
          resource: resource,
          appointments: count[resource]!,
          base: round2(base[resource]!),
          commission: round2(commission[resource]!),
        ),
    ]..sort((a, b) => b.commission.compareTo(a.commission));
    return lines;
  }
}
