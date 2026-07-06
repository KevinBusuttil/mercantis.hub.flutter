import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_hub_app/ledger/hub_interceptors.dart';
import 'package:mercantis_hub_app/ledger/hub_tax_engine.dart';
import 'package:mercantis_hub_app/ledger/ledger_values.dart';
import 'package:mercantis_hub_app/manifest/hub_manifest.dart';
import 'package:mercantis_hub_app/onboarding/hub_seeder.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Tax-inclusive (retail) pricing: entered amounts contain the VAT, the
/// engine extracts it, and the grand total equals what the customer sees.
void main() {
  group('HubTaxEngine inclusive mode (pure)', () {
    const rates = {
      'VAT18': TaxRateInfo(
          codeId: 'VAT18', description: '18%', rate: 18, account: 'VAT'),
      'VAT5': TaxRateInfo(
          codeId: 'VAT5', description: '5%', rate: 5, account: 'VAT'),
    };

    test('extracts the contained tax; grand total equals entered amounts', () {
      final comp = HubTaxEngine.compute(
        const [TaxLine(118, 'VAT18')],
        rates,
        inclusive: true,
      );
      expect(comp.grandTotal, 118);
      expect(comp.totalTax, 18);
      expect(comp.netTotal, 100);
      expect(comp.taxRows.single.taxableAmount, 100);
    });

    test('mixed rates and an untaxed line', () {
      final comp = HubTaxEngine.compute(
        const [
          TaxLine(118, 'VAT18'),
          TaxLine(105, 'VAT5'),
          TaxLine(50, null), // no code — passes through untouched
        ],
        rates,
        inclusive: true,
      );
      expect(comp.grandTotal, 118 + 105 + 50);
      expect(comp.totalTax, 18 + 5);
      expect(comp.netTotal, 100 + 100 + 50);
    });

    test('exclusive mode is unchanged', () {
      final comp = HubTaxEngine.compute(const [TaxLine(100, 'VAT18')], rates);
      expect(comp.netTotal, 100);
      expect(comp.totalTax, 18);
      expect(comp.grandTotal, 118);
    });
  });

  group('inclusive Sales Invoice through the interceptor (engine)', () {
    setUpAll(sqfliteFfiInit);

    test('gross line of 118 @18%: net 100, tax 18, grand 118', () async {
      final db = await MercantisDatabase.open(
          factory: databaseFactoryFfi, path: inMemoryDatabasePath);
      addTearDown(db.close);
      const roles = {'System Manager'};
      final today = DateTime.now().toIso8601String().split('T').first;
      final registry = MetadataRegistry(db.db);
      final sync = SyncEngine(database: db.db, registry: registry);
      await AppInstaller(database: db.db, registry: registry, syncEngine: sync)
          .install(HubManifest.build());
      final engine = DocumentEngine(
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
          LineItemTotalsInterceptor(),
          TaxCalculationInterceptor(),
        ],
      );
      await HubSeeder(engine, roles: roles).seed(
          businessName: 'Acme',
          currencyCode: 'EUR',
          year: DateTime.now().year);
      await engine.save(
          Document(id: 'CUST-1', docType: 'Customer', payload: {
            'customer_name': 'Walk-in',
            'customer_type': 'Individual',
          }),
          roles);
      await engine.save(
          Document(id: 'X', docType: 'Item', payload: {
            'item_code': 'X',
            'item_name': 'Widget',
            'item_type': 'Service',
            'stock_uom': 'Nos',
          }),
          roles);
      await engine.save(
          Document(id: 'VAT18', docType: 'Tax Code', payload: {
            'tax_code_name': 'VAT 18%',
            'tax_type': 'VAT',
            'rate': 18,
            'tax_account': 'VAT',
            'enabled': 1,
          }),
          roles);

      final si = Document(id: '', docType: 'Sales Invoice', payload: {
        'customer': 'CUST-1',
        'posting_date': today,
        'tax_code': 'VAT18',
        'prices_include_tax': 1,
      });
      si.children['items'] = [
        ChildRow(
          id: '', parentId: '', parentDocType: 'Sales Invoice',
          tableName: 'items', rowIndex: 0,
          payload: {'item': 'X', 'qty': 1, 'rate': 118}, // shelf price
        ),
      ];
      final saved = await engine.save(si, roles);

      expect(asNum(saved.payload['grand_total']), 118);
      expect(asNum(saved.payload['tax_total']), 18);
      expect(asNum(saved.payload['total']), 100);
      final taxRow = saved.children['taxes']!.single;
      expect(asNum(taxRow.payload['taxable_amount']), 100);
      expect(asNum(taxRow.payload['tax_amount']), 18);

      // The same document without the flag adds tax on top instead.
      final exclusive = Document(id: '', docType: 'Sales Invoice', payload: {
        'customer': 'CUST-1',
        'posting_date': today,
        'tax_code': 'VAT18',
      });
      exclusive.children['items'] = [
        ChildRow(
          id: '', parentId: '', parentDocType: 'Sales Invoice',
          tableName: 'items', rowIndex: 0,
          payload: {'item': 'X', 'qty': 1, 'rate': 118},
        ),
      ];
      final savedEx = await engine.save(exclusive, roles);
      expect(asNum(savedEx.payload['grand_total']), 139.24); // 118 + 18%
    });
  });
}
