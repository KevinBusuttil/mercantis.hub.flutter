import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_hub_app/ledger/hub_interceptors.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// End-to-end coverage for [TaxCalculationInterceptor]: VAT is computed on save
/// from real Tax Code masters, the line → item → document → party fallback chain
/// is honoured, and the computed `taxes` child rows + tax-aware totals persist.
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
      interceptors: const [LineItemTotalsInterceptor(), TaxCalculationInterceptor()],
    );

    for (final dt in <DocType>[
      const DocType(id: 'Company', name: 'Company', fields: [
        FieldDefinition(key: 'company_name', label: 'Name', type: FieldType.data),
        FieldDefinition(key: 'default_vat_account', label: 'Default VAT Account', type: FieldType.data),
      ]),
      const DocType(id: 'Tax Code', name: 'Tax Code', fields: [
        FieldDefinition(key: 'tax_code_name', label: 'Name', type: FieldType.data),
        FieldDefinition(key: 'tax_type', label: 'Tax Type', type: FieldType.data),
        FieldDefinition(key: 'rate', label: 'Rate', type: FieldType.float),
        FieldDefinition(key: 'tax_account', label: 'Tax Account', type: FieldType.data),
        FieldDefinition(key: 'enabled', label: 'Enabled', type: FieldType.check),
      ]),
      const DocType(id: 'Tax Charge', name: 'Tax Charge', isChild: true, fields: [
        FieldDefinition(key: 'tax_code', label: 'Tax Code', type: FieldType.data),
        FieldDefinition(key: 'tax_type', label: 'Tax Type', type: FieldType.data),
        FieldDefinition(key: 'description', label: 'Description', type: FieldType.data),
        FieldDefinition(key: 'rate', label: 'Rate', type: FieldType.float),
        FieldDefinition(key: 'tax_account', label: 'Tax Account', type: FieldType.data),
        FieldDefinition(key: 'taxable_amount', label: 'Taxable', type: FieldType.currency),
        FieldDefinition(key: 'tax_amount', label: 'Tax', type: FieldType.currency),
      ]),
      const DocType(id: 'Item', name: 'Item', fields: [
        FieldDefinition(key: 'item_name', label: 'Name', type: FieldType.data),
        FieldDefinition(key: 'tax_code', label: 'Tax Code', type: FieldType.data),
      ]),
      const DocType(id: 'Customer', name: 'Customer', fields: [
        FieldDefinition(key: 'customer_name', label: 'Name', type: FieldType.data),
        FieldDefinition(key: 'tax_code', label: 'Tax Code', type: FieldType.data),
      ]),
      const DocType(id: 'Sales Invoice Item', name: 'Sales Invoice Item', isChild: true, fields: [
        FieldDefinition(key: 'item', label: 'Item', type: FieldType.data),
        FieldDefinition(key: 'qty', label: 'Qty', type: FieldType.float),
        FieldDefinition(key: 'rate', label: 'Rate', type: FieldType.currency),
        FieldDefinition(key: 'amount', label: 'Amount', type: FieldType.currency, readOnly: true),
        FieldDefinition(key: 'tax_code', label: 'Tax Code', type: FieldType.data),
      ]),
      const DocType(id: 'Sales Invoice', name: 'Sales Invoice', isSubmittable: true, fields: [
        FieldDefinition(key: 'customer', label: 'Customer', type: FieldType.data),
        FieldDefinition(key: 'tax_code', label: 'Tax Code', type: FieldType.data),
        FieldDefinition(key: 'items', label: 'Items', type: FieldType.table, tableDocType: 'Sales Invoice Item'),
        FieldDefinition(key: 'total', label: 'Total', type: FieldType.currency, readOnly: true),
        FieldDefinition(key: 'taxes', label: 'Taxes', type: FieldType.table, tableDocType: 'Tax Charge'),
        FieldDefinition(key: 'tax_total', label: 'Tax Total', type: FieldType.currency, readOnly: true),
        FieldDefinition(key: 'grand_total', label: 'Grand Total', type: FieldType.currency, readOnly: true),
      ]),
    ]) {
      await registry.register(dt);
    }
  });

  tearDown(() => database.close());

  Future<String> taxCode({num rate = 18, String? account = 'VAT Output'}) async {
    final saved = await engine.save(
      Document(id: '', docType: 'Tax Code', payload: {
        'tax_code_name': 'VAT $rate',
        'tax_type': 'VAT',
        'rate': rate,
        if (account != null) 'tax_account': account,
        'enabled': true,
      }),
      roles,
    );
    return saved.id;
  }

  ChildRow line(num qty, num rate, {String? taxCode, String? item}) => ChildRow(
        id: '',
        parentId: '',
        parentDocType: 'Sales Invoice',
        tableName: 'items',
        rowIndex: 0,
        payload: {'qty': qty, 'rate': rate, if (taxCode != null) 'tax_code': taxCode, if (item != null) 'item': item},
      );

  Future<Document> saveInvoice(Map<String, dynamic> payload, List<ChildRow> rows) async {
    final saved = await engine.save(
      Document(id: '', docType: 'Sales Invoice', company: payload.remove('company') as String?, payload: payload, children: {'items': rows}),
      roles,
    );
    return (await engine.fetch('Sales Invoice', saved.id))!;
  }

  test('line-level tax code computes VAT and tax-aware totals', () async {
    final code = await taxCode(rate: 18, account: 'VAT Output');
    final inv = await saveInvoice({}, [line(2, 500, taxCode: code)]);

    expect(inv.payload['total'], 1000); // net
    expect(inv.payload['tax_total'], 180);
    expect(inv.payload['grand_total'], 1180);

    final taxes = inv.children['taxes']!;
    expect(taxes.length, 1);
    expect(taxes.single.payload['tax_amount'], 180);
    expect(taxes.single.payload['taxable_amount'], 1000);
    expect(taxes.single.payload['tax_account'], 'VAT Output');
    expect(taxes.single.payload['tax_code'], code);
  });

  test('falls back to the customer default tax code', () async {
    final code = await taxCode(rate: 7);
    final cust = await engine.save(
      Document(id: '', docType: 'Customer', payload: {'customer_name': 'Acme', 'tax_code': code}),
      roles,
    );
    // No line / item / document tax code → resolves via the customer.
    final inv = await saveInvoice({'customer': cust.id}, [line(1, 200)]);

    expect(inv.payload['tax_total'], 14); // 200 * 7%
    expect(inv.children['taxes']!.single.payload['tax_code'], code);
  });

  test('blank tax account falls back to the Company default VAT account', () async {
    final company = await engine.save(
      Document(id: '', docType: 'Company', payload: {'company_name': 'Co', 'default_vat_account': 'VAT Control'}),
      roles,
    );
    final code = await taxCode(rate: 18, account: null); // no account on the code
    final inv = await saveInvoice({'company': company.id}, [line(1, 1000, taxCode: code)]);

    expect(inv.children['taxes']!.single.payload['tax_account'], 'VAT Control');
    expect(inv.payload['grand_total'], 1180);
  });

  test('no tax code → net-only, grand_total equals total', () async {
    final inv = await saveInvoice({}, [line(2, 50)]);
    expect(inv.payload['total'], 100);
    expect(inv.payload['tax_total'], 0);
    expect(inv.payload['grand_total'], 100);
    expect(inv.children['taxes'] ?? const [], isEmpty);
  });
}
