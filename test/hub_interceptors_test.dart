import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_hub_app/ledger/hub_interceptors.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Integration coverage for the Hub's [DocumentInterceptor]s: business-profile
/// defaults on new drafts, and the fiscal-year posting guard on submit.
void main() {
  setUpAll(sqfliteFfiInit);

  late MercantisDatabase database;
  late DocumentEngine engine;
  const roles = {'System Manager'};

  setUp(() async {
    database = await MercantisDatabase.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    final registry = MetadataRegistry(database.db);
    engine = DocumentEngine(
      database: database.db,
      registry: registry,
      metaComposer: MetaComposer(registry, database.db),
      permissionEngine: const PermissionEngine(),
      workflowEngine: WorkflowEngine(database.db),
      expressionEvaluator: ExpressionEvaluator(),
      namingService: NamingService(),
      syncEngine: SyncEngine(database: database.db, registry: registry),
      emitter: EventEmitter(),
      deviceId: 'test-device',
      userId: 'test-user',
      interceptors: const [
        BusinessProfileDefaultsInterceptor(),
        FiscalYearGuardInterceptor(),
      ],
    );

    await registry.register(const DocType(
      id: 'Company',
      name: 'Company',
      fields: [
        FieldDefinition(key: 'company_name', label: 'Company Name', type: FieldType.data),
        FieldDefinition(key: 'default_currency', label: 'Default Currency', type: FieldType.data),
        FieldDefinition(key: 'default_receivable_account', label: 'Receivable', type: FieldType.data),
        FieldDefinition(key: 'default_income_account', label: 'Income', type: FieldType.data),
      ],
    ));
    await registry.register(const DocType(
      id: 'Fiscal Year',
      name: 'Fiscal Year',
      fields: [
        FieldDefinition(key: 'year', label: 'Year', type: FieldType.data),
        FieldDefinition(key: 'year_start_date', label: 'Start', type: FieldType.date),
        FieldDefinition(key: 'year_end_date', label: 'End', type: FieldType.date),
      ],
    ));
    await registry.register(const DocType(
      id: 'Sales Invoice',
      name: 'Sales Invoice',
      isSubmittable: true,
      fields: [
        FieldDefinition(key: 'customer', label: 'Customer', type: FieldType.data),
        FieldDefinition(key: 'currency', label: 'Currency', type: FieldType.data),
        FieldDefinition(key: 'posting_date', label: 'Posting Date', type: FieldType.date),
        FieldDefinition(key: 'debit_to', label: 'Debit To', type: FieldType.data),
        FieldDefinition(key: 'income_account', label: 'Income', type: FieldType.data),
      ],
    ));
  });

  test('business-profile defaults fill blanks on a new draft', () async {
    final company = await engine.save(
      Document(id: '', docType: 'Company', payload: {
        'company_name': 'Acme',
        'default_currency': 'USD',
        'default_receivable_account': 'Debtors',
        'default_income_account': 'Sales',
      }),
      roles,
    );

    final saved = await engine.save(
      Document(id: '', docType: 'Sales Invoice', payload: {'customer': 'C1'}),
      roles,
    );
    final inv = await engine.fetch('Sales Invoice', saved.id);

    expect(inv!.company, company.id);
    expect(inv.payload['currency'], 'USD');
    expect(inv.payload['debit_to'], 'Debtors');
    expect(inv.payload['income_account'], 'Sales');
    final today = DateTime.now().toIso8601String().split('T').first;
    expect(inv.payload['posting_date'], today);
  });

  test('user-entered values are never overwritten', () async {
    await engine.save(
      Document(id: '', docType: 'Company', payload: {
        'company_name': 'Acme',
        'default_currency': 'USD',
      }),
      roles,
    );
    final saved = await engine.save(
      Document(id: '', docType: 'Sales Invoice', payload: {
        'currency': 'EUR',
        'posting_date': '2026-03-03',
      }),
      roles,
    );
    final inv = await engine.fetch('Sales Invoice', saved.id);
    expect(inv!.payload['currency'], 'EUR');
    expect(inv.payload['posting_date'], '2026-03-03');
  });

  group('fiscal-year guard', () {
    Future<void> seedFiscalYear() => engine.save(
          Document(id: '', docType: 'Fiscal Year', payload: {
            'year': 'FY2026',
            'year_start_date': '2026-01-01',
            'year_end_date': '2026-12-31',
          }),
          roles,
        );

    test('blocks a posting dated outside every fiscal year', () async {
      await seedFiscalYear();
      final draft = await engine.save(
        Document(id: '', docType: 'Sales Invoice', payload: {'posting_date': '2025-06-01'}),
        roles,
      );
      await expectLater(
        engine.submit(draft, roles),
        throwsA(isA<DocumentEngineError>()),
      );
      final reloaded = await engine.fetch('Sales Invoice', draft.id);
      expect(reloaded!.docStatus, 0);
    });

    test('allows a posting inside a fiscal year', () async {
      await seedFiscalYear();
      final draft = await engine.save(
        Document(id: '', docType: 'Sales Invoice', payload: {'posting_date': '2026-06-01'}),
        roles,
      );
      final submitted = await engine.submit(draft, roles);
      expect(submitted.docStatus, 1);
    });

    test('does not block when no fiscal years are defined', () async {
      final draft = await engine.save(
        Document(id: '', docType: 'Sales Invoice', payload: {'posting_date': '2025-06-01'}),
        roles,
      );
      final submitted = await engine.submit(draft, roles);
      expect(submitted.docStatus, 1);
    });
  });
}
