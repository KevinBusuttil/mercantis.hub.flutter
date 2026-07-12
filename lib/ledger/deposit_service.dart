import 'package:mercantis_core/mercantis_core.dart';

import 'ledger_values.dart';

const _systemRoles = {'System Manager'};

/// One deposit with its computed application state (S4). `applied` is the
/// sum of submitted Payment Entries that name this deposit — computed, never
/// stored, so Solo and Team replicas can't drift.
class DepositRow {
  const DepositRow({
    required this.deposit,
    required this.applied,
  });

  final Document deposit;
  final num applied;

  num get amount => asNum(deposit.payload['amount']);
  num get outstanding => amount - applied;
}

/// Deposit arithmetic shared by the report screen and the Payment Entry
/// guard: how much of a Customer Deposit has been applied, and what remains.
class DepositService {
  DepositService(this._engine);

  final DocumentEngine _engine;

  /// Sum of submitted Payment Entries applying [depositId]. A cancelled
  /// application (docstatus 2) no longer counts.
  Future<num> applied(String depositId, {String? excludingPayment}) async {
    final payments =
        await _engine.list('Payment Entry', userRoles: _systemRoles);
    num total = 0;
    for (final p in payments) {
      if (p.docStatus != 1) continue;
      if (asNonEmpty(p.payload['deposit']) != depositId) continue;
      if (excludingPayment != null && p.id == excludingPayment) continue;
      total += asNum(p.payload['paid_amount']);
    }
    return total;
  }

  /// All submitted deposits, newest first, with their application state.
  /// Cancelled deposits are excluded; drafts show with zero applied.
  Future<List<DepositRow>> liabilityReport() async {
    final deposits =
        await _engine.list('Customer Deposit', userRoles: _systemRoles);
    final rows = <DepositRow>[];
    for (final d in deposits) {
      if (d.docStatus == 2) continue;
      rows.add(DepositRow(deposit: d, applied: await applied(d.id)));
    }
    rows.sort((a, b) => '${b.deposit.payload['posting_date']}'
        .compareTo('${a.deposit.payload['posting_date']}'));
    return rows;
  }
}

/// Payment-Entry side of deposit application (S4). When `deposit` is set on
/// a Receive payment:
///  * `paid_to` defaults to the deposit's liability account (the whole
///    point — the GL debits prepayment liability instead of cash) and the
///    party defaults to the deposit's customer;
///  * at submit, the deposit must be submitted, belong to the same
///    customer, and still have enough unapplied balance — over-application
///    is blocked here AND by the Team backend's allocation guards.
class DepositApplicationInterceptor extends DocumentInterceptor {
  const DepositApplicationInterceptor();

  @override
  Future<void> beforeSave(
      DocumentEngine engine, Document doc, DocType docType,
      {required bool isNew}) async {
    if (docType.id != 'Payment Entry') return;
    final depositId = asNonEmpty(doc.payload['deposit']);
    if (depositId == null) return;
    // Only a Receive payment can consume a customer deposit; autofilling a
    // Pay/Internal Transfer here would aim its GL at the deposit liability.
    if ('${doc.payload['payment_type']}' != 'Receive') return;
    final deposit = await engine.fetch('Customer Deposit', depositId);
    if (deposit == null) return;
    if (asNonEmpty(doc.payload['paid_to']) == null) {
      final account = asNonEmpty(deposit.payload['deposit_account']);
      if (account != null) doc.payload['paid_to'] = account;
    }
    if (asNonEmpty(doc.payload['party']) == null) {
      doc.payload['party_type'] = 'Customer';
      doc.payload['party'] = deposit.payload['customer'];
    }
  }

  @override
  Future<void> beforeSubmit(
      DocumentEngine engine, Document doc, DocType docType) async {
    if (docType.id != 'Payment Entry') return;
    final depositId = asNonEmpty(doc.payload['deposit']);
    if (depositId == null) return;
    if ('${doc.payload['payment_type']}' != 'Receive') {
      throw StateError(
          'A Customer Deposit applies through a Receive payment — this '
          'entry is ${doc.payload['payment_type']}.');
    }

    final deposit = await engine.fetch('Customer Deposit', depositId);
    if (deposit == null || deposit.docStatus != 1) {
      throw StateError(
          'Deposit $depositId is not submitted — submit it before applying.');
    }
    final customer = asNonEmpty(deposit.payload['customer']);
    if (asNonEmpty(doc.payload['party']) != customer) {
      throw StateError(
          'Deposit $depositId belongs to $customer, not this party.');
    }
    final applied = await DepositService(engine)
        .applied(depositId, excludingPayment: doc.id);
    final remaining = asNum(deposit.payload['amount']) - applied;
    final paying = asNum(doc.payload['paid_amount']);
    if (paying > remaining + 0.005) {
      throw StateError(
          'Deposit $depositId has ${remaining.toStringAsFixed(2)} left; '
          'this application of ${paying.toStringAsFixed(2)} exceeds it.');
    }
  }
}
