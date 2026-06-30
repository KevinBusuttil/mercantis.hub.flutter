import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_hub_app/modules/accounting/tax_return_builder.dart';
import 'package:mercantis_hub_app/manifest/hub_manifest.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// H2 — the VAT/tax return builder: pure aggregation + the engine-wired fill.
void main() {
  group('TaxReturnBuilder (pure)', () {
    test('splits output vs input tax and computes the net + bases', () {
      final r = TaxReturnBuilder.build(const [
        TaxReturnRow(partyType: 'Customer', baseAmount: 1000, taxAmount: 180),
        TaxReturnRow(partyType: 'Supplier', baseAmount: 600, taxAmount: 108),
      ]);
      expect(r.outputTax, 180);
      expect(r.inputTax, 108);
      expect(r.netTax, 72);
      expect(r.taxableSales, 1000);
      expect(r.taxablePurchases, 600);
      expect(r.boxes.map((b) => b.number), ['1', '2', '3', '4', '5']);
      expect(r.boxes[2].amount, 72); // net tax due
      expect(r.boxes[2].isTax, isTrue);
      expect(r.boxes[3].isTax, isFalse); // taxable sales is a base figure
    });

    test('reversal rows (negated) net cancellations out', () {
      final r = TaxReturnBuilder.build(const [
        TaxReturnRow(partyType: 'Customer', baseAmount: 1000, taxAmount: 180),
        TaxReturnRow(partyType: 'Customer', baseAmount: -200, taxAmount: -36),
      ]);
      expect(r.outputTax, 144);
      expect(r.taxableSales, 800);
    });

    test('rows without a party side are ignored', () {
      final r = TaxReturnBuilder.build(const [
        TaxReturnRow(partyType: null, baseAmount: 999, taxAmount: 99),
      ]);
      expect(r.outputTax, 0);
      expect(r.inputTax, 0);
    });
  });

  group('TaxReturnService (engine)', () {
    setUpAll(sqfliteFfiInit);
    late MercantisDatabase db;
    late DocumentEngine engine;
    late TaxReturnService service;
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
      service = TaxReturnService(engine: engine, roles: roles);
    });

    tearDown(() async => db.close());

    Future<void> tt(String id,
        {required String type, String? party, required num base,
        required num tax, required String date, String? company}) async {
      await engine.save(
          Document(id: id, docType: 'Tax Transaction', company: company, payload: {
            'tax_type': type,
            if (party != null) 'party_type': party,
            'base_amount': base,
            'tax_amount': tax,
            'posting_date': date,
            'voucher_type': 'Sales Invoice',
            'voucher_no': 'X',
          }),
          roles);
    }

    test('prepare fills the filing from in-period rows of its tax type', () async {
      final filing = await engine.save(
          Document(id: '', docType: 'Tax Filing', payload: {
            'tax_type': 'VAT',
            'from_date': '2026-04-01',
            'to_date': '2026-06-30',
          }),
          roles);

      await tt('TT1', type: 'VAT', party: 'Customer', base: 1000, tax: 180, date: '2026-04-15');
      await tt('TT2', type: 'VAT', party: 'Supplier', base: 600, tax: 108, date: '2026-05-10');
      await tt('TT3', type: 'VAT', party: 'Customer', base: 2000, tax: 360, date: '2026-03-31'); // before period
      await tt('TT4', type: 'SalesTax', party: 'Customer', base: 500, tax: 50, date: '2026-04-20'); // other type
      await tt('TT5', type: 'VAT', party: 'Customer', base: -100, tax: -18, date: '2026-04-25'); // reversal

      final filled = await service.prepare(filing.id);

      expect(asNum(filled.payload['output_tax']), 162); // 180 − 18
      expect(asNum(filled.payload['input_tax']), 108);
      expect(asNum(filled.payload['net_tax']), 54); // 162 − 108
      expect(asNum(filled.payload['taxable_sales']), 900); // 1000 − 100
      expect(asNum(filled.payload['taxable_purchases']), 600);
      expect(filled.children['boxes'], hasLength(5));
      final net = filled.children['boxes']!
          .firstWhere((b) => b.payload['box_number'] == '3');
      expect(asNum(net.payload['amount']), 54);
    });

    test('only the filing company\'s rows count (multi-company books)', () async {
      final filing = await engine.save(
          Document(id: '', docType: 'Tax Filing', company: 'ACME', payload: {
            'tax_type': 'VAT',
            'from_date': '2026-04-01',
            'to_date': '2026-06-30',
          }),
          roles);

      await tt('A1', type: 'VAT', party: 'Customer', base: 1000, tax: 180, date: '2026-04-15', company: 'ACME');
      await tt('B1', type: 'VAT', party: 'Customer', base: 5000, tax: 900, date: '2026-04-15', company: 'OTHER');

      final filled = await service.prepare(filing.id);
      expect(asNum(filled.payload['output_tax']), 180); // ACME only, not 1080
      expect(asNum(filled.payload['taxable_sales']), 1000);
    });
  });
}

num asNum(dynamic v) => v is num ? v : num.tryParse('$v') ?? 0;
