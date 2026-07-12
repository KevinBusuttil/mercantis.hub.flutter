import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_hub_app/hospitality/tab_service.dart';
import 'package:mercantis_hub_app/ledger/hub_interceptors.dart';
import 'package:mercantis_hub_app/ledger/ledger_values.dart' hide isTrue;
import 'package:mercantis_hub_app/manifest/hub_manifest.dart';
import 'package:mercantis_hub_app/modules/pos/pos_receipt.dart';
import 'package:mercantis_hub_app/payments/pos_checkout.dart';
import 'package:mercantis_hub_app/pricing/price_resolver.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// V2-1 hospitality: a tab is pre-fiscal working state on a table; the
/// fiscal moment is settlement into a POS Invoice on the till spine.
/// Modifier price deltas fold into line rates (backend invariant intact)
/// and the chosen modifiers ride the receipt.
void main() {
  setUpAll(sqfliteFfiInit);

  late MercantisDatabase db;
  late DocumentEngine engine;
  late TabService tabs;
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
      deviceId: 'till-1',
      userId: 'server-anna',
      interceptors: const [
        PriceResolutionInterceptor(),
        LineItemTotalsInterceptor(),
        TaxCalculationInterceptor(),
      ],
    );
    tabs = TabService(engine);

    await engine.save(
        Document(id: 'T1', docType: 'POS Table', payload: {
          'table_name': 'Table 1', 'area': 'Terrace', 'seats': 4,
        }),
        roles);
    await engine.save(
        Document(id: 'BURGER', docType: 'Item', payload: {
          'item_code': 'BURGER', 'item_name': 'Burger',
          'item_type': 'Service', 'stock_uom': 'Nos',
          'standard_rate': 12,
        }),
        roles);
    await engine.save(
        Document(id: 'COLA', docType: 'Item', payload: {
          'item_code': 'COLA', 'item_name': 'Cola',
          'item_type': 'Service', 'stock_uom': 'Nos',
          'standard_rate': 2.5,
        }),
        roles);
  });

  tearDown(() async => db.close());

  test('one open tab per table; bar tabs are unlimited', () async {
    final tab = await tabs.openTab(table: 'T1', covers: 2, server: 'Anna');
    expect(tab.id, startsWith('TAB-'));
    expect(tab.payload['status'], 'Open');

    await expectLater(
      tabs.openTab(table: 'T1'),
      throwsA(isA<StateError>()
          .having((e) => '$e', 'message', contains(tab.id))),
    );

    // Bar tabs (no table) stack freely.
    await tabs.openTab(server: 'Anna');
    await tabs.openTab(server: 'Bert');

    // Unknown table is a clear error.
    await expectLater(
        tabs.openTab(table: 'T9'), throwsA(isA<StateError>()));
  });

  test('ordering: S8-priced lines, modifiers, and the running total',
      () async {
    final tab = await tabs.openTab(table: 'T1');
    await tabs.addItem(tab.id, item: 'BURGER',
        modifiers: 'well done, +cheese', modifierAmount: 0.5);
    await tabs.addItem(tab.id, item: 'COLA', qty: 2);

    final loaded = await engine.fetch('POS Tab', tab.id);
    final lines = loaded!.children['items']!;
    expect(asNum(lines[0].payload['rate']), 12); // S8 standard rate
    expect(lines[0].payload['modifiers'], contains('cheese'));
    expect(asNum(lines[1].payload['qty']), 2);

    // 1 × (12 + 0.50) + 2 × 2.50 = 17.50
    expect(tabs.tabTotal(loaded), 17.5);
  });

  test('settlement is the fiscal moment: POS Invoice on the till series',
      () async {
    final tab = await tabs.openTab(table: 'T1', covers: 2);
    await tabs.addItem(tab.id, item: 'BURGER',
        modifiers: '+cheese', modifierAmount: 0.5);
    await tabs.addItem(tab.id, item: 'COLA', qty: 2);

    final invoice = await tabs.settleTab(
      tab.id,
      tenders: const [PosTender(type: 'Cash', amount: 20)],
      tillSeries: 'TERRACE',
    );

    expect(invoice.docStatus, 1); // submitted — the fiscal document
    expect(invoice.id, startsWith('POS-.TERRACE.-')); // per-till series
    expect(asNum(invoice.payload['grand_total']), 17.5);
    // The modifier delta folded into the line rate…
    final lines = invoice.children['items']!;
    expect(asNum(lines[0].payload['rate']), 12.5);
    // …and the modifiers ride the description onto the receipt.
    expect(lines[0].payload['description'], contains('+cheese'));

    final billed = await engine.fetch('POS Tab', tab.id);
    expect(billed!.payload['status'], 'Billed');
    expect(billed.payload['pos_invoice'], invoice.id);

    // The table frees for the next sitting.
    await tabs.openTab(table: 'T1');

    // A billed tab takes no more orders and cannot settle twice.
    await expectLater(
        tabs.addItem(tab.id, item: 'COLA'), throwsA(isA<StateError>()));
    await expectLater(
      tabs.settleTab(tab.id,
          tenders: const [PosTender(type: 'Cash', amount: 1)]),
      throwsA(isA<StateError>()),
    );
  });

  test('voids need a reason, keep the record, and never touch billed tabs',
      () async {
    final tab = await tabs.openTab(table: 'T1');
    await expectLater(
        tabs.voidTab(tab.id, reason: '  '), throwsA(isA<StateError>()));

    final voided =
        await tabs.voidTab(tab.id, reason: 'Guests left before ordering');
    expect(voided.payload['status'], 'Void');
    expect(voided.payload['void_reason'], contains('left'));
    // The record remains queryable — the audit trail the 13th Schedule
    // certification cares about.
    expect(await engine.fetch('POS Tab', tab.id), isNotNull);
    // And the table is free again.
    final second = await tabs.openTab(table: 'T1');
    await tabs.addItem(second.id, item: 'COLA');
    final billed = await tabs.settleTab(second.id,
        tenders: const [PosTender(type: 'Cash', amount: 5)]);
    await expectLater(
      tabs.voidTab(second.id, reason: 'oops'),
      throwsA(isA<StateError>()
          .having((e) => '$e', 'message', contains(billed.id))),
    );

    // An empty tab cannot settle.
    final empty = await tabs.openTab(table: 'T1');
    await expectLater(
      tabs.settleTab(empty.id,
          tenders: const [PosTender(type: 'Cash', amount: 1)]),
      throwsA(isA<StateError>()),
    );
  });

  test('the fiscal receipt carries VAT and EXO numbers', () async {
    final tab = await tabs.openTab(table: 'T1');
    await tabs.addItem(tab.id, item: 'BURGER');
    final invoice = await tabs.settleTab(tab.id,
        tenders: const [PosTender(type: 'Cash', amount: 12)]);
    final hydrated = await engine.fetch('POS Invoice', invoice.id);

    final text = PosReceiptBuilder.build(
      invoice: hydrated!,
      businessName: 'Ta\' Kris',
      vatNumber: 'MT12345678',
      exoNumber: 'EXO-9876',
    );
    expect(text, contains('VAT No: MT12345678'));
    expect(text, contains('EXO No: EXO-9876'));
    expect(text, contains('12.00'));
  });
}
