import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_hub_app/ledger/hub_interceptors.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Covers [LineItemTotalsInterceptor]: line-item amounts and document totals
/// are computed on save so the ledger derives correct GL/stock amounts from
/// UI-entered (or imported) documents.
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
      interceptors: const [LineItemTotalsInterceptor()],
    );

    await registry.register(const DocType(
      id: 'Sales Invoice Item',
      name: 'Sales Invoice Item',
      isChild: true,
      fields: [
        FieldDefinition(key: 'qty', label: 'Qty', type: FieldType.float),
        FieldDefinition(key: 'rate', label: 'Rate', type: FieldType.currency),
        FieldDefinition(key: 'amount', label: 'Amount', type: FieldType.currency, readOnly: true),
      ],
    ));
    await registry.register(const DocType(
      id: 'Sales Invoice',
      name: 'Sales Invoice',
      isSubmittable: true,
      fields: [
        FieldDefinition(key: 'items', label: 'Items', type: FieldType.table, tableDocType: 'Sales Invoice Item'),
        FieldDefinition(key: 'total', label: 'Total', type: FieldType.currency, readOnly: true),
        FieldDefinition(key: 'grand_total', label: 'Grand Total', type: FieldType.currency, readOnly: true),
      ],
    ));
  });

  tearDown(() => database.close());

  ChildRow item(dynamic qty, dynamic rate) => ChildRow(
        id: '',
        parentId: '',
        parentDocType: 'Sales Invoice',
        tableName: 'items',
        rowIndex: 0,
        payload: {'qty': qty, 'rate': rate},
      );

  Future<Document> saveInvoice(List<ChildRow> rows) async {
    final saved = await engine.save(
      Document(id: '', docType: 'Sales Invoice', children: {'items': rows}),
      roles,
    );
    return (await engine.fetch('Sales Invoice', saved.id))!;
  }

  test('computes row amount and sums document totals on save', () async {
    final inv = await saveInvoice([item(2, 50), item(1, 10)]);

    expect(inv.payload['total'], 110);
    expect(inv.payload['grand_total'], 110);
    expect(
      inv.children['items']!.map((r) => r.payload['amount']).toList(),
      [100, 10],
    );
  });

  test('coerces string qty/rate via asNum before multiplying', () async {
    final inv = await saveInvoice([item('3', '5')]);
    expect(inv.payload['grand_total'], 15);
  });

  test('empty items table yields zero totals', () async {
    final inv = await saveInvoice([]);
    expect(inv.payload['total'], 0);
    expect(inv.payload['grand_total'], 0);
  });
}
