import 'package:mercantis_core/mercantis_core.dart';

import '../ledger/deposit_service.dart';
import '../ledger/ledger_values.dart';
import '../scheduling/scheduling_service.dart';

const _systemRoles = {'System Manager'};

/// V3: the hire lifecycle. Booking holds the unit's calendar (the S1
/// conflict interceptor makes double-hiring impossible) and can take an
/// S4 deposit; handover and return are recorded moments; return bills
/// the chargeable days as an ordinary Sales Invoice with the deposit
/// auto-applied.
class RentalService {
  RentalService(this._engine, {Set<String> roles = _systemRoles})
      : _roles = roles;

  final DocumentEngine _engine;
  final Set<String> _roles;

  /// What (if anything) blocks [unitId] over the window. Empty = free.
  Future<List<ScheduleConflict>> availability(
      String unitId, DateTime from, DateTime to) async {
    final unit = await _requireUnit(unitId);
    return SchedulingService(_engine).conflicts(
      resource: '${unit.payload['resource']}',
      startsAt: from,
      endsAt: to,
    );
  }

  /// Books a hire: the availability hold saves FIRST (a clash dies on
  /// the S1 interceptor and creates nothing else), then the agreement,
  /// then the optional S4 deposit — submitted and stamped on it.
  Future<Document> book({
    required String unitId,
    required String customer,
    required DateTime from,
    required DateTime to,
    num? dailyRate,
    num depositAmount = 0,
    String? cashAccount,
    String? depositAccount,
    String? notes,
  }) async {
    final unit = await _requireUnit(unitId);
    if (!(unit.payload['enabled'] == null ||
        isTrue(unit.payload['enabled']))) {
      throw StateError('Unit $unitId is disabled.');
    }

    // Everything the hire creates inherits the UNIT's company —
    // multi-company books must not fall to the defaults interceptor's
    // first company.
    final hold = await _engine.save(
        Document(id: '', docType: 'Appointment', company: unit.company,
            payload: {
          'subject': 'HIRE ${unit.payload['unit_name']} — $customer',
          'resource': unit.payload['resource'],
          'customer': customer,
          'starts_at': from.toIso8601String(),
          'ends_at': to.toIso8601String(),
          'status': 'Scheduled',
        }),
        _roles);

    final agreement = await _engine.save(
        Document(id: '', docType: 'Rental Agreement',
            company: unit.company, payload: {
          'customer': customer,
          'unit': unit.id,
          'status': 'Draft',
          'starts_at': from.toIso8601String(),
          'ends_at': to.toIso8601String(),
          'daily_rate': dailyRate ?? asNum(unit.payload['daily_rate']),
          'appointment': hold.id,
          if (notes != null && notes.isNotEmpty) 'notes': notes,
        }),
        _roles);

    if (depositAmount > 0) {
      final deposit = await _engine.submit(
          await _engine.save(
              Document(id: '', docType: 'Customer Deposit',
                  company: agreement.company,
                  payload: {
                'customer': customer,
                'posting_date':
                    DateTime.now().toIso8601String().split('T').first,
                'amount': depositAmount,
                if (cashAccount != null) 'cash_account': cashAccount,
                if (depositAccount != null)
                  'deposit_account': depositAccount,
                'remarks': 'Rental deposit for ${agreement.id}',
              }),
              _roles),
          _roles);
      agreement.payload['deposit'] = deposit.id;
      return _engine.save(agreement, _roles);
    }
    return agreement;
  }

  /// Handover: the unit leaves the yard. Draft → Out.
  Future<Document> checkOut(String agreementId, {String? condition}) async {
    final agreement = await _require(agreementId, expected: 'Draft');
    agreement.payload['status'] = 'Out';
    agreement.payload['out_at'] = DateTime.now().toIso8601String();
    if (condition != null && condition.isNotEmpty) {
      agreement.payload['out_condition'] = condition;
    }
    return _engine.save(agreement, _roles);
  }

  /// Whole days charged for a hire: ceil of the elapsed time, minimum 1
  /// — a same-day hire is one day, 3 days + an hour is 4.
  static int chargeableDays(DateTime from, DateTime to) {
    final minutes = to.difference(from).inMinutes;
    if (minutes <= 0) return 1;
    return (minutes + 1439) ~/ 1440;
  }

  /// Return: Out → Returned, billed as days × rate on the unit's rental
  /// item. Late returns charge to the ACTUAL return moment. The invoice
  /// submits and the deposit's remaining balance auto-applies against it
  /// (the S4 interceptor aims paid_to at the liability account). The
  /// calendar hold stays as history — the unit was genuinely out.
  Future<Document> returnUnit(
    String agreementId, {
    String? condition,
    DateTime? asOf,
    String? taxCode,
  }) async {
    final agreement = await _require(agreementId, expected: 'Out');
    final unit = await _requireUnit('${agreement.payload['unit']}');
    final from = DateTime.parse('${agreement.payload['starts_at']}');
    final plannedTo = DateTime.parse('${agreement.payload['ends_at']}');
    final actual = asOf ?? DateTime.now();
    final to = actual.isAfter(plannedTo) ? actual : plannedTo;
    final days = chargeableDays(from, to);
    final rate = asNum(agreement.payload['daily_rate']);

    final invoice = Document(id: '', docType: 'Sales Invoice',
        company: agreement.company, payload: {
      'customer': agreement.payload['customer'],
      'posting_date': actual.toIso8601String().split('T').first,
      if (taxCode != null) 'tax_code': taxCode,
    });
    invoice.children['items'] = [
      ChildRow(
        id: '', parentId: '', parentDocType: 'Sales Invoice',
        tableName: 'items', rowIndex: 0,
        payload: {
          'item': unit.payload['rental_item'],
          'qty': days,
          if (rate > 0) 'rate': rate,
          'description': 'Hire ${unit.payload['unit_name']} '
              '${'${agreement.payload['starts_at']}'.split('T').first} → '
              '${to.toIso8601String().split('T').first} ($days day(s))',
        },
      ),
    ];
    final posted =
        await _engine.submit(await _engine.save(invoice, _roles), _roles);

    final depositId = asNonEmpty(agreement.payload['deposit']);
    if (depositId != null) {
      final deposit = await _engine.fetch('Customer Deposit', depositId);
      if (deposit != null && deposit.docStatus == 1) {
        final applied = await DepositService(_engine).applied(depositId);
        final remaining = asNum(deposit.payload['amount']) - applied;
        final due = asNum(posted.payload['grand_total']);
        final apply = remaining < due ? remaining : due;
        if (apply > 0.005) {
          final application = await _engine.save(
              Document(id: '', docType: 'Payment Entry',
                  company: posted.company,
                  payload: {
                'payment_type': 'Receive',
                'posting_date':
                    actual.toIso8601String().split('T').first,
                'deposit': depositId,
                if (asNonEmpty(posted.payload['debit_to']) != null)
                  'paid_from': posted.payload['debit_to'],
                'paid_amount': apply,
                'remarks': 'Rental deposit applied — $agreementId',
              })
                ..children['references'] = [
                  ChildRow(
                    id: '', parentId: '', parentDocType: 'Payment Entry',
                    tableName: 'references', rowIndex: 0,
                    payload: {
                      'reference_doctype': 'Sales Invoice',
                      'reference_name': posted.id,
                      'allocated_amount': apply,
                    },
                  ),
                ],
              _roles);
          await _engine.submit(application, _roles);
        }
      }
    }

    agreement.payload['status'] = 'Returned';
    agreement.payload['returned_at'] = actual.toIso8601String();
    if (condition != null && condition.isNotEmpty) {
      agreement.payload['return_condition'] = condition;
    }
    agreement.payload['sales_invoice'] = posted.id;
    await _engine.save(agreement, _roles);
    return posted;
  }

  /// Cancels a Draft hire and frees the calendar hold.
  Future<Document> cancelBooking(String agreementId) async {
    final agreement = await _require(agreementId, expected: 'Draft');
    final holdId = asNonEmpty(agreement.payload['appointment']);
    if (holdId != null) {
      final hold = await _engine.fetch('Appointment', holdId);
      if (hold != null) {
        hold.payload['status'] = 'Cancelled';
        await _engine.save(hold, _roles);
      }
    }
    agreement.payload['status'] = 'Cancelled';
    return _engine.save(agreement, _roles);
  }

  Future<Document> _require(String agreementId,
      {required String expected}) async {
    final agreement =
        await _engine.fetch('Rental Agreement', agreementId);
    if (agreement == null) {
      throw StateError('Rental Agreement $agreementId not found.');
    }
    if ('${agreement.payload['status']}' != expected) {
      throw StateError(
          'Rental $agreementId is ${agreement.payload['status']}, '
          'not $expected.');
    }
    return agreement;
  }

  Future<Document> _requireUnit(String unitId) async {
    final unit = await _engine.fetch('Rental Unit', unitId);
    if (unit == null) throw StateError('Rental Unit $unitId not found.');
    return unit;
  }
}
