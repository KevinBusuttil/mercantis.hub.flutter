import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_hub_app/manifest/hub_manifest.dart';
import 'package:mercantis_hub_app/modules/pos/pos_parking.dart';
import 'package:mercantis_hub_app/modules/pos/pos_receipt.dart';
import 'package:mercantis_hub_app/modules/pos/pos_till_logic.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// POS polish (Phase 6): barcode/code item resolution, parked (suspended)
/// sales that survive restarts and resume exactly once, and the 80mm text
/// receipt.
void main() {
  group('resolvePosItem', () {
    Document item(String id, {String? barcode, String? code}) =>
        Document(id: id, docType: 'Item', payload: {
          'item_code': code ?? id,
          if (barcode != null) 'barcode': barcode,
        });

    final items = [
      item('ITEM-A', barcode: '5099206079992', code: 'WID-1'),
      item('ITEM-B', code: 'GAD-2'),
    ];

    test('barcode wins, then item code, then id — case-insensitive', () {
      expect(resolvePosItem(items, '5099206079992')!.id, 'ITEM-A');
      expect(resolvePosItem(items, 'wid-1')!.id, 'ITEM-A');
      expect(resolvePosItem(items, 'GAD-2')!.id, 'ITEM-B');
      expect(resolvePosItem(items, ' item-b ')!.id, 'ITEM-B');
      expect(resolvePosItem(items, 'nope'), isNull);
      expect(resolvePosItem(items, '  '), isNull);
    });
  });

  group('PosReceiptBuilder', () {
    test('42 columns: header, lines, VAT, tenders, change', () {
      final invoice = Document(id: 'POS-2026-0007', docType: 'POS Invoice',
          docStatus: 1, payload: {
        'posting_date': '2026-07-06',
        'total': 20.00,
        'tax_total': 3.60,
        'grand_total': 23.60,
        'change_amount': 1.40,
      });
      ChildRow row(String table, int i, Map<String, dynamic> payload) =>
          ChildRow(
            id: '', parentId: 'POS-2026-0007', parentDocType: 'POS Invoice',
            tableName: table, rowIndex: i, payload: payload,
          );
      invoice.children['items'] = [
        row('items', 0, {
          'item': 'ITEM-A',
          'description': 'Widget with a very long descriptive name indeed',
          'qty': 2, 'rate': 10.0, 'amount': 20.0,
        }),
      ];
      invoice.children['taxes'] = [
        row('taxes', 0,
            {'description': 'VAT 18%', 'tax_amount': 3.60}),
      ];
      invoice.children['tenders'] = [
        row('tenders', 0, {'tender_type': 'Cash', 'amount': 25.00}),
      ];

      final text = PosReceiptBuilder.build(
        invoice: invoice,
        businessName: 'Acme Stores',
        vatNumber: 'MT12345678',
      );
      final lines = text.trimRight().split('\n');
      // Nothing exceeds the 80mm printable width.
      expect(lines.every((l) => l.length <= 42), isTrue,
          reason: lines.firstWhere((l) => l.length > 42, orElse: () => ''));
      expect(text, contains('Acme Stores'));
      expect(text, contains('VAT No: MT12345678'));
      expect(text, contains('POS-2026-0007'));
      expect(text, contains('2 x 10.00'));
      expect(text, contains('VAT 18%'));
      expect(lines.any((l) => l.startsWith('TOTAL') && l.endsWith('23.60')),
          isTrue);
      expect(lines.any((l) => l.startsWith('Cash') && l.endsWith('25.00')),
          isTrue);
      expect(lines.any((l) => l.startsWith('Change') && l.endsWith('1.40')),
          isTrue);
      expect(text, contains('Thank you!'));
    });

    test('whole quantities print without .0; no change line when exact', () {
      final invoice = Document(id: 'POS-1', docType: 'POS Invoice', payload: {
        'total': 5, 'grand_total': 5, 'change_amount': 0,
      });
      invoice.children['items'] = [
        ChildRow(
          id: '', parentId: 'POS-1', parentDocType: 'POS Invoice',
          tableName: 'items', rowIndex: 0,
          payload: {'item': 'A', 'qty': 1.5, 'rate': 2, 'amount': 3},
        ),
      ];
      final text =
          PosReceiptBuilder.build(invoice: invoice, businessName: 'Shop');
      expect(text, contains('1.5 x 2.00'));
      expect(text, isNot(contains('Change')));
    });
  });

  group('PosParkingService (engine)', () {
    setUpAll(sqfliteFfiInit);
    late MercantisDatabase db;
    late DocumentEngine engine;
    late PosParkingService service;
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
      service = PosParkingService(engine: engine);
      await engine.save(
          Document(id: 'ITEM-A', docType: 'Item', payload: {
            'item_code': 'ITEM-A',
            'item_name': 'Item A',
            'item_type': 'Stock',
            'stock_uom': 'Nos',
          }),
          roles);
    });

    tearDown(() async => db.close());

    test('park → list → resume restores the cart and deletes the slip',
        () async {
      final parked = await service.park(
        lines: const [
          ParkedLine(item: 'ITEM-A', name: 'Item A', qty: 2, rate: 10),
        ],
        customer: null,
        note: 'Customer fetching wallet',
      );
      expect(parked.id, startsWith('PARK-'));

      final listed = await service.listParked();
      expect(listed.map((d) => d.id), [parked.id]);

      final sale = await service.resume(parked.id);
      expect(sale!.lines.single.item, 'ITEM-A');
      expect(sale.lines.single.qty, 2);
      expect(sale.lines.single.rate, 10);
      expect(sale.note, 'Customer fetching wallet');

      // One-shot: the slip is gone; resuming again returns null.
      expect(await service.listParked(), isEmpty);
      expect(await service.resume(parked.id), isNull);
    });

    test('an empty cart cannot be parked', () {
      expect(() => service.park(lines: const []), throwsStateError);
    });
  });
}
