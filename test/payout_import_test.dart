import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_hub_app/ledger/hub_interceptors.dart';
import 'package:mercantis_hub_app/ledger/ledger_values.dart' hide isTrue;
import 'package:mercantis_hub_app/manifest/hub_manifest.dart';
import 'package:mercantis_hub_app/modules/banking/payout_import.dart';
import 'package:mercantis_hub_app/onboarding/hub_seeder.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Payment-provider payout reconciliation (Phase 5, via the Phase-4 clearing
/// machinery): a Stripe-style balance CSV becomes one balanced Journal Entry
/// — Dr Bank (net), Dr Payment Fees, Cr Payment Clearing (gross).
void main() {
  group('PayoutReportCsvParser', () {
    test('parses charges, skips the payout row, handles refunds', () {
      final report = PayoutReportCsvParser.parse('''
id,Type,Amount,Fee,Net,Created (UTC),Description
ch_1,charge,100.00,3.20,96.80,2026-07-01,Order 741
ch_2,charge,"59.90","2.04","57.86",2026-07-02,Order 742
re_1,refund,-20.00,-0.50,-19.50,2026-07-03,Refund 741
po_1,payout,-135.16,0.00,-135.16,2026-07-04,STRIPE PAYOUT
''');
      expect(report.rows.length, 3);
      expect(report.skipped, 1); // the payout row
      expect(report.gross, 139.9); // 100 + 59.90 − 20
      expect(report.fee, closeTo(4.74, 0.001)); // 3.20 + 2.04 − 0.50
      expect(report.net, closeTo(135.16, 0.001));
      expect(report.rows.first.reference, 'ch_1');
    });

    test('unrecognisable text yields an empty report', () {
      final report = PayoutReportCsvParser.parse('hello\nworld');
      expect(report.rows, isEmpty);
    });
  });

  group('PayoutImportService (engine)', () {
    setUpAll(sqfliteFfiInit);
    late MercantisDatabase db;
    late DocumentEngine engine;
    late PayoutImportService service;
    const roles = {'System Manager'};
    final today = DateTime.now().toIso8601String().split('T').first;

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
        interceptors: const [
          FiscalYearGuardInterceptor(),
          GroupAccountPostingGuardInterceptor(),
          JournalBalanceGuardInterceptor(),
        ],
      );
      await HubSeeder(engine, roles: roles).seed(
          businessName: 'Acme',
          currencyCode: 'EUR',
          year: DateTime.now().year);
      service = PayoutImportService(engine: engine);
    });

    tearDown(() async => db.close());

    test('books Dr Bank net + Dr fees / Cr clearing gross, balanced',
        () async {
      final je = await service.importPayoutCsv(
        csv: '''
id,Type,Amount,Fee,Net
ch_1,charge,100.00,3.20,96.80
ch_2,charge,59.90,2.04,57.86
''',
        postingDate: today,
        bankGlAccount: 'Bank',
        provider: 'Stripe',
      );
      expect(je.docStatus, 0); // draft — reviewed before posting

      // The balance guard stamped the totals; the entry balances.
      expect(asNum(je.payload['total_debit']), 159.9);
      expect(asNum(je.payload['total_credit']), 159.9);
      expect(asNum(je.payload['difference']), 0);

      final hydrated = await engine.fetch('Journal Entry', je.id);
      final byAccount = {
        for (final row in hydrated!.children['accounts']!)
          row.payload['account']: row.payload,
      };
      expect(asNum(byAccount['Bank']!['debit']), 154.66); // net
      expect(asNum(byAccount[PayoutImportService.feesAccountId]!['debit']),
          5.24);
      expect(
          asNum(byAccount[PayoutImportService.clearingAccountId]!['credit']),
          159.9);

      // The clearing and fee accounts were created on demand.
      final clearing =
          await engine.fetch('Account', PayoutImportService.clearingAccountId);
      expect(clearing!.payload['root_type'], 'Asset');
      final fees =
          await engine.fetch('Account', PayoutImportService.feesAccountId);
      expect(fees!.payload['root_type'], 'Expense');

      // A submitted payout journal passes the balance guard.
      final posted = await engine.submit(hydrated, roles);
      expect(posted.docStatus, 1);
    });

    test('a CSV without charge rows refuses to book anything', () {
      expect(
        () => service.importPayoutCsv(
          csv: 'id,Type,Amount,Fee\npo_1,payout,-10,0',
          postingDate: today,
          bankGlAccount: 'Bank',
        ),
        throwsStateError,
      );
    });
  });
}
