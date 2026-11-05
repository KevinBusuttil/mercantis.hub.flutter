import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_hub_app/ledger/ledger_derivation_service.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/books_harness.dart';

/// R6: owed ledger postings can be completed on demand ("Retry owed
/// postings") instead of only by restarting Atlas, without duplicating any
/// posting and without lifting the stock pause before they complete.
void main() {
  setUpAll(sqfliteFfiInit);

  late Directory dir;
  late String path;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('hub_retry_owed_');
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

  Document purchase() {
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

  Document sale() {
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

  /// A ledger service that is running but has NOT done its boot recovery,
  /// so the owed batch is still owed: the state "Retry" is for.
  LedgerDerivationService runningWithoutRecovery(BooksHarness h) {
    final l = LedgerDerivationService(
        engine: h.engine, emitter: h.emitter, database: h.db.db);
    l.start();
    h.ledger = l;
    return l;
  }

  test('retry completes owed postings once, even when tapped twice', () async {
    final h = await BooksHarness.open(path, startLedger: false);
    await masters(h);
    final pi = await h.saveAndSubmit(purchase());
    expect(await h.rowCount('GL Entry', {'voucher_no': pi.id}), 0);

    final ledger = runningWithoutRecovery(h);
    expect(await ledger.outstandingPostings(), hasLength(1));

    final results = await Future.wait(
        [ledger.retryOwedPostings(), ledger.retryOwedPostings()]);
    expect(results.every((r) => r.isEmpty), isTrue);
    expect(await ledger.outstandingPostings(), isEmpty);

    final gl = await h.rowCount('GL Entry', {'voucher_no': pi.id});
    expect(gl, greaterThanOrEqualTo(4));
    // A third retry with nothing owed is a no-op: no duplicate postings.
    expect(await ledger.retryOwedPostings(), isEmpty);
    expect(await h.rowCount('GL Entry', {'voucher_no': pi.id}), gl);
    expect(await h.trialBalanceDifference(), 0);
    await h.close();
  });

  test('stock stays paused until the retry, and the message says how',
      () async {
    final h = await BooksHarness.open(path);
    await masters(h);
    await h.saveAndSubmit(purchase());
    // The sale's derivation fails before its stock movement is written, as a
    // full disk or a crash would leave it.
    await h.db.db.execute(
        'CREATE TEMP TRIGGER fail_sle BEFORE INSERT ON documents '
        "WHEN NEW.doctype = 'Stock Ledger Entry' AND NEW.id NOT LIKE '%PINV%' "
        "BEGIN SELECT RAISE(ABORT, 'injected write failure'); END");
    await h.saveAndSubmit(sale());
    await h.db.db.execute('DROP TRIGGER fail_sle');
    final ledger = h.ledger!;
    expect(await ledger.outstandingPostings(), hasLength(1));

    // Negative: while postings are owed, the next stock document is refused,
    // and the operator is pointed at the retry rather than a restart.
    Object? refused;
    try {
      await h.saveAndSubmit(sale());
    } catch (e) {
      refused = e;
    }
    expect(refused, isNotNull);
    final text = refused is DocumentEngineError
        ? refused.humanMessage
        : refused.toString();
    expect(text, contains('Retry owed postings'));
    expect(text, isNot(contains('Close and reopen')));

    expect(await ledger.retryOwedPostings(), isEmpty);
    final si = await h.saveAndSubmit(sale());
    expect((await h.engine.fetch('Sales Invoice', si.id))!.docStatus, 1);
    expect(await h.trialBalanceDifference(), 0);
    await h.close();
  });
}
