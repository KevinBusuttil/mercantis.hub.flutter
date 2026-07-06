import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_hub_app/ledger/hub_interceptors.dart';
import 'package:mercantis_hub_app/ledger/ledger_derivation.dart';
import 'package:mercantis_hub_app/ledger/ledger_derivation_service.dart';
import 'package:mercantis_hub_app/ledger/ledger_values.dart';
import 'package:mercantis_hub_app/manifest/hub_manifest.dart';
import 'package:mercantis_hub_app/onboarding/hub_seeder.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The lightweight Expense: interceptor-stamped totals, balanced GL (paid →
/// credit cash, unpaid → credit payable + supplier subledger), input VAT in
/// the Tax Transaction subledger, and it lands in the P&L via the GL.
void main() {
  setUpAll(sqfliteFfiInit);

  late MercantisDatabase db;
  late DocumentEngine engine;
  late EventEmitter emitter;
  late LedgerDerivationService ledger;
  const roles = {'System Manager'};
  final today = DateTime.now().toIso8601String().split('T').first;

  setUp(() async {
    db = await MercantisDatabase.open(
        factory: databaseFactoryFfi, path: inMemoryDatabasePath);
    final registry = MetadataRegistry(db.db);
    final sync = SyncEngine(database: db.db, registry: registry);
    await AppInstaller(database: db.db, registry: registry, syncEngine: sync)
        .install(HubManifest.build());
    emitter = EventEmitter();
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
        BusinessProfileDefaultsInterceptor(),
        FiscalYearGuardInterceptor(),
        ExpenseDefaultsInterceptor(),
      ],
    );
    await HubSeeder(engine, roles: roles).seed(
        businessName: 'Acme', currencyCode: 'EUR', year: DateTime.now().year);
    ledger = LedgerDerivationService(engine: engine, emitter: emitter);
    ledger.start();
    await engine.save(
        Document(id: 'SUPP-1', docType: 'Supplier', payload: {
          'supplier_name': 'Apex',
          'supplier_type': 'Company',
        }),
        roles);
    // A known 18% VAT code with an explicit account.
    await engine.save(
        Document(id: 'VAT18', docType: 'Tax Code', payload: {
          'tax_code_name': 'VAT 18%',
          'tax_type': 'VAT',
          'rate': 18,
          'tax_account': 'VAT',
          'enabled': 1,
        }),
        roles);
  });

  tearDown(() async {
    ledger.dispose();
    await db.close();
  });

  Future<void> until(Future<bool> Function() cond) async {
    for (var i = 0; i < 80; i++) {
      if (await cond()) return;
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    fail('derivation did not settle');
  }

  Future<num> voucherAccount(String account, String voucherNo) async {
    final rows = await engine.list('GL Entry',
        filters: {'account': account, 'voucher_no': voucherNo},
        userRoles: roles);
    num bal = 0;
    for (final r in rows) {
      bal += asNum(r.payload['debit']) - asNum(r.payload['credit']);
    }
    return bal;
  }

  test('interceptor computes VAT from the code and stamps gross', () async {
    final e = await engine.save(
        Document(id: '', docType: 'Expense', payload: {
          'posting_date': today,
          'description': 'Fuel',
          'expense_account': 'COGS',
          'net_amount': 100,
          'tax_code': 'VAT18',
        }),
        roles);
    expect(asNum(e.payload['tax_amount']), 18);
    expect(asNum(e.payload['gross_amount']), 118);
    expect(e.payload['tax_account'], 'VAT');
  });

  test('paid expense: Dr category + Dr VAT / Cr cash; VAT in the subledger',
      () async {
    final e = await engine.submit(
        await engine.save(
            Document(id: '', docType: 'Expense', payload: {
              'posting_date': today,
              'description': 'Fuel',
              'expense_account': 'COGS',
              'net_amount': 100,
              'tax_code': 'VAT18',
              'is_paid': 1,
            }),
            roles),
        roles);
    await until(() async => (await engine.list('GL Entry',
            filters: {'voucher_no': e.id}, userRoles: roles))
        .isNotEmpty);

    expect(await voucherAccount('COGS', e.id), 100);
    expect(await voucherAccount('VAT', e.id), 18);
    expect(await voucherAccount('Bank', e.id), -118); // default cash account

    final tts = await engine.list('Tax Transaction',
        filters: {'voucher_no': e.id}, userRoles: roles);
    expect(tts.length, 1);
    expect(asNum(tts.first.payload['tax_amount']), 18);
    expect(tts.first.payload['party_type'], 'Supplier');
  });

  test('unpaid expense credits the payable and books the supplier subledger',
      () async {
    final e = await engine.submit(
        await engine.save(
            Document(id: '', docType: 'Expense', payload: {
              'posting_date': today,
              'description': 'Accountancy fee',
              'supplier': 'SUPP-1',
              'expense_account': 'COGS',
              'net_amount': 200,
              'is_paid': 0,
            }),
            roles),
        roles);
    await until(() async => (await engine.list('GL Entry',
            filters: {'voucher_no': e.id}, userRoles: roles))
        .isNotEmpty);

    expect(await voucherAccount('Creditors', e.id), -200);
    expect(await voucherAccount('Bank', e.id), 0);

    final vts = await engine.list('Supplier Transaction',
        filters: {'voucher_no': e.id}, userRoles: roles);
    expect(vts.length, 1);
    expect(asNum(vts.first.payload['amount']), 200); // we owe the supplier
  });

  test('cancel reverses the expense exactly', () async {
    final e = await engine.submit(
        await engine.save(
            Document(id: '', docType: 'Expense', payload: {
              'posting_date': today,
              'description': 'Fuel',
              'expense_account': 'COGS',
              'net_amount': 100,
              'is_paid': 1,
            }),
            roles),
        roles);
    await until(() async => (await engine.list('GL Entry',
            filters: {'voucher_no': e.id}, userRoles: roles))
        .isNotEmpty);
    final before = (await engine.list('GL Entry',
            filters: {'voucher_no': e.id}, userRoles: roles))
        .length;
    await engine.cancel(e, roles);
    await until(() async => (await engine.list('GL Entry',
                filters: {'voucher_no': e.id}, userRoles: roles))
            .length >=
        before * 2);
    expect(await voucherAccount('COGS', e.id), 0);
    expect(await voucherAccount('Bank', e.id), 0);
  });

  test('pure derivation balances', () {
    final rows = LedgerDerivation.derive(
        Document(id: 'EXP-1', docType: 'Expense', payload: {
          'posting_date': today,
          'expense_account': 'COGS',
          'tax_account': 'VAT',
          'net_amount': 100,
          'tax_amount': 18,
          'gross_amount': 118,
          'is_paid': 1,
          'paid_from': 'Bank',
        }),
        reversal: false);
    num debit = 0, credit = 0;
    for (final r in rows) {
      if (r.docType != 'GL Entry') continue;
      debit += asNum(r.payload['debit']);
      credit += asNum(r.payload['credit']);
    }
    expect(debit, 118);
    expect(credit, 118);
  });
}
