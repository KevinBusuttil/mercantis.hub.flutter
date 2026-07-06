import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_hub_app/ledger/hub_interceptors.dart';
import 'package:mercantis_hub_app/manifest/hub_manifest.dart';
import 'package:mercantis_hub_app/onboarding/hub_seeder.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The duplicate-bill guard: the same supplier + supplier-invoice-number pair
/// cannot be entered twice (double-payment risk), while blanks, other
/// suppliers, cancelled bills and re-saves pass.
void main() {
  setUpAll(sqfliteFfiInit);

  late MercantisDatabase db;
  late DocumentEngine engine;
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
        BusinessProfileDefaultsInterceptor(),
        DuplicateSupplierBillGuardInterceptor(),
      ],
    );
    await HubSeeder(engine, roles: roles).seed(
        businessName: 'Acme', currencyCode: 'EUR', year: DateTime.now().year);
    for (final id in const ['SUPP-1', 'SUPP-2']) {
      await engine.save(
          Document(id: id, docType: 'Supplier', payload: {
            'supplier_name': id,
            'supplier_type': 'Company',
          }),
          roles);
    }
  });

  tearDown(() async => db.close());

  Future<Document> bill(String supplier, String? number) => engine.save(
      Document(id: '', docType: 'Purchase Invoice', payload: {
        'supplier': supplier,
        'posting_date': today,
        if (number != null) 'supplier_invoice_no': number,
      }),
      roles);

  test('the same supplier + number is rejected (case/space-insensitive)',
      () async {
    await bill('SUPP-1', 'INV-100');
    await expectLater(
        bill('SUPP-1', 'INV-100'), throwsA(isA<DocumentEngineError>()));
    await expectLater(
        bill('SUPP-1', '  inv-100 '), throwsA(isA<DocumentEngineError>()));
  });

  test('other suppliers, other numbers and blanks pass', () async {
    await bill('SUPP-1', 'INV-100');
    await bill('SUPP-2', 'INV-100'); // same number, different supplier
    await bill('SUPP-1', 'INV-101'); // different number
    await bill('SUPP-1', null); // no number — never checked
    await bill('SUPP-1', null); // twice
  });

  test('re-saving the same draft passes', () async {
    final doc = await bill('SUPP-1', 'INV-100');
    doc.payload['due_date'] = today;
    await engine.save(doc, roles); // no self-collision
  });

  test('a cancelled bill frees its number', () async {
    final doc = await bill('SUPP-1', 'INV-100');
    await engine.submit(doc, roles);
    await engine.cancel(doc, roles);
    await bill('SUPP-1', 'INV-100'); // allowed again
  });
}
