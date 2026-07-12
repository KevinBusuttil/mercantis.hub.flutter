import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_hub_app/assets/asset_service.dart';
import 'package:mercantis_hub_app/ledger/hub_interceptors.dart';
import 'package:mercantis_hub_app/ledger/ledger_derivation_service.dart';
import 'package:mercantis_hub_app/ledger/ledger_values.dart' hide isTrue;
import 'package:mercantis_hub_app/manifest/hub_manifest.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// S10 fixed assets: the Asset is a register; the money is Journal
/// Entries. Straight-line schedules sum exactly to gross − salvage, due
/// periods post Dr expense / Cr accumulated (idempotently), and disposal
/// clears the books with the balance going to gain/loss.
void main() {
  setUpAll(sqfliteFfiInit);

  late MercantisDatabase db;
  late DocumentEngine engine;
  late LedgerDerivationService ledger;
  late AssetService assets;
  const roles = {'System Manager'};

  Future<void> until(Future<bool> Function() ready) async {
    for (var i = 0; i < 100; i++) {
      if (await ready()) return;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    fail('condition never became true');
  }

  Future<num> glBalance(String account) async {
    num balance = 0;
    for (final gl in await engine.list('GL Entry', userRoles: roles)) {
      if (gl.payload['account'] != account) continue;
      balance += asNum(gl.payload['debit']) - asNum(gl.payload['credit']);
    }
    return balance;
  }

  setUp(() async {
    db = await MercantisDatabase.open(
        factory: databaseFactoryFfi, path: inMemoryDatabasePath);
    final registry = MetadataRegistry(db.db);
    final sync = SyncEngine(database: db.db, registry: registry);
    await AppInstaller(database: db.db, registry: registry, syncEngine: sync)
        .install(HubManifest.build());
    final emitter = EventEmitter();
    engine = DocumentEngine(
      database: db.db,
      registry: registry,
      metaComposer: MetaComposer(registry, db.db),
      permissionEngine: const PermissionEngine(),
      workflowEngine: WorkflowEngine(db.db),
      expressionEvaluator: ExpressionEvaluator(),
      namingService: NamingService(),
      syncEngine: sync,
      emitter: emitter,
      deviceId: 'devA',
      userId: 'u',
      interceptors: const [JournalBalanceGuardInterceptor()],
    );
    ledger = LedgerDerivationService(engine: engine, emitter: emitter)
      ..start();
    assets = AssetService(engine);

    for (final entry in {
      'Vehicles': 'Asset',
      'Accum Depr': 'Asset', // contra-asset
      'Depr Expense': 'Expense',
      'Bank': 'Asset',
      'Disposal Gain Loss': 'Income',
    }.entries) {
      await engine.save(
          Document(id: entry.key, docType: 'Account', payload: {
            'account_name': entry.key,
            'root_type': entry.value,
          }),
          roles);
    }
    await engine.save(
        Document(id: 'VANS', docType: 'Asset Category', payload: {
          'category_name': 'Vans',
          'asset_account': 'Vehicles',
          'accumulated_depreciation_account': 'Accum Depr',
          'depreciation_expense_account': 'Depr Expense',
          'useful_life_months': 12,
        }),
        roles);
  });

  tearDown(() async {
    ledger.dispose();
    await db.close();
  });

  Future<Document> van({num gross = 1200, num salvage = 0}) async =>
      engine.save(
          Document(id: '', docType: 'Asset', payload: {
            'asset_name': 'Delivery van',
            'category': 'VANS',
            'status': 'Draft',
            'purchase_date': '2026-01-15',
            'gross_purchase_amount': gross,
            'salvage_value': salvage,
          }),
          roles);

  test('the schedule sums exactly to gross − salvage', () {
    final rows = AssetService.buildSchedule(
      start: DateTime(2026, 1, 31),
      gross: 1000,
      salvage: 100,
      months: 7,
    );
    expect(rows, hasLength(7));
    // 900/7 = 128.57…; the last row absorbs the rounding.
    expect(rows.first['amount'], 128.57);
    expect(rows.last['amount'], 128.58);
    num total = 0;
    for (final r in rows) {
      total += r['amount'] as num;
    }
    expect(round2(total), 900);
    // End-of-month clamp: a Jan 31 start hits Feb 28, not Mar 3.
    expect(rows.first['period_date'], '2026-02-28');
    expect(rows[1]['period_date'], '2026-03-31');
  });

  test('capitalise builds the schedule from category defaults', () async {
    final asset = await assets.capitalise((await van()).id);
    expect(asset.payload['status'], 'In Use');
    expect(asset.payload['asset_account'], 'Vehicles'); // pinned
    expect(asset.children['schedule'], hasLength(12));
    expect(AssetService.netBookValue(asset), 1200); // nothing posted yet

    // Only Drafts capitalise.
    await expectLater(
        assets.capitalise(asset.id), throwsA(isA<StateError>()));
    // No accounts anywhere → a loud config error.
    final bare = await engine.save(
        Document(id: '', docType: 'Asset', payload: {
          'asset_name': 'Mystery box',
          'status': 'Draft',
          'purchase_date': '2026-01-01',
          'gross_purchase_amount': 100,
          'useful_life_months': 10,
        }),
        roles);
    await expectLater(
        assets.capitalise(bare.id), throwsA(isA<StateError>()));
  });

  test('due periods post as JEs once — a re-run posts nothing', () async {
    final asset = await assets.capitalise((await van()).id);

    // Three periods are due by 2026-04-20 (Feb 15, Mar 15, Apr 15).
    final posted =
        await assets.postDueDepreciation(asOf: DateTime(2026, 4, 20));
    expect(posted, 3);
    await until(() async => (await glBalance('Accum Depr')) == -300);
    expect(await glBalance('Depr Expense'), 300);

    // Idempotent: nothing new before the next period.
    expect(
        await assets.postDueDepreciation(asOf: DateTime(2026, 4, 20)), 0);

    // The rows carry their JEs; NBV reflects the posted three.
    final loaded = await engine.fetch('Asset', asset.id);
    final rows = loaded!.children['schedule']!;
    expect('${rows[0].payload['journal_entry']}', startsWith('JV-'));
    expect(AssetService.netBookValue(loaded), 900);

    // The next month brings exactly one more.
    expect(
        await assets.postDueDepreciation(asOf: DateTime(2026, 5, 20)), 1);
  });

  test('disposal clears the books and sends the balance to gain/loss',
      () async {
    final asset = await assets.capitalise((await van()).id);
    await assets.postDueDepreciation(asOf: DateTime(2026, 4, 20)); // 300
    await until(() async => (await glBalance('Accum Depr')) == -300);

    // NBV 900, sold for 500 → 400 loss.
    final je = await assets.dispose(
      asset.id,
      proceeds: 500,
      proceedsAccount: 'Bank',
      gainLossAccount: 'Disposal Gain Loss',
      date: DateTime(2026, 4, 30),
    );
    expect(je.docStatus, 1);
    final legs = je.children['accounts']!;
    num debit(String account) => legs
        .where((l) => l.payload['account'] == account)
        .fold<num>(0, (s, l) => s + asNum(l.payload['debit']));
    num credit(String account) => legs
        .where((l) => l.payload['account'] == account)
        .fold<num>(0, (s, l) => s + asNum(l.payload['credit']));
    expect(credit('Vehicles'), 1200); // gross off the books
    expect(debit('Accum Depr'), 300); // accumulated cleared
    expect(debit('Bank'), 500); // proceeds in
    expect(debit('Disposal Gain Loss'), 400); // the loss

    final gone = await engine.fetch('Asset', asset.id);
    expect(gone!.payload['status'], 'Disposed');
    expect(gone.payload['disposal_journal'], je.id);

    // Disposed assets never depreciate again.
    expect(
        await assets.postDueDepreciation(asOf: DateTime(2027, 1, 1)), 0);
    // And can't dispose twice.
    await expectLater(
      assets.dispose(asset.id, gainLossAccount: 'Disposal Gain Loss'),
      throwsA(isA<StateError>()),
    );
  });

  test('proceeds above book value book a gain', () async {
    final asset = await assets.capitalise((await van()).id);
    // No depreciation posted: NBV 1200, sold 1500 → 300 gain.
    final je = await assets.dispose(
      asset.id,
      proceeds: 1500,
      proceedsAccount: 'Bank',
      gainLossAccount: 'Disposal Gain Loss',
    );
    final gain = je.children['accounts']!
        .where((l) => l.payload['account'] == 'Disposal Gain Loss')
        .single;
    expect(asNum(gain.payload['credit']), 300);
  });
}
