import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_hub_app/ledger/hub_interceptors.dart';
import 'package:mercantis_hub_app/ledger/ledger_values.dart';
import 'package:mercantis_hub_app/manifest/hub_manifest.dart';
import 'package:mercantis_hub_app/onboarding/hub_seeder.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The journal-balance guard: a hand-entered Journal Entry whose debits and
/// credits differ must be rejected at submit, and the read-only
/// `total_debit` / `total_credit` / `difference` fields are stamped on save.
void main() {
  setUpAll(sqfliteFfiInit);

  late MercantisDatabase db;
  late DocumentEngine engine;
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
      interceptors: const [
        BusinessProfileDefaultsInterceptor(),
        FiscalYearGuardInterceptor(),
        JournalBalanceGuardInterceptor(),
      ],
    );
    await HubSeeder(engine, roles: roles).seed(
        businessName: 'Acme', currencyCode: 'EUR', year: DateTime.now().year);
  });

  tearDown(() async => db.close());

  Future<Document> journal(List<(String, num, num)> lines) async {
    final je = Document(id: '', docType: 'Journal Entry', payload: {
      'posting_date':
          DateTime.now().toIso8601String().split('T').first,
    });
    je.children['accounts'] = [
      for (final (i, line) in lines.indexed)
        ChildRow(
          id: '', parentId: '', parentDocType: 'Journal Entry',
          tableName: 'accounts', rowIndex: i,
          payload: {'account': line.$1, 'debit': line.$2, 'credit': line.$3},
        ),
    ];
    return engine.save(je, roles);
  }

  test('save stamps total_debit / total_credit / difference', () async {
    final je = await journal([('Bank', 100, 0), ('Sales', 0, 60)]);
    expect(asNum(je.payload['total_debit']), 100);
    expect(asNum(je.payload['total_credit']), 60);
    expect(asNum(je.payload['difference']), 40);
  });

  test('an unbalanced journal cannot be submitted', () async {
    final je = await journal([('Bank', 100, 0), ('Sales', 0, 60)]);
    await expectLater(
      engine.submit(je, roles),
      throwsA(isA<DocumentEngineError>()),
    );
    // Still a draft — nothing posted.
    final fetched = await engine.fetch('Journal Entry', je.id);
    expect(fetched!.docStatus, 0);
  });

  test('a balanced journal submits', () async {
    final je = await journal([('Bank', 100, 0), ('Sales', 0, 100)]);
    final submitted = await engine.submit(je, roles);
    expect(submitted.docStatus, 1);
  });

  test('sub-cent rounding noise is tolerated', () async {
    final je = await journal([('Bank', 33.333, 0), ('Sales', 0, 33.331)]);
    final submitted = await engine.submit(je, roles);
    expect(submitted.docStatus, 1);
  });
}
