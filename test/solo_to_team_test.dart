import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_hub_app/team/solo_to_team.dart';
import 'package:mercantis_hub_app/team/solo_to_team_runner.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/books_harness.dart';

/// C3 — the Solo side of moving a book into Atlas Team, without a server:
/// preflight, the take-on package, what is published, reconciliation and
/// the crash-safe switch. The server half and the full round trip run in
/// test/team_e2e/solo_to_team_e2e_test.dart against a real backend.
void main() {
  setUpAll(sqfliteFfiInit);

  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('solo_to_team_'));
  tearDown(() => dir.deleteSync(recursive: true));

  Future<BooksHarness> book({bool history = true}) async {
    final h = await BooksHarness.open(p.join(dir.path, 'mercantis.db'));
    await h.save(Document(id: 'C-1', docType: 'Customer', payload: {
      'customer_name': 'Harbour Bar',
      'customer_type': 'Company',
    }));
    await h.save(Document(id: 'S-1', docType: 'Supplier', payload: {
      'supplier_name': 'Glassworks',
    }));
    await h.save(Document(id: 'BOTTLE', docType: 'Item', payload: {
      'item_code': 'BOTTLE',
      'item_name': 'Bottle',
      'item_type': 'Stock',
      'stock_uom': 'Nos',
      'valuation_method': 'Moving Average',
    }));
    if (!history) return h;
    await h
        .saveAndSubmit(Document(id: '', docType: 'Purchase Invoice', payload: {
      'supplier': 'S-1',
      'posting_date': '2026-10-01',
      'update_stock': 1,
      'set_warehouse': 'Main Store',
    })
          ..children['items'] = [
            itemLine('Purchase Invoice', {
              'item': 'BOTTLE',
              'qty': 10,
              'rate': 5,
              'warehouse': 'Main Store'
            }),
          ]);
    await h.saveAndSubmit(Document(id: '', docType: 'Sales Invoice', payload: {
      'customer': 'C-1',
      'posting_date': '2026-10-02',
      'update_stock': 1,
      'set_warehouse': 'Main Store',
    })
      ..children['items'] = [
        itemLine('Sales Invoice', {
          'item': 'BOTTLE',
          'qty': 3,
          'rate': 12,
          'warehouse': 'Main Store'
        }),
      ]);
    return h;
  }

  test('a consistent book passes preflight; its figures reconcile', () async {
    final h = await book();
    final c = SoloToTeamConversion(h.db.db);
    final pre =
        await c.preflight(cutoverDate: '2026-11-05', teamConnected: false);
    expect(pre.blockers.map((b) => b.message), isEmpty);
    expect(pre.checks.map((b) => b.id), containsAll(['history', 'devices']));
    final f = pre.figures;
    expect(f.trialBalance.values.fold<num>(0, (a, b) => a + b).abs(),
        lessThan(0.005));
    expect(f.stock.single.qty, 7);
    expect(f.stock.single.value, 35);
    expect(f.receivables, f.customerBalances['C-1']);
    expect(f.payables, f.supplierBalances['S-1']);
    await h.close();
  });

  test('the package carries the trial balance by party, stock and numbering',
      () async {
    final h = await book();
    final c = SoloToTeamConversion(h.db.db);
    final pkg = await c.buildPackage(
        migrationId: 'mig-00000001', cutoverDate: '2026-11-05');
    num dr = 0, cr = 0;
    for (final l in pkg.lines) {
      dr += l['debit'] as num;
      cr += l['credit'] as num;
    }
    expect((dr - cr).abs(), lessThan(0.005), reason: 'balanced');
    expect(pkg.lines.where((l) => l['party'] == 'C-1'), isNotEmpty);
    expect(pkg.lines.where((l) => l['party'] == 'S-1'), isNotEmpty);
    expect(pkg.stock.single['qty'], 7);
    final sinv =
        pkg.numbering.firstWhere((n) => n['doctype'] == 'Sales Invoice');
    expect(sinv['last_value'], 1);
    expect('${sinv['last_issued']}', endsWith('1'));
    expect(pkg.documentId, 'SOLO-OPENING-mig-00000001');
    await h.close();
  });

  test('only non-official documents are published, with stable ids', () async {
    final h = await book();
    final c = SoloToTeamConversion(h.db.db);
    final rows = await c.masterRows();
    final types = rows.map((r) => r['doctype']).toSet();
    expect(types,
        containsAll(['Customer', 'Supplier', 'Item', 'Account', 'Company']));
    // Negative: no ledger row and no submitted voucher is ever published.
    for (final t in [
      'GL Entry',
      'Stock Ledger Entry',
      'Bin',
      'Customer Transaction',
      'Supplier Transaction',
      'Posting Batch',
    ]) {
      expect(types, isNot(contains(t)), reason: t);
    }
    expect(
        rows.where((r) =>
            SoloToTeamConversion.historyDocTypes.contains(r['doctype']) &&
            (r['docstatus'] as int) >= 1),
        isEmpty);
    final a = await c.masterMutations(
        migrationId: 'mig-00000001', deviceId: 'd', userId: 'u');
    final b = await c.masterMutations(
        migrationId: 'mig-00000001', deviceId: 'd', userId: 'u');
    expect(a.map((m) => m.id).toList(), b.map((m) => m.id).toList(),
        reason: 'a retried push re-sends the same mutation ids');
    expect(a.every((m) => m.id.startsWith('smig-')), isTrue);
    expect(await soloHistoryCount(h.db.db), 2);
    await h.close();
  });

  test('preflight blocks what would not reconcile or would be refused',
      () async {
    final h = await book();
    final c = SoloToTeamConversion(h.db.db);

    // Already connected, a later-dated document, a lock on the cut-over
    // date, owed postings and a numbering hold each block on their own.
    var pre = await c.preflight(
        cutoverDate: '2026-10-01',
        teamConnected: true,
        numberingHolds: {'Sales Invoice'});
    expect(pre.blockers.map((b) => b.id),
        containsAll(['team', 'future', 'numbering']));

    final company =
        (await h.engine.list('Company', userRoles: systemRoles)).single;
    company.payload['books_lock_date'] = '2026-11-30';
    await h.save(company);
    await h.db.db.update('posting_batches', {'status': 'failed'});
    pre = await c.preflight(cutoverDate: '2026-11-05', teamConnected: false);
    expect(pre.blockers.map((b) => b.id), containsAll(['lock', 'owed']));
    expect(pre.canProceed, isFalse);
    await h.close();
  });

  test('preflight blocks stock that does not agree with the ledger', () async {
    final h = await book();
    // A bin edited behind the ledger's back (what a bad import would leave).
    final bin = (await h.engine.list('Bin', userRoles: systemRoles)).single;
    await h.db.db.update(
        'documents',
        {
          'payload':
              '{"item":"BOTTLE","warehouse":"Main Store","actual_qty":7,"stock_value":99,"valuation_rate":14.14}'
        },
        where: 'id = ?',
        whereArgs: [bin.id]);
    final pre = await SoloToTeamConversion(h.db.db)
        .preflight(cutoverDate: '2026-11-05', teamConnected: false);
    expect(pre.blockers.map((b) => b.id), contains('stock_vs_ledger'));
    await h.close();
  });

  test('reconcile finds every account, party and stock difference', () async {
    final solo = await book();
    final figures = await SoloToTeamConversion(solo.db.db).figures();
    await solo.close();

    final other = await BooksHarness.open(p.join(dir.path, 'other.db'));
    final problems = await SoloToTeamConversion.reconcile(figures, other.db.db);
    expect(problems.where((x) => x.startsWith('Account')), isNotEmpty);
    expect(problems.where((x) => x.startsWith('Customer C-1')), isNotEmpty);
    expect(problems.where((x) => x.startsWith('Stock BOTTLE in Main Store')),
        isNotEmpty);

    // And a book compared with itself has none.
    final same = await SoloToTeamConversion.reconcile(
        await SoloToTeamConversion(other.db.db).figures(), other.db.db);
    expect(same, isEmpty);
    await other.close();
  });

  test('the switch archives the Solo book before replacing it', () async {
    final live = p.join(dir.path, 'mercantis.db');
    final solo = await book();
    final soloTb =
        (await SoloToTeamConversion(solo.db.db).figures()).trialBalance;
    await solo.close();
    final teamPath = p.join(dir.path, 'staging', 'mercantis.db');
    final team = await BooksHarness.open(teamPath, deviceId: 'team');
    await team.close();

    final archived = await SoloToTeamRunner.switchToTeamBook(
      liveDatabasePath: live,
      teamBookPath: teamPath,
      archiveDirectory: p.join(dir.path, 'solo-archive', 'mig'),
      factory: databaseFactoryFfi,
    );
    final archive = await databaseFactoryFfi.openDatabase(archived);
    expect(
        (await SoloToTeamConversion(archive).figures()).trialBalance, soloTb);
    expect(await soloHistoryCount(archive), 2);
    await archive.close();
    final now = await databaseFactoryFfi.openDatabase(live);
    expect(await soloHistoryCount(now), 0, reason: 'the Team book is live');
    await now.close();
    expect(File(teamPath).existsSync(), isFalse);
  });

  test('a damaged archive copy stops the switch with the Solo book live',
      () async {
    final live = p.join(dir.path, 'mercantis.db');
    final solo = await book(history: false);
    await solo.close();
    final archiveDir = p.join(dir.path, 'solo-archive', 'mig');
    // The archive location is a file, not a folder: the copy cannot be made.
    File(archiveDir).createSync(recursive: true);
    final teamPath = p.join(dir.path, 'staging', 'mercantis.db');
    File(teamPath).createSync(recursive: true);
    await expectLater(
      SoloToTeamRunner.switchToTeamBook(
        liveDatabasePath: live,
        teamBookPath: teamPath,
        archiveDirectory: archiveDir,
        factory: databaseFactoryFfi,
      ),
      throwsA(anything),
    );
    final still = await databaseFactoryFfi.openDatabase(live);
    expect(
        (await still
            .query('documents', where: 'doctype = ?', whereArgs: ['Company'])),
        isNotEmpty,
        reason: 'the Solo book is still live');
    await still.close();
  });
}
