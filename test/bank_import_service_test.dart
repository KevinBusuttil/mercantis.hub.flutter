import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_hub_app/ledger/hub_interceptors.dart';
import 'package:mercantis_hub_app/ledger/ledger_derivation_service.dart';
import 'package:mercantis_hub_app/ledger/ledger_values.dart' hide isTrue;
import 'package:mercantis_hub_app/manifest/hub_manifest.dart';
import 'package:mercantis_hub_app/modules/banking/bank_import_service.dart';
import 'package:mercantis_hub_app/modules/banking/bank_matching_service.dart';
import 'package:mercantis_hub_app/onboarding/hub_seeder.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The banking workbench end to end: CSV import persists lines with
/// deterministic ids (re-import is a no-op), suggestions match submitted
/// payments AND paid expenses, and accepting reconciles the line.
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
        Document(id: 'BA-1', docType: 'Bank Account', payload: {
          'account_name': 'Main current account',
          'gl_account': 'Bank',
        }),
        roles);
  });

  tearDown(() async {
    ledger.dispose();
    await db.close();
  });

  String csv(String date) => 'Date,Description,Reference,Amount\n'
      '$date,COFFEE SHOP,REF-1,-25.00\n'
      '$date,CLIENT TRANSFER,INV-9,500.00\n';

  test('import persists lines; re-import creates nothing new', () async {
    final service = BankImportService(engine: engine);
    final first =
        await service.importCsv(bankAccountId: 'BA-1', csv: csv(today));
    expect(first.imported, 2);
    expect(first.duplicates, 0);

    final again =
        await service.importCsv(bankAccountId: 'BA-1', csv: csv(today));
    expect(again.imported, 0);
    expect(again.duplicates, 2);

    final lines = await engine.list('Bank Statement Line',
        filters: {'bank_account': 'BA-1'}, userRoles: roles);
    expect(lines.length, 2);
    expect(lines.every((l) => l.payload['status'] == 'Unreconciled'), isTrue);
  });

  test('identical rows within one file stay distinct', () async {
    final service = BankImportService(engine: engine);
    final result = await service.importCsv(
      bankAccountId: 'BA-1',
      csv: 'Date,Description,Amount\n'
          '$today,COFFEE,-3.00\n'
          '$today,COFFEE,-3.00\n', // same coffee twice — both real
    );
    expect(result.imported, 2);
  });

  test('a paid expense is suggested for its statement line and reconciles',
      () async {
    await BankImportService(engine: engine)
        .importCsv(bankAccountId: 'BA-1', csv: csv(today));

    // The €25 card charge was a fuel expense paid from the bank account.
    final expense = await engine.submit(
        await engine.save(
            Document(id: '', docType: 'Expense', payload: {
              'posting_date': today,
              'description': 'Coffee with client',
              'expense_account': 'COGS',
              'net_amount': 25,
              'is_paid': 1,
              'paid_from': 'Bank',
            }),
            roles),
        roles);

    final matching = BankMatchingService(engine: engine);
    final suggestions = await matching.suggest('BA-1');
    expect(suggestions, isNotEmpty);
    final match = suggestions.firstWhere((m) => m.voucherId == expense.id);
    expect(match.voucherType, 'Expense');

    await matching.apply(match);
    final line =
        await engine.fetch('Bank Statement Line', match.lineId);
    expect(line!.payload['status'], 'Reconciled');
    expect(line.payload['matched_voucher'], expense.id);

    // The remaining (deposit) line can be manually reconciled.
    final rest = await matching.suggest('BA-1');
    expect(rest.where((m) => m.lineId == match.lineId), isEmpty);

    final lines = await engine.list('Bank Statement Line',
        filters: {'bank_account': 'BA-1'}, userRoles: roles);
    final deposit = lines.firstWhere(
        (l) => asNum(l.payload['deposit']) > 0);
    await matching.markReconciled(deposit.id);
    expect(
        (await engine.fetch('Bank Statement Line', deposit.id))!
            .payload['status'],
        'Reconciled');
  });
}
