import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_hub_app/construction/valuation_service.dart';
import 'package:mercantis_hub_app/ledger/hub_interceptors.dart';
import 'package:mercantis_hub_app/ledger/ledger_values.dart' hide isTrue;
import 'package:mercantis_hub_app/manifest/hub_manifest.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// V6 construction: interim valuations are cumulative; each bills the
/// delta less retention (10% per application, capped at 5% of the
/// contract), and the held retention releases as one final invoice at
/// practical completion.
void main() {
  setUpAll(sqfliteFfiInit);

  late MercantisDatabase db;
  late DocumentEngine engine;
  late ValuationService valuations;
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
      deviceId: 'site-office',
      userId: 'qs',
      interceptors: const [
        LineItemTotalsInterceptor(),
        TaxCalculationInterceptor(),
      ],
    );
    valuations = ValuationService(engine);

    await engine.save(
        Document(id: 'EMP-1', docType: 'Customer', payload: {
          'customer_name': 'Gozo Developments', 'customer_type': 'Company',
        }),
        roles);
    await engine.save(
        Document(id: 'WORKS', docType: 'Item', payload: {
          'item_code': 'WORKS', 'item_name': 'Construction Works',
          'item_type': 'Service', 'stock_uom': 'Nos',
        }),
        roles);
  });

  tearDown(() async => db.close());

  Future<Document> activeContract({num value = 100000}) async {
    final contract = await engine.save(
        Document(id: '', docType: 'Construction Contract',
            company: 'CO-2', payload: {
          'contract_name': 'Villa shell works',
          'customer': 'EMP-1',
          'status': 'Active',
          'contract_value': value,
          'retention_percent': 10,
          'retention_cap_percent': 5,
          'billing_item': 'WORKS',
        }),
        roles);
    return contract;
  }

  test('valuations bill the delta less retention, capped at 5% of the '
      'contract', () async {
    final contract = await activeContract();

    // Valuation 1: 45% of 100k = 45,000 gross; retention 10% = 4,500.
    final first = await valuations.bill(contract.id,
        cumulativePercent: 45, date: DateTime(2026, 8, 31));
    expect(first.docStatus, 1);
    expect(asNum(first.payload['grand_total']), 40500);
    // Codex P2 (PR #169): the invoice posts under the CONTRACT's company.
    expect(first.company, 'CO-2');
    expect(first.children['items']!.single.payload['description'],
        contains('45% complete'));

    // Valuation 2: 80% → gross 35,000; retention would be 3,500 but the
    // cap (5,000) leaves only 500 headroom.
    final second =
        await valuations.bill(contract.id, cumulativePercent: 80);
    expect(asNum(second.payload['grand_total']), 34500);

    final loaded =
        await engine.fetch('Construction Contract', contract.id);
    expect(ValuationService.retentionHeld(loaded!), 5000); // at the cap
    expect(ValuationService.certifiedPercent(loaded), 80);
    final rows = loaded.children['valuations']!;
    expect(rows, hasLength(2));
    expect(asNum(rows[0].payload['retention_this_time']), 4500);
    expect(asNum(rows[1].payload['retention_this_time']), 500);
    expect('${rows[1].payload['sales_invoice']}', second.id);

    // Valuation 3: 100% → gross 20,000, retention exhausted → nets in
    // full.
    final third =
        await valuations.bill(contract.id, cumulativePercent: 100);
    expect(asNum(third.payload['grand_total']), 20000);
  });

  test('valuations only go forward, and only on Active contracts',
      () async {
    final contract = await activeContract();
    await valuations.bill(contract.id, cumulativePercent: 60);

    // Going backwards (or sideways) refuses with the position named.
    await expectLater(
      valuations.bill(contract.id, cumulativePercent: 60),
      throwsA(isA<StateError>()
          .having((e) => '$e', 'message', contains('60'))),
    );
    await expectLater(
        valuations.bill(contract.id, cumulativePercent: 150),
        throwsA(isA<StateError>()));

    // Draft contracts don't bill.
    final draft = await engine.save(
        Document(id: '', docType: 'Construction Contract', payload: {
          'contract_name': 'Unsigned job', 'customer': 'EMP-1',
          'status': 'Draft', 'contract_value': 5000,
          'billing_item': 'WORKS',
        }),
        roles);
    await expectLater(
        valuations.bill(draft.id, cumulativePercent: 10),
        throwsA(isA<StateError>()));
  });

  test('retention releases once, after practical completion, and closes '
      'the contract', () async {
    final contract = await activeContract();
    await valuations.bill(contract.id, cumulativePercent: 100);
    // 100% in one go: gross 100k, retention capped at 5,000.

    // Release before practical completion refuses — that's the point
    // of retention.
    await expectLater(valuations.releaseRetention(contract.id),
        throwsA(isA<StateError>()));

    await valuations.markPracticallyComplete(contract.id);
    final release = await valuations.releaseRetention(contract.id);
    expect(release.docStatus, 1);
    expect(release.company, 'CO-2'); // Codex P2 (PR #169)
    expect(asNum(release.payload['grand_total']), 5000);
    expect(release.children['items']!.single.payload['description'],
        contains('Retention release'));

    final closed =
        await engine.fetch('Construction Contract', contract.id);
    expect(closed!.payload['status'], 'Closed');
    expect(closed.payload['release_invoice'], release.id);
    expect(ValuationService.retentionHeld(closed), 0);

    // Total invoiced over the whole life == the contract value.
    num invoiced = 0;
    for (final inv
        in await engine.list('Sales Invoice', userRoles: roles)) {
      invoiced += asNum(inv.payload['grand_total']);
    }
    expect(invoiced, 100000);

    // No second release.
    await expectLater(valuations.releaseRetention(contract.id),
        throwsA(isA<StateError>()));
  });
}
