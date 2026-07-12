import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_hub_app/hospitality/hospitality_audit.dart';
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
    expect(TabService.tabTotal(loaded), 17.5);
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

  test(
      'kitchen rounds: each send snapshots only the new lines; bumps and '
      'void cascade', () async {
    final tab = await tabs.openTab(table: 'T1', server: 'Anna');
    await tabs.addItem(tab.id, item: 'BURGER',
        modifiers: 'well done', notes: 'no bun');
    await tabs.addItem(tab.id, item: 'COLA', qty: 2);

    // Round one carries both lines with their kitchen detail.
    final first = await tabs.sendToKitchen(tab.id);
    expect(first.id, startsWith('KOT-'));
    expect(first.payload['status'], 'Open');
    expect(first.payload['table'], 'T1');
    final lines = first.children['items']!;
    expect(lines, hasLength(2));
    expect(lines[0].payload['modifiers'], 'well done');
    expect(lines[0].payload['notes'], 'no bun');

    // Nothing new — the server gets told, the kitchen gets no duplicate.
    await expectLater(
        tabs.sendToKitchen(tab.id), throwsA(isA<StateError>()));

    // A follow-up order is the NEXT ticket, holding only the new line.
    await tabs.addItem(tab.id, item: 'COLA');
    final second = await tabs.sendToKitchen(tab.id);
    expect(second.children['items'], hasLength(1));

    // The kitchen bumps round one; a Done ticket can't bump twice.
    final done = await tabs.bumpTicket(first.id);
    expect(done.payload['status'], 'Done');
    await expectLater(
        tabs.bumpTicket(first.id), throwsA(isA<StateError>()));

    // Voiding the tab voids what's still on the rail — never cooked work.
    await tabs.voidTab(tab.id, reason: 'Guests walked out');
    final t1 = await engine.fetch('Kitchen Ticket', first.id);
    final t2 = await engine.fetch('Kitchen Ticket', second.id);
    expect(t1!.payload['status'], 'Done'); // history stays honest
    expect(t2!.payload['status'], 'Void');
  });

  test('split settlement: chosen lines invoice now, the rest stays open',
      () async {
    final tab = await tabs.openTab(table: 'T1', covers: 3);
    await tabs.addItem(tab.id, item: 'BURGER',
        modifiers: '+cheese', modifierAmount: 0.5); // 12.50
    await tabs.addItem(tab.id, item: 'COLA', qty: 2); // 5.00
    await tabs.addItem(tab.id, item: 'COLA'); // 2.50

    // One guest pays for their burger and leaves.
    final first = await tabs.settleTab(
      tab.id,
      tenders: const [PosTender(type: 'Card', amount: 12.5)],
      rowIndexes: const [0],
    );
    expect(first.docStatus, 1);
    expect(asNum(first.payload['grand_total']), 12.5);

    // The tab is still open with the two cola lines and remembers the
    // split invoice.
    final open = await engine.fetch('POS Tab', tab.id);
    expect(open!.payload['status'], 'Open');
    expect(open.children['items'], hasLength(2));
    expect(open.payload['split_invoices'], contains(first.id));
    expect(TabService.tabTotal(open), 7.5);

    // A stale line index refuses.
    await expectLater(
      tabs.settleTab(tab.id,
          tenders: const [PosTender(type: 'Cash', amount: 1)],
          rowIndexes: const [7]),
      throwsA(isA<StateError>()),
    );

    // Settling the rest bills the tab.
    final rest = await tabs.settleTab(tab.id,
        tenders: const [PosTender(type: 'Cash', amount: 7.5)]);
    expect(asNum(rest.payload['grand_total']), 7.5);
    final billed = await engine.fetch('POS Tab', tab.id);
    expect(billed!.payload['status'], 'Billed');
    expect(billed.payload['pos_invoice'], rest.id);
  });

  test('service charge posts as a priced line and takes VAT', () async {
    await engine.save(
        Document(id: 'SVC', docType: 'Item', payload: {
          'item_code': 'SVC', 'item_name': 'Service Charge',
          'item_type': 'Service', 'stock_uom': 'Nos',
        }),
        roles);

    final tab = await tabs.openTab(table: 'T1');
    await tabs.addItem(tab.id, item: 'BURGER'); // 12.00
    await tabs.addItem(tab.id, item: 'COLA', qty: 2); // 5.00

    // Percent without a configured item is a config error, not silence.
    await expectLater(
      tabs.settleTab(tab.id,
          tenders: const [PosTender(type: 'Cash', amount: 20)],
          serviceChargePercent: 10),
      throwsA(isA<StateError>()),
    );

    final invoice = await tabs.settleTab(
      tab.id,
      tenders: const [PosTender(type: 'Cash', amount: 20)],
      serviceChargePercent: 10,
      serviceChargeItem: 'SVC',
    );
    // 17.00 + 1.70 service charge = 18.70
    expect(asNum(invoice.payload['grand_total']), 18.7);
    final lines = invoice.children['items']!;
    expect(lines, hasLength(3));
    expect(lines.last.payload['item'], 'SVC');
    expect(asNum(lines.last.payload['rate']), 1.7);
    expect(lines.last.payload['description'], contains('10%'));
  });

  test('merge: lines and covers move over, the source stays on record',
      () async {
    await engine.save(
        Document(id: 'T2', docType: 'POS Table', payload: {
          'table_name': 'Table 2', 'area': 'Terrace', 'seats': 2,
        }),
        roles);

    final host = await tabs.openTab(table: 'T1', covers: 2);
    await tabs.addItem(host.id, item: 'BURGER');
    final joiner = await tabs.openTab(table: 'T2', covers: 1);
    await tabs.addItem(joiner.id, item: 'COLA', qty: 2,
        modifiers: 'no ice');
    await tabs.sendToKitchen(joiner.id); // a round already cooking

    await expectLater(
        tabs.mergeTabs(host.id, host.id), throwsA(isA<StateError>()));

    await tabs.mergeTabs(joiner.id, host.id);

    final merged = await engine.fetch('POS Tab', host.id);
    expect(merged!.children['items'], hasLength(2));
    expect(merged.children['items']![1].payload['modifiers'], 'no ice');
    // Moved lines keep their kitchen state — nothing re-fires.
    expect(merged.children['items']![1].payload['sent_to_kitchen'], 1);
    expect(asNum(merged.payload['covers']), 3);
    expect(TabService.tabTotal(merged), 17);

    // The source stays on record, pointing at where its lines went…
    final gone = await engine.fetch('POS Tab', joiner.id);
    expect(gone!.payload['status'], 'Merged');
    expect(gone.payload['merged_into'], host.id);
    // …it can't take orders, and Table 2 frees for the next sitting.
    await expectLater(
        tabs.addItem(gone.id, item: 'COLA'), throwsA(isA<StateError>()));
    await tabs.openTab(table: 'T2');

    // The cooking round now belongs to the host tab and its table.
    final tickets =
        await engine.list('Kitchen Ticket', userRoles: roles);
    expect(tickets, hasLength(1));
    expect(tickets.first.payload['tab'], host.id);
    expect(tickets.first.payload['table'], 'T1');
  });

  test('comps leave the bill but never the record; the audit sees all',
      () async {
    final tab = await tabs.openTab(table: 'T1', server: 'Anna');
    await tabs.addItem(tab.id, item: 'BURGER'); // 12.00
    await tabs.addItem(tab.id, item: 'COLA', qty: 2); // 5.00

    // A comp needs a reason, and only once per line.
    await expectLater(
        tabs.compLine(tab.id, 0, reason: '  '),
        throwsA(isA<StateError>()));
    await tabs.compLine(tab.id, 0, reason: 'Dropped at the pass');
    await expectLater(
        tabs.compLine(tab.id, 0, reason: 'again'),
        throwsA(isA<StateError>()));

    // Off the bill…
    final loaded = await engine.fetch('POS Tab', tab.id);
    expect(TabService.tabTotal(loaded!), 5);
    // …and unsettleable, even by explicit selection.
    await expectLater(
      tabs.settleTab(tab.id,
          tenders: const [PosTender(type: 'Cash', amount: 12)],
          rowIndexes: const [0]),
      throwsA(isA<StateError>()),
    );

    // Default settlement invoices only what's payable — and the billed
    // tab keeps BOTH lines, comp attached, as the record.
    final invoice = await tabs.settleTab(tab.id,
        tenders: const [PosTender(type: 'Cash', amount: 5)]);
    expect(asNum(invoice.payload['grand_total']), 5);
    expect(invoice.children['items'], hasLength(1));
    final billed = await engine.fetch('POS Tab', tab.id);
    expect(billed!.payload['status'], 'Billed');
    expect(billed.children['items'], hasLength(2));
    expect(billed.children['items']![0].payload['comp_reason'],
        contains('pass'));

    // Add a voided tab and a cancelled fiscal invoice to the picture.
    final walked = await tabs.openTab(table: 'T1');
    await tabs.addItem(walked.id, item: 'COLA'); // 2.50
    await tabs.voidTab(walked.id, reason: 'Guests walked out');
    await engine.cancel(
        (await engine.fetch('POS Invoice', invoice.id))!, roles);

    // The audit report: every giveaway with its value and reason.
    final audit = await buildHospitalityAudit(engine);
    expect(audit.comps, hasLength(1));
    expect(audit.comps.first.value, 12);
    expect(audit.comps.first.reason, contains('pass'));
    expect(audit.compValue, 12);
    expect(audit.voids, hasLength(1));
    expect(audit.voids.first.value, 2.5);
    expect(audit.voids.first.reason, contains('walked'));
    expect(audit.cancellations, hasLength(1));
    expect(audit.cancellations.first.value, 5);
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
