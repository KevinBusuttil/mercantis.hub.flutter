import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_hub_app/backup/business_summary.dart';
import 'package:mercantis_hub_app/backup/hub_backup.dart';
import 'package:mercantis_hub_app/ledger/ledger_values.dart' show asNum;
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/books_harness.dart';

/// Atlas Solo fault injection at the Hub level (Section E of the Solo
/// hardening brief). Core proves the storage primitives (transactions,
/// migrations, archive, journalled restore, child-process kills); the posting
/// outbox tests prove derivation recovery. These prove the assembled books:
/// a submitted document always has its ledger rows and consistent stock,
/// whatever happens around it.
void main() {
  sqfliteFfiInit();
  const passphrase = 'correct horse battery staple';

  late Directory root;
  late String data;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('solo-fault');
    data = p.join(root.path, 'data');
    Directory(data).createSync();
  });
  tearDown(() async {
    if (root.existsSync()) await root.delete(recursive: true);
  });

  String dbPath() => p.join(data, 'mercantis.db');

  Future<void> masters(BooksHarness h) async {
    await h.save(Document(
        id: 'C1',
        docType: 'Customer',
        payload: {'customer_name': 'Blue Fig', 'customer_type': 'Company'}));
    await h.save(Document(
        id: 'S1',
        docType: 'Supplier',
        payload: {'supplier_name': 'Apex', 'supplier_type': 'Company'}));
    await h.save(Document(id: 'W1', docType: 'Item', payload: {
      'item_code': 'W1',
      'item_name': 'Widget',
      'item_type': 'Stock',
      'stock_uom': 'Nos',
    }));
  }

  Future<String> company(BooksHarness h) async =>
      (await h.engine.list('Company', userRoles: systemRoles)).single.id;

  Future<Document> buy(BooksHarness h, num qty, num rate, String date) async =>
      h.saveAndSubmit(Document(
          id: '',
          docType: 'Purchase Invoice',
          company: await company(h),
          payload: {
            'supplier': 'S1',
            'posting_date': date,
            'due_date': date,
            'update_stock': 1,
            'set_warehouse': 'Main Store',
          })
        ..children['items'] = [
          itemLine('Purchase Invoice', {'item': 'W1', 'qty': qty, 'rate': rate}),
        ]);

  Future<Document> sell(BooksHarness h, num qty, num rate, String date) async =>
      h.saveAndSubmit(Document(
          id: '',
          docType: 'Sales Invoice',
          company: await company(h),
          payload: {
            'customer': 'C1',
            'posting_date': date,
            'due_date': date,
            'update_stock': 1,
            'set_warehouse': 'Main Store',
          })
        ..children['items'] = [
          itemLine('Sales Invoice', {'item': 'W1', 'qty': qty, 'rate': rate}),
        ]);

  /// The invariant every scenario ends on: balanced GL, every submitted
  /// posting document has GL rows, nothing owed by the outbox, the stock
  /// ledger agrees with the Bin and with the stock account.
  Future<void> expectConsistent(BooksHarness h) async {
    expect(await h.trialBalanceDifference(), 0);
    expect(await h.ledger!.outstandingPostings(), isEmpty);
    for (final type in const ['Sales Invoice', 'Purchase Invoice']) {
      for (final d in await h.engine.list(type, userRoles: systemRoles)) {
        if (d.docStatus != 1) continue;
        expect(
            await h.rowCount('GL Entry', {'voucher_no': d.id}), greaterThan(0),
            reason: '${d.id} is submitted but has no GL');
      }
    }
    num qty = 0, value = 0;
    for (final s in await h.engine.list('Stock Ledger Entry',
        userRoles: systemRoles)) {
      qty += asNum(s.payload['qty_change']);
      value += asNum(s.payload['qty_change']) * asNum(s.payload['valuation_rate']);
    }
    final bin = await h.bin('W1', 'Main Store');
    expect(asNum(bin?.payload['actual_qty']), closeTo(qty, 1e-9));
    expect(await h.balance('Stock'), closeTo(value, 0.005));
    expect(await h.stockValue(), await h.balance('Stock'));
  }

  test('repeated restart: reopening the books never changes or re-posts them',
      () async {
    var h = await BooksHarness.open(dbPath());
    await masters(h);
    await buy(h, 20, 5, isoToday());
    Map<String, Object?>? summary;
    for (var i = 0; i < 6; i++) {
      await sell(h, 1, 12, isoToday());
      final before = await BusinessSummary.compute(h.db.db);
      await h.close();
      h = await BooksHarness.open(dbPath());
      // Boot ran migrations, metadata sync and posting recovery again.
      expect(await BusinessSummary.compute(h.db.db), before);
      summary = before;
    }
    expect((summary!['submitted_counts'] as Map)['Sales Invoice'], 6);
    expect(asNum((await h.bin('W1', 'Main Store'))!.payload['actual_qty']), 14);
    await expectConsistent(h);
    await h.close();
  });

  test('long-term offline: months of trading with no sync stays consistent '
      'and every change waits in the outbound queue', () async {
    final h = await BooksHarness.open(dbPath());
    await masters(h);
    final queuedAtStart = await h.db.db
        .rawQuery("SELECT COUNT(*) AS n FROM sync_queue WHERE status = 'pending'");
    final year = DateTime.now().year;
    var docs = 0;
    for (var month = 1; month <= 9; month++) {
      final date = '$year-${month.toString().padLeft(2, '0')}-15';
      await buy(h, 10, 5 + month / 10, date);
      for (var d = 0; d < 3; d++) {
        await sell(h, 2, 12, date);
      }
      docs += 4;
    }
    await expectConsistent(h);
    expect(asNum((await h.bin('W1', 'Main Store'))!.payload['actual_qty']),
        90 - 54);
    final queued = await h.db.db
        .rawQuery("SELECT COUNT(*) AS n FROM sync_queue WHERE status = 'pending'");
    expect((queued.first['n'] as int) - (queuedAtStart.first['n'] as int),
        greaterThanOrEqualTo(docs),
        reason: 'nothing is dropped while offline');
    await h.close();
  });

  test('repeated submit (double tap, retry after a timeout) posts once',
      () async {
    final h = await BooksHarness.open(dbPath());
    await masters(h);
    await buy(h, 5, 5, isoToday());
    final draft = await h.save(Document(
        id: '',
        docType: 'Sales Invoice',
        company: await company(h),
        payload: {
          'customer': 'C1',
          'posting_date': isoToday(),
          'due_date': isoToday(),
          'update_stock': 1,
          'set_warehouse': 'Main Store',
        })
      ..children['items'] = [
        itemLine('Sales Invoice', {'item': 'W1', 'qty': 1, 'rate': 12}),
      ]);
    await h.submit(draft);
    final gl = await h.rowCount('GL Entry', {'voucher_no': draft.id});
    // The same draft object submitted again, as a retry would.
    await expectLater(h.submit(draft), throwsA(anything));
    final fresh = await h.engine.fetch('Sales Invoice', draft.id);
    await expectLater(h.submit(fresh!), throwsA(anything));
    expect(await h.rowCount('GL Entry', {'voucher_no': draft.id}), gl);
    expect(asNum((await h.bin('W1', 'Main Store'))!.payload['actual_qty']), 4);
    await expectConsistent(h);
    await h.close();
  });

  test('database write failure during submit: the invoice stays a draft with '
      'no ledger rows, and nothing is left owed', () async {
    final h = await BooksHarness.open(dbPath());
    await masters(h);
    await buy(h, 5, 5, isoToday());
    final draft = await h.save(Document(
        id: '',
        docType: 'Sales Invoice',
        company: await company(h),
        payload: {
          'customer': 'C1',
          'posting_date': isoToday(),
          'due_date': isoToday(),
          'update_stock': 1,
          'set_warehouse': 'Main Store',
        })
      ..children['items'] = [
        itemLine('Sales Invoice', {'item': 'W1', 'qty': 1, 'rate': 12}),
      ]);
    // The audit write inside the submit transaction fails.
    await h.db.db.execute('''
      CREATE TEMP TRIGGER fail_audit BEFORE INSERT ON audit_log
      BEGIN SELECT RAISE(ABORT, 'injected write failure'); END''');
    await expectLater(h.submit(draft), throwsA(anything));
    await h.db.db.execute('DROP TRIGGER fail_audit');
    expect((await h.engine.fetch('Sales Invoice', draft.id))!.docStatus, 0);
    expect(await h.rowCount('GL Entry', {'voucher_no': draft.id}), 0);
    await expectConsistent(h);
    // Once the fault clears the same draft submits normally.
    await h.submit((await h.engine.fetch('Sales Invoice', draft.id))!);
    await expectConsistent(h);
    await h.close();
  });

  test('low storage while trading: refused cleanly, never a half-posted '
      'invoice', () async {
    final h = await BooksHarness.open(dbPath());
    await masters(h);
    await buy(h, 500, 5, isoToday());
    // Compact, then cap the file at its current size: page allocations fail
    // with SQLITE_FULL, exactly as on a full disk.
    await h.db.db.execute('VACUUM');
    final pages =
        (await h.db.db.rawQuery('PRAGMA page_count')).first.values.first as int;
    await h.db.db.execute('PRAGMA max_page_count = $pages');
    Object? error;
    try {
      for (var i = 0; i < 300; i++) {
        await sell(h, 1, 12, isoToday());
      }
    } catch (e) {
      error = e;
    }
    await h.db.db.execute('PRAGMA max_page_count = 1073741823');
    expect(error, isNotNull, reason: 'the store must refuse, not truncate');
    expect(await h.db.quickCheck(), isTrue);
    // Restart: recovery completes anything a full disk interrupted.
    await h.close();
    final after = await BooksHarness.open(dbPath());
    await expectConsistent(after);
    await after.close();
  });

  group('backup and restore faults', () {
    Future<(BooksHarness, Map<String, Object?>, String)> booksWithBackup() async {
      final h = await BooksHarness.open(dbPath());
      await masters(h);
      await buy(h, 10, 5, isoToday());
      await sell(h, 3, 12, isoToday());
      final backup = HubBackup(dataDirectory: data, factory: databaseFactoryFfi);
      final file = p.join(root.path, 'b.atlasbackup');
      await backup.createBackup(
          database: h.db.db, passphrase: passphrase, outputPath: file);
      // Trade on after the backup, so "live" and "backup" differ.
      await sell(h, 1, 12, isoToday());
      return (h, await BusinessSummary.compute(h.db.db), file);
    }

    for (final step in RestoreStep.values) {
      test('restore failing at ${step.name}: live books intact or the backup '
          'fully installed, never a mix', () async {
        final (h, live, file) = await booksWithBackup();
        final backup =
            HubBackup(dataDirectory: data, factory: databaseFactoryFfi);
        final staged = await backup.stage(file, passphrase);
        final restored = staged.businessSummary;
        await h.close();
        Object? error;
        try {
          await backup.commit(staged, onStep: (s) async {
            if (s == step) throw StateError('injected at ${s.name}');
          });
        } catch (e) {
          error = e;
        }
        expect(error, isNotNull);
        // Next start, as the app does before opening the database.
        AtlasBackupService.recoverInterruptedRestore(backup.target,
            safetyCopyDirectory: backup.safetyCopyDirectory);
        final after = await BooksHarness.open(dbPath());
        final summary = await BusinessSummary.compute(after.db.db);
        expect(summary, anyOf(equals(live), equals(restored)));
        if (step != RestoreStep.committed) expect(summary, live);
        await expectConsistent(after);
        await after.close();
      });
    }

    test('a sale made while the backup is written does not make it '
        'unrestorable', () async {
      final h = await BooksHarness.open(dbPath());
      await masters(h);
      await buy(h, 10, 5, isoToday());
      final backup = HubBackup(dataDirectory: data, factory: databaseFactoryFfi);
      backup.service.faultHook = (step) async {
        if (step == 'snapshot') await sell(h, 3, 12, isoToday());
      };
      final file = p.join(root.path, 'b.atlasbackup');
      await backup.createBackup(
          database: h.db.db, passphrase: passphrase, outputPath: file);
      backup.service.faultHook = null;
      final staged = await backup.stage(file, passphrase);
      await h.close();
      await backup.commit(staged);
      final after = await BooksHarness.open(dbPath());
      expect(await BusinessSummary.compute(after.db.db),
          staged.businessSummary);
      expect(await after.balance('Stock'), 50,
          reason: 'the sale came after the snapshot');
      await expectConsistent(after);
      await after.close();
    });

    test('a backup whose books do not reproduce its recorded totals is not '
        'installed', () async {
      final (h, live, file) = await booksWithBackup();
      final backup = HubBackup(dataDirectory: data, factory: databaseFactoryFfi);
      final staged = await backup.stage(file, passphrase);
      // Tamper with the staged books after decryption: one GL row goes.
      final db = await databaseFactoryFfi.openDatabase(staged.databasePath,
          options: OpenDatabaseOptions(singleInstance: false));
      await db.rawDelete(
          'DELETE FROM documents WHERE id IN (SELECT id FROM documents '
          "WHERE doctype = 'GL Entry' LIMIT 1)");
      await db.close();
      await h.close();
      await expectLater(
          backup.commit(staged), throwsA(isA<RestoreVerificationException>()));
      final after = await BooksHarness.open(dbPath());
      expect(await BusinessSummary.compute(after.db.db), live);
      await after.close();
    });

    test('disk full while writing a backup: no partial backup left, books '
        'untouched', () async {
      final h = await BooksHarness.open(dbPath());
      await masters(h);
      await buy(h, 10, 5, isoToday());
      final before = await BusinessSummary.compute(h.db.db);
      final backup = HubBackup(dataDirectory: data, factory: databaseFactoryFfi);
      final out = p.join(root.path, 'out', 'b.atlasbackup');
      Directory(p.dirname(out)).createSync();
      backup.service.faultHook = (stage) async {
        if (stage == 'attachments-written') {
          throw const FileSystemException('No space left on device');
        }
      };
      await expectLater(
          backup.createBackup(
              database: h.db.db, passphrase: passphrase, outputPath: out),
          throwsA(anything));
      expect(Directory(p.dirname(out)).listSync(), isEmpty);
      expect(await BusinessSummary.compute(h.db.db), before);
      await h.close();
    });
  });
}
