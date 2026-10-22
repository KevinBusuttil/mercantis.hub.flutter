import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_hub_app/ledger/ledger_values.dart' show asNum;
import 'package:mercantis_hub_app/ledger/posting_outbox.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/books_harness.dart';

/// M1.5 core invariant: a submitted (or cancelled) voucher always ends up with
/// its complete ledger postings, even when the app dies or a write fails
/// between the submit and the derivation. The outbox marker commits with the
/// submit; startup recovery finishes the job without duplicating anything.
void main() {
  setUpAll(sqfliteFfiInit);

  late Directory dir;
  late String path;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('hub_outbox_');
    path = p.join(dir.path, 'books.db');
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Future<void> masters(BooksHarness h) async {
    await h.save(Document(
        id: 'WH', docType: 'Warehouse', payload: {'warehouse_name': 'Main'}));
    await h.save(Document(id: 'CUST-1', docType: 'Customer', payload: {
      'customer_name': 'Blue Fig Café',
      'customer_type': 'Company',
    }));
    await h.save(Document(id: 'SUPP-1', docType: 'Supplier', payload: {
      'supplier_name': 'Apex Supplies',
      'supplier_type': 'Company',
    }));
    await h.save(Document(id: 'ITEM-A', docType: 'Item', payload: {
      'item_code': 'ITEM-A',
      'item_name': 'Item A',
      'item_type': 'Stock',
      'stock_uom': 'Nos',
      'valuation_method': 'Moving Average',
    }));
  }

  Document purchase10At5() {
    final pi = Document(id: '', docType: 'Purchase Invoice', payload: {
      'supplier': 'SUPP-1',
      'posting_date': isoToday(),
      'update_stock': 1,
      'set_warehouse': 'WH',
    });
    pi.children['items'] = [
      itemLine('Purchase Invoice', {'item': 'ITEM-A', 'qty': 10, 'rate': 5}),
    ];
    return pi;
  }

  Document sale3At12() {
    final si = Document(id: '', docType: 'Sales Invoice', payload: {
      'customer': 'CUST-1',
      'posting_date': isoToday(),
      'update_stock': 1,
      'set_warehouse': 'WH',
    });
    si.children['items'] = [
      itemLine('Sales Invoice', {'item': 'ITEM-A', 'qty': 3, 'rate': 12}),
    ];
    return si;
  }

  Future<String?> batchStatus(BooksHarness h, String id) async {
    final rows = await h.db.db
        .query('posting_batches', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : rows.single['status'] as String;
  }

  test('a normal submit marks its outbox batch posted', () async {
    final h = await BooksHarness.open(path);
    await masters(h);
    final pi = await h.saveAndSubmit(purchase10At5());
    expect(
        await batchStatus(h,
            postingBatchId('Purchase Invoice', pi.id, LifecycleAction.submit)),
        'posted');
    expect(await h.trialBalanceDifference(), 0);
    await h.close();
  });

  test('app killed after submit, before postings: restart completes them',
      () async {
    // First run: the ledger service is not running, which is exactly the
    // state a process killed right after the submit committed leaves behind.
    var h = await BooksHarness.open(path, startLedger: false);
    await masters(h);
    final pi = await h.saveAndSubmit(purchase10At5());
    expect((await h.engine.fetch('Purchase Invoice', pi.id))!.docStatus, 1);
    expect(await h.rowCount('GL Entry', {'voucher_no': pi.id}), 0,
        reason: 'submitted, not yet posted');
    expect(
        await batchStatus(h,
            postingBatchId('Purchase Invoice', pi.id, LifecycleAction.submit)),
        'pending');
    await h.close();

    // Restart: boot recovery posts it.
    h = await BooksHarness.open(path);
    expect(await h.ledger!.outstandingPostings(), isEmpty);
    expect(await h.rowCount('GL Entry', {'voucher_no': pi.id}),
        greaterThanOrEqualTo(4));
    expect(await h.trialBalanceDifference(), 0);
    expect(await h.balance('Stock'), 50);
    expect(asNum((await h.bin('ITEM-A', 'WH'))!.payload['actual_qty']), 10);
    final outstanding =
        (await h.engine.fetch('Purchase Invoice', pi.id))!.payload['outstanding_amount'];
    expect(asNum(outstanding), asNum((await h.engine.fetch('Purchase Invoice', pi.id))!.payload['grand_total']));
    await h.close();
  });

  test('a write failure part-way through posting is repaired without duplicates',
      () async {
    var h = await BooksHarness.open(path);
    await masters(h);
    await h.saveAndSubmit(purchase10At5());

    // Fail the sale's Cr Income leg after its Dr Receivable leg and stock
    // movement were already written: the books are now visibly unbalanced.
    await h.db.db.execute(
        'CREATE TEMP TRIGGER fail_income BEFORE INSERT ON documents '
        "WHEN NEW.doctype = 'GL Entry' AND NEW.id LIKE 'GL-%-credit' "
        "BEGIN SELECT RAISE(ABORT, 'injected write failure'); END");
    final si = await h.saveAndSubmit(sale3At12());
    final batch = postingBatchId('Sales Invoice', si.id, LifecycleAction.submit);
    expect(await batchStatus(h, batch), 'failed');
    expect(await h.trialBalanceDifference(), isNot(0),
        reason: 'the danger the outbox exists for');
    await h.db.db.execute('DROP TRIGGER fail_income');
    await h.close();

    h = await BooksHarness.open(path);
    expect(await batchStatus(h, batch), 'posted');
    expect(await h.trialBalanceDifference(), 0);
    expect(await h.balance('Stock'), 35);
    expect(await h.balance('COGS'), 15,
        reason: "re-costing ignores the voucher's own half-written rows");
    expect(asNum((await h.bin('ITEM-A', 'WH'))!.payload['actual_qty']), 7);
    final glRows = await h.rowCount('GL Entry', {'voucher_no': si.id});

    // Recovery again (another restart) changes nothing.
    await h.close();
    h = await BooksHarness.open(path);
    expect(await h.rowCount('GL Entry', {'voucher_no': si.id}), glRows);
    expect(await h.rowCount('Stock Ledger Entry', {'voucher_no': si.id}), 1);
    expect(await h.trialBalanceDifference(), 0);
    await h.close();
  });

  test('a cancel interrupted before its reversal is completed on restart',
      () async {
    var h = await BooksHarness.open(path);
    await masters(h);
    await h.saveAndSubmit(purchase10At5());
    final si = await h.saveAndSubmit(sale3At12());
    h.ledger!.dispose(); // the process dies right after the cancel commits
    await h.engine.cancel(si, systemRoles);
    expect(await h.balance('COGS'), 15, reason: 'reversal not yet posted');
    await h.close();

    h = await BooksHarness.open(path);
    expect(await h.balance('COGS'), 0);
    expect(await h.balance('Stock'), 50);
    expect(await h.trialBalanceDifference(), 0);
    expect(
        await batchStatus(h,
            postingBatchId('Sales Invoice', si.id, LifecycleAction.cancel)),
        'posted');
    await h.close();
  });

  group('a voucher cancelled while its submit posting is still owed', () {
    Future<(BooksHarness, Document)> failedSale() async {
      final h = await BooksHarness.open(path);
      await masters(h);
      await h.saveAndSubmit(purchase10At5());
      // The sale's derivation fails before its stock movement is written.
      await h.db.db.execute(
          'CREATE TEMP TRIGGER fail_sle BEFORE INSERT ON documents '
          "WHEN NEW.doctype = 'Stock Ledger Entry' AND NEW.id NOT LIKE '%PINV%' "
          "BEGIN SELECT RAISE(ABORT, 'injected write failure'); END");
      final si = await h.saveAndSubmit(sale3At12());
      expect(
          await batchStatus(h,
              postingBatchId('Sales Invoice', si.id, LifecycleAction.submit)),
          'failed');
      await h.db.db.execute('DROP TRIGGER fail_sle');
      return (h, si);
    }

    Future<void> expectNetZero(BooksHarness h, Document si) async {
      for (final action in LifecycleAction.values) {
        expect(
            await batchStatus(
                h, postingBatchId('Sales Invoice', si.id, action)),
            'posted',
            reason: action.name);
      }
      expect(await h.trialBalanceDifference(), 0);
      expect(await h.balance('COGS'), 0);
      expect(await h.balance('Stock'), 50);
      expect(await h.balance('Debtors'), 0);
      expect(asNum((await h.bin('ITEM-A', 'WH'))!.payload['actual_qty']), 10);
      expect(asNum((await h.bin('ITEM-A', 'WH'))!.payload['stock_value']), 50);
    }

    test('cancelled in the same session: the original posts first', () async {
      final (h, si) = await failedSale();
      await h.engine.cancel(
          (await h.engine.fetch('Sales Invoice', si.id))!, systemRoles);
      await expectNetZero(h, si);
      await h.close();
      // And a restart re-posts nothing.
      final again = await BooksHarness.open(path);
      await expectNetZero(again, si);
      await again.close();
    });

    test('cancelled, then the app restarts: recovery posts original, then '
        'reversal', () async {
      final (h, si) = await failedSale();
      h.ledger!.dispose(); // the process dies right after the cancel commits
      await h.engine.cancel(
          (await h.engine.fetch('Sales Invoice', si.id))!, systemRoles);
      await h.close();
      final again = await BooksHarness.open(path);
      await expectNetZero(again, si);
      await again.close();
    });
  });

  test('recovery replays owed vouchers in the order they were entered',
      () async {
    var h = await BooksHarness.open(path);
    await masters(h);
    await h.saveAndSubmit(purchase10At5());
    await h.close();

    // Both owed: a sale of 3 (met stock at 5.00), then a purchase at 20.
    // The purchase draft was created first; submission order is what counts.
    h = await BooksHarness.open(path, startLedger: false);
    final dearer = purchase10At5();
    dearer.children['items'] = [
      itemLine('Purchase Invoice', {'item': 'ITEM-A', 'qty': 10, 'rate': 20}),
    ];
    final dearerDraft = await h.save(dearer);
    await h.saveAndSubmit(sale3At12());
    await h.submit(dearerDraft);
    expect(await h.ledger?.outstandingPostings() ?? const [], isEmpty,
        reason: 'no ledger in this run');
    await h.close();

    h = await BooksHarness.open(path);
    expect(await h.ledger!.outstandingPostings(), isEmpty);
    expect(await h.balance('COGS'), 15,
        reason: 'the sale is costed at the stock it met, not after the '
            'later purchase');
    expect(await h.balance('Stock'), 235);
    expect(await h.trialBalanceDifference(), 0);
    await h.close();
  });

  test('stock documents wait while an earlier stock posting is owed',
      () async {
    var h = await BooksHarness.open(path);
    await masters(h);
    await h.saveAndSubmit(purchase10At5());
    await h.db.db.execute(
        'CREATE TEMP TRIGGER fail_sle BEFORE INSERT ON documents '
        "WHEN NEW.doctype = 'Stock Ledger Entry' "
        "BEGIN SELECT RAISE(ABORT, 'injected write failure'); END");
    final si = await h.saveAndSubmit(sale3At12());
    await h.db.db.execute('DROP TRIGGER fail_sle');
    expect(
        await batchStatus(
            h, postingBatchId('Sales Invoice', si.id, LifecycleAction.submit)),
        'failed');

    // A later stock movement would be costed without the owed sale.
    final dearer = purchase10At5();
    dearer.children['items'] = [
      itemLine('Purchase Invoice', {'item': 'ITEM-A', 'qty': 10, 'rate': 20}),
    ];
    final draft = await h.save(dearer);
    await expectLater(h.submit(draft), throwsA(isA<DocumentEngineError>()));
    expect((await h.engine.fetch('Purchase Invoice', draft.id))!.docStatus, 0);
    await h.close();

    // The next start posts the sale; then the purchase goes through and the
    // sale is costed at the stock it met.
    h = await BooksHarness.open(path);
    await h.submit((await h.engine.fetch('Purchase Invoice', draft.id))!);
    expect(await h.balance('COGS'), 15);
    expect(await h.trialBalanceDifference(), 0);
    await h.close();
  });

  test('legacy vouchers without an outbox batch are never re-posted',
      () async {
    var h = await BooksHarness.open(path);
    await masters(h);
    final pi = await h.saveAndSubmit(purchase10At5());
    // Simulate a voucher posted by an older build: no batch row.
    await h.db.db.delete('posting_batches');
    final before = await h.rowCount('GL Entry');
    await h.close();
    h = await BooksHarness.open(path);
    expect(await h.rowCount('GL Entry'), before);
    expect(await h.rowCount('GL Entry', {'voucher_no': pi.id}),
        greaterThanOrEqualTo(4));
    await h.close();
  });

  test('disk full during posting: nothing silent, repaired once space returns',
      () async {
    var h = await BooksHarness.open(path);
    await masters(h);
    await h.saveAndSubmit(purchase10At5());
    final draft = await h.save(sale3At12());
    final pages = (await h.db.db.rawQuery('PRAGMA page_count')).first.values.first as int;
    // Leave room for the submit itself, not for its ledger rows.
    await h.db.db.execute('PRAGMA max_page_count = ${pages + 2}');
    Document? submitted;
    try {
      submitted = await h.submit(draft);
    } catch (_) {
      // The submit itself may be refused when the disk is full: then nothing
      // was submitted and nothing is owed.
    }
    await h.db.db.execute('PRAGMA max_page_count = 1073741823');
    await h.close();

    h = await BooksHarness.open(path);
    expect(await h.db.quickCheck(), isTrue);
    expect(await h.trialBalanceDifference(), 0);
    final doc = await h.engine.fetch('Sales Invoice', draft.id);
    if (submitted != null || doc!.docStatus == 1) {
      expect(await h.rowCount('GL Entry', {'voucher_no': draft.id}),
          greaterThanOrEqualTo(4));
      expect(await h.balance('COGS'), 15);
    } else {
      expect(await h.rowCount('GL Entry', {'voucher_no': draft.id}), 0);
    }
    expect(await h.ledger!.outstandingPostings(), isEmpty);
    await h.close();
  });
}
