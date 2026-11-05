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

/// The liability account [deposit] credited: its own `deposit_account`, or
/// the company default the ledger fell back to when it was left blank (the
/// same fallback `LedgerDerivation.accountFallbacks` applies at posting).
Future<String?> depositLiabilityAccount(
    DocumentEngine engine, Document deposit) async {
  final own = asNonEmpty(deposit.payload['deposit_account']);
  if (own != null) return own;
  final id = asNonEmpty(deposit.company);
  final company = id != null
      ? await engine.fetch('Company', id)
      : (await engine.list('Company', userRoles: _systemRoles)).firstOrNull;
  return asNonEmpty(company?.payload['default_customer_deposit_account']);
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

  /// A deposit still applied by a submitted payment cannot be cancelled:
  /// the payment would point at a deposit that no longer exists and the
  /// liability would go negative. Cancel the payments first (the Team server
  /// enforces the same rule; shared contract fixture 0015).
  @override
  Future<void> inLifecycleTransaction(DocumentEngine engine, Document doc,
      DocType docType, UnitOfWork uow, LifecycleAction action) async {
    if (action != LifecycleAction.cancel || doc.docType != 'Customer Deposit') {
      return;
    }
    final rows = await uow.db.query('documents',
        columns: ['id'],
        where: "doctype = 'Payment Entry' AND docstatus = 1 "
            "AND json_extract(payload, '\$.deposit') = ?",
        whereArgs: [doc.id]);
    if (rows.isEmpty) return;
    throw DocumentEngineError.validationFailed([
      ValidationError(
        stage: 'deposit_applied',
        fieldKey: 'docstatus',
        message: 'Deposit ${doc.id} is applied by '
            '${rows.map((r) => r['id']).join(', ')}. Cancel those payments '
            'first, then the deposit.',
      ),
    ]);
  }

  @override
  Future<void> beforeSave(DocumentEngine engine, Document doc, DocType docType,
      {required bool isNew}) async {
    if (docType.id != 'Payment Entry') return;
    final depositId = asNonEmpty(doc.payload['deposit']);
    if (depositId == null) return;
    // Stored trimmed, as the Team server stores it, so every lookup of the
    // deposit's applications matches it.
    doc.payload['deposit'] = depositId;
    // Only a Receive payment can consume a customer deposit; autofilling a
    // Pay/Internal Transfer here would aim its GL at the deposit liability.
    if ('${doc.payload['payment_type']}' != 'Receive') return;
    final deposit = await engine.fetch('Customer Deposit', depositId);
    if (deposit == null) return;
    if (asNonEmpty(doc.payload['paid_to']) == null) {
      final account = await depositLiabilityAccount(engine, deposit);
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

    // Deposits are held in the company currency; a rate would mis-state
    // the liability the application releases. The Team server refuses it
    // too.
    final rate = doc.payload['conversion_rate'];
    if (rate != null &&
        '$rate'.trim().isNotEmpty &&
        (asNum(rate) - 1).abs() > 1e-9) {
      throw StateError(
          'A payment applying deposit $depositId must be in the company '
          'currency (conversion_rate $rate); deposits are held in the '
          'company currency.');
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
    // Applying the deposit is what moves its liability. A payment that names
    // the deposit but debits another account would leave the deposit
    // standing AND count it as applied. The Team server refuses it too.
    final liability = await depositLiabilityAccount(engine, deposit);
    final paidTo = asNonEmpty(doc.payload['paid_to']);
    if (liability != null && paidTo != liability) {
      throw StateError(
          'A payment applying deposit $depositId must debit its liability '
          'account $liability, not ${paidTo ?? 'nothing'}.');
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
