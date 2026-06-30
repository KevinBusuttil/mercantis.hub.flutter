import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_hub_app/modules/banking/bank_matching_service.dart';
import 'package:mercantis_hub_app/manifest/hub_manifest.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// H1 — the engine-wired matching service: it loads a bank account's
/// unreconciled lines + its submitted payments, proposes matches, and applies
/// an accepted one.
void main() {
  setUpAll(sqfliteFfiInit);

  late MercantisDatabase db;
  late DocumentEngine engine;
  late BankMatchingService service;
  const roles = {'System Manager'};

  setUp(() async {
    db = await MercantisDatabase.open(
        factory: databaseFactoryFfi, path: inMemoryDatabasePath);
    final registry = MetadataRegistry(db.db);
    final sync = SyncEngine(database: db.db, registry: registry);
    await AppInstaller(database: db.db, registry: registry, syncEngine: sync)
        .install(HubManifest.build());
    engine = DocumentEngine(
      database: db.db,
      registry: registry,
      metaComposer: MetaComposer(registry, db.db),
      permissionEngine: const PermissionEngine(),
      workflowEngine: WorkflowEngine(db.db),
      expressionEvaluator: ExpressionEvaluator(),
      namingService: NamingService(),
      syncEngine: sync,
      emitter: EventEmitter(),
      deviceId: 'devA',
      userId: 'u',
      interceptors: const [],
    );
    service = BankMatchingService(engine: engine, roles: roles);

    // Ledger accounts the links point at (link-existence is validated on save).
    for (final a in const ['Bank', 'Cash']) {
      await engine.save(
          Document(id: a, docType: 'Account', payload: {
            'account_name': a, 'root_type': 'Asset', 'account_type': a,
          }),
          roles);
    }
    await engine.save(
        Document(id: 'BA1', docType: 'Bank Account', payload: {
          'account_name': 'Current', 'gl_account': 'Bank',
        }),
        roles);
  });

  tearDown(() async => db.close());

  Future<void> statementLine(String id,
      {required num deposit, required num withdrawal, required String date,
      String? ref}) async {
    await engine.save(
        Document(id: id, docType: 'Bank Statement Line', payload: {
          'bank_account': 'BA1',
          'posting_date': date,
          'deposit': deposit,
          'withdrawal': withdrawal,
          'amount': deposit - withdrawal,
          if (ref != null) 'reference_number': ref,
          'status': 'Unreconciled',
        }),
        roles);
  }

  Future<Document> payment(String id,
      {required String type, required num amount, required String date,
      String? from, String? to, String? ref}) async {
    final p = Document(id: id, docType: 'Payment Entry', payload: {
      'payment_type': type,
      'posting_date': date,
      'paid_amount': amount,
      if (from != null) 'paid_from': from,
      if (to != null) 'paid_to': to,
      if (ref != null) 'reference_no': ref,
    });
    return engine.submit(await engine.save(p, roles), roles);
  }

  test('suggests matches for inbound and outbound payments by sign', () async {
    await statementLine('L1', deposit: 500, withdrawal: 0, date: '2026-06-10', ref: 'RC1');
    await statementLine('L2', deposit: 0, withdrawal: 200, date: '2026-06-11');
    // A receive into the bank (+500) and a payment out of it (−200).
    await payment('PAY-1', type: 'Receive', amount: 500, date: '2026-06-10', to: 'Bank', ref: 'RC1');
    await payment('PAY-2', type: 'Pay', amount: 200, date: '2026-06-11', from: 'Bank');
    // Noise: a payment that doesn't touch the bank account.
    await payment('PAY-3', type: 'Pay', amount: 500, date: '2026-06-10', from: 'Cash');

    final matches = await service.suggest('BA1');
    final byLine = {for (final m in matches) m.lineId: m.voucherId};
    expect(byLine, {'L1': 'PAY-1', 'L2': 'PAY-2'}); // PAY-3 ignored
  });

  test('apply marks the line Reconciled against its voucher', () async {
    await statementLine('L1', deposit: 500, withdrawal: 0, date: '2026-06-10');
    await payment('PAY-1', type: 'Receive', amount: 500, date: '2026-06-10', to: 'Bank');

    final match = (await service.suggest('BA1')).single;
    await service.apply(match);

    final line = (await engine.fetch('Bank Statement Line', 'L1'))!;
    expect(line.payload['status'], 'Reconciled');
    expect(line.payload['matched_voucher'], 'PAY-1');
    expect(line.payload['matched_voucher_type'], 'Payment Entry');

    // A reconciled line is no longer offered.
    expect(await service.suggest('BA1'), isEmpty);
  });
}
