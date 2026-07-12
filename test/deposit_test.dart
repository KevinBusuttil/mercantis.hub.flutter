import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_hub_app/ledger/deposit_service.dart';
import 'package:mercantis_hub_app/ledger/hub_interceptors.dart';
import 'package:mercantis_hub_app/ledger/ledger_derivation_service.dart';
import 'package:mercantis_hub_app/ledger/ledger_values.dart' hide isTrue;
import 'package:mercantis_hub_app/manifest/hub_manifest.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// S4 deposits & prepayments: money taken before the invoice posts to a
/// LIABILITY, not income or receivable; applying it later is a Payment
/// Entry whose paid_to IS the liability account, settling the invoice
/// through the ordinary settlement machinery.
void main() {
  setUpAll(sqfliteFfiInit);

  late MercantisDatabase db;
  late DocumentEngine engine;
  late LedgerDerivationService ledger;
  late DepositService deposits;
  const roles = {'System Manager'};
  const today = '2026-07-11';

  Future<void> until(Future<bool> Function() ready) async {
    for (var i = 0; i < 100; i++) {
      if (await ready()) return;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    fail('condition never became true');
  }

  Future<num> glBalance(String account) async {
    num balance = 0;
    for (final gl in await engine.list('GL Entry', userRoles: roles)) {
      if (gl.payload['account'] != account) continue;
      balance += asNum(gl.payload['debit']) - asNum(gl.payload['credit']);
    }
    return balance;
  }

  setUp(() async {
    db = await MercantisDatabase.open(
        factory: databaseFactoryFfi, path: inMemoryDatabasePath);
    final registry = MetadataRegistry(db.db);
    final sync = SyncEngine(database: db.db, registry: registry);
    await AppInstaller(database: db.db, registry: registry, syncEngine: sync)
        .install(HubManifest.build());
    final emitter = EventEmitter();
    engine = DocumentEngine(
      database: db.db,
      registry: registry,
      metaComposer: MetaComposer(registry, db.db),
      permissionEngine: const PermissionEngine(),
      workflowEngine: WorkflowEngine(db.db),
      expressionEvaluator: ExpressionEvaluator(),
      namingService: NamingService(),
      syncEngine: sync,
      emitter: emitter,
      deviceId: 'devA',
      userId: 'u',
      interceptors: const [
        LineItemTotalsInterceptor(),
        TaxCalculationInterceptor(),
        DepositApplicationInterceptor(),
      ],
    );
    ledger = LedgerDerivationService(engine: engine, emitter: emitter)
      ..start();
    deposits = DepositService(engine);

    for (final account in ['Bank', 'Customer Deposits', 'Debtors', 'Sales']) {
      await engine.save(
          Document(id: account, docType: 'Account', payload: {
            'account_name': account,
            'root_type': account == 'Bank'
                ? 'Asset'
                : account == 'Sales'
                    ? 'Income'
                    : account == 'Debtors'
                        ? 'Asset'
                        : 'Liability',
          }),
          roles);
    }
    await engine.save(
        Document(id: 'CUST-1', docType: 'Customer', payload: {
          'customer_name': 'C',
          'customer_type': 'Company',
        }),
        roles);
    await engine.save(
        Document(id: 'ITEM-A', docType: 'Item', payload: {
          'item_code': 'ITEM-A', 'item_name': 'A',
          'item_type': 'Service', 'stock_uom': 'Nos',
        }),
        roles);
  });

  tearDown(() async {
    ledger.dispose();
    await db.close();
  });

  Future<Document> submittedDeposit(num amount) async {
    final dep = await engine.save(
        Document(id: '', docType: 'Customer Deposit', payload: {
          'customer': 'CUST-1',
          'posting_date': today,
          'amount': amount,
          'cash_account': 'Bank',
          'deposit_account': 'Customer Deposits',
        }),
        roles);
    final posted = await engine.submit(dep, roles);
    await until(() async =>
        (await engine.list('GL Entry', userRoles: roles))
            .where((g) => g.payload['voucher_no'] == posted.id)
            .length >=
        2); // both legs — asserting between them is a race
    return posted;
  }

  Future<Document> submittedInvoice(num amount) async {
    final si = Document(id: '', docType: 'Sales Invoice', payload: {
      'customer': 'CUST-1',
      'posting_date': today,
      'debit_to': 'Debtors',
      'income_account': 'Sales',
    });
    si.children['items'] = [
      ChildRow(
        id: '', parentId: '', parentDocType: 'Sales Invoice',
        tableName: 'items', rowIndex: 0,
        payload: {'item': 'ITEM-A', 'qty': 1, 'rate': amount},
      ),
    ];
    final posted = await engine.submit(await engine.save(si, roles), roles);
    await until(() async =>
        (await engine.list('GL Entry', userRoles: roles)).any(
            (g) => g.payload['voucher_no'] == posted.id));
    return posted;
  }

  test('a deposit posts Dr cash / Cr liability — no income, no receivable',
      () async {
    await submittedDeposit(500);
    expect(await glBalance('Bank'), 500);
    expect(await glBalance('Customer Deposits'), -500); // credit balance
    expect(await glBalance('Debtors'), 0);
    expect(await glBalance('Sales'), 0);
  });

  test('applying a deposit moves liability onto the invoice', () async {
    final dep = await submittedDeposit(500);
    final invoice = await submittedInvoice(300);

    final pe = await engine.save(
        Document(id: '', docType: 'Payment Entry', payload: {
          'payment_type': 'Receive',
          'posting_date': today,
          'deposit': dep.id,
          'paid_from': 'Debtors',
          'paid_amount': 300,
        })
          ..children['references'] = [
            ChildRow(
              id: '', parentId: '', parentDocType: 'Payment Entry',
              tableName: 'references', rowIndex: 0,
              payload: {
                'reference_doctype': 'Sales Invoice',
                'reference_name': invoice.id,
                'allocated_amount': 300,
              },
            ),
          ],
        roles);
    // The interceptor pointed paid_to at the deposit's liability account
    // and filled the party from the deposit.
    expect(pe.payload['paid_to'], 'Customer Deposits');
    expect(pe.payload['party'], 'CUST-1');

    await engine.submit(pe, roles);
    await until(() async =>
        asNum((await engine.fetch('Sales Invoice', invoice.id))!
            .payload['outstanding_amount']) ==
        0);

    // Liability shrank by the application; no cash moved.
    expect(await glBalance('Customer Deposits'), -200);
    expect(await glBalance('Bank'), 500);
    expect(await deposits.applied(dep.id), 300);

    final report = await deposits.liabilityReport();
    expect(report.single.outstanding, 200);
  });

  test('over-applying a deposit is blocked at submit', () async {
    final dep = await submittedDeposit(100);
    final pe = await engine.save(
        Document(id: '', docType: 'Payment Entry', payload: {
          'payment_type': 'Receive',
          'posting_date': today,
          'deposit': dep.id,
          'paid_from': 'Debtors',
          'paid_amount': 150, // more than the deposit holds
        }),
        roles);
    await expectLater(engine.submit(pe, roles), throwsA(isA<StateError>()));

    // Two applications that together exceed it: second one dies.
    final ok = await engine.save(
        Document(id: '', docType: 'Payment Entry', payload: {
          'payment_type': 'Receive',
          'posting_date': today,
          'deposit': dep.id,
          'paid_from': 'Debtors',
          'paid_amount': 80,
        }),
        roles);
    await engine.submit(ok, roles);
    final second = await engine.save(
        Document(id: '', docType: 'Payment Entry', payload: {
          'payment_type': 'Receive',
          'posting_date': today,
          'deposit': dep.id,
          'paid_from': 'Debtors',
          'paid_amount': 30, // only 20 left
        }),
        roles);
    await expectLater(
        engine.submit(second, roles), throwsA(isA<StateError>()));
  });

  // Codex review (PR #166): a deposit consumes through a Receive payment
  // ONLY — a Pay entry naming one must neither autofill nor submit.
  test('non-Receive payments cannot apply a deposit', () async {
    final dep = await submittedDeposit(100);
    final pe = await engine.save(
        Document(id: '', docType: 'Payment Entry', payload: {
          'payment_type': 'Pay',
          'posting_date': today,
          'deposit': dep.id,
          'paid_from': 'Bank',
          'paid_to': 'Debtors',
          'party_type': 'Supplier',
          'paid_amount': 50,
        }),
        roles);
    // beforeSave left the Pay entry alone…
    expect(pe.payload['paid_to'], 'Debtors');
    expect(pe.payload['party'], isNull);
    // …and submit refuses outright.
    await expectLater(
      engine.submit(pe, roles),
      throwsA(isA<StateError>().having(
          (e) => '$e', 'message', contains('Receive'))),
    );
  });

  test('a draft deposit cannot be applied', () async {
    final draft = await engine.save(
        Document(id: '', docType: 'Customer Deposit', payload: {
          'customer': 'CUST-1',
          'posting_date': today,
          'amount': 100,
          'cash_account': 'Bank',
          'deposit_account': 'Customer Deposits',
        }),
        roles);
    final pe = await engine.save(
        Document(id: '', docType: 'Payment Entry', payload: {
          'payment_type': 'Receive',
          'posting_date': today,
          'deposit': draft.id,
          'paid_from': 'Debtors',
          'paid_amount': 50,
        }),
        roles);
    await expectLater(engine.submit(pe, roles), throwsA(isA<StateError>()));
  });

  test('cancelling a deposit reverses its GL', () async {
    final dep = await submittedDeposit(500);
    await engine.cancel(dep, roles);
    await until(() async => (await glBalance('Customer Deposits')) == 0);
    expect(await glBalance('Bank'), 0);
    // Cancelled deposits drop off the liability report.
    expect(await deposits.liabilityReport(), isEmpty);
  });
}
