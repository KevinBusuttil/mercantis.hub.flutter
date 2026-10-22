import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_hub_app/ledger/bin_identity.dart';
import 'package:mercantis_hub_app/ledger/hub_interceptors.dart';
import 'package:mercantis_hub_app/ledger/ledger_values.dart' show asNum;
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/books_harness.dart';

/// R14: Bin ids are `BIN-<item>-<warehouse>`, so item `A-B` in `C` and item
/// `A` in `B-C` share one id. This proves the consequence (stock valuation
/// silently disagrees with the ledger) and that new colliding codes are now
/// refused before they can reach the books.
void main() {
  setUpAll(sqfliteFfiInit);

  late Directory dir;
  late String path;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('hub_bin_identity_');
    path = p.join(dir.path, 'books.db');
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Future<void> supplier(BooksHarness h) => h.save(Document(
      id: 'SUPP-1',
      docType: 'Supplier',
      payload: {'supplier_name': 'Apex', 'supplier_type': 'Company'}));

  Document item(String id) => Document(id: id, docType: 'Item', payload: {
        'item_code': id,
        'item_name': id,
        'item_type': 'Stock',
        'stock_uom': 'Nos',
        'valuation_method': 'Moving Average',
      });

  Document warehouse(String id) =>
      Document(id: id, docType: 'Warehouse', payload: {'warehouse_name': id});

  Future<void> buy(BooksHarness h, String item, String wh, num qty, num rate) {
    final pi = Document(id: '', docType: 'Purchase Invoice', payload: {
      'supplier': 'SUPP-1',
      'posting_date': isoToday(),
      'update_stock': 1,
      'set_warehouse': wh,
    });
    pi.children['items'] = [
      itemLine('Purchase Invoice', {'item': item, 'qty': qty, 'rate': rate}),
    ];
    return h.saveAndSubmit(pi);
  }

  test('findBinCollisions finds exactly the ambiguous pairs', () {
    expect(findBinCollisions(['A', 'A-B'], ['C', 'B-C']), hasLength(1));
    final c = findBinCollisions(['A', 'A-B'], ['C', 'B-C']).single;
    expect(c.binId, 'BIN-A-B-C');
    expect(findBinCollisions(['A-B', 'X-Y'], ['Main Store']), isEmpty);
    expect(findBinCollisions(['WIDGET', 'GADGET'], ['Shop-1', 'Shop-2']),
        isEmpty);
  });

  test('without the guard, a collision silently misstates stock', () async {
    // The pre-fix interceptor set: everything except the new guard.
    final h = await BooksHarness.open(path,
        interceptors: [
          for (final i in hubInterceptors)
            if (i is! BinIdentityGuardInterceptor) i,
        ]);
    await supplier(h);
    for (final w in ['C', 'B-C']) {
      await h.save(warehouse(w));
    }
    await h.save(item('A-B'));
    await h.save(item('A'));

    await buy(h, 'A-B', 'C', 10, 5); // 50.00 of stock
    await buy(h, 'A', 'B-C', 4, 2); // 8.00 of stock, same Bin id

    expect(await h.balance('Stock'), 58, reason: 'the ledger is right');
    expect(await h.rowCount('Bin'), 1, reason: 'two positions, one Bin');
    expect(await h.stockValue(), isNot(58),
        reason: 'stock valuation (from Bins) no longer matches the ledger');
    await h.close();
  });

  group('with the production interceptors', () {
    late BooksHarness h;
    setUp(() async {
      h = await BooksHarness.open(path);
      await supplier(h);
    });
    tearDown(() => h.close());

    Future<String> refusal(Future<Object?> f) async {
      try {
        await f;
      } on DocumentEngineError catch (e) {
        return e.humanMessage;
      }
      fail('expected the save to be refused');
    }

    test('a new item that would collide is refused, books unaffected',
        () async {
      await h.save(warehouse('C'));
      await h.save(warehouse('B-C'));
      await h.save(item('A-B'));
      await buy(h, 'A-B', 'C', 10, 5);

      final msg = await refusal(h.save(item('A')));
      expect(msg, contains('BIN-A-B-C'));
      expect(msg, contains('"A-B"'));
      expect(await h.engine.fetch('Item', 'A'), isNull);
      expect(await h.stockValue(), await h.balance('Stock'));
    });

    test('the longer half is refused too', () async {
      await h.save(warehouse('C'));
      await h.save(warehouse('B-C'));
      await h.save(item('A'));
      expect(await refusal(h.save(item('A-B'))), contains('BIN-A-B-C'));
    });

    test('a new warehouse that would collide is refused', () async {
      await h.save(warehouse('C'));
      await h.save(item('A-B'));
      await h.save(item('A'));
      expect(await refusal(h.save(warehouse('B-C'))), contains('BIN-A-B-C'));
      expect(await h.engine.fetch('Warehouse', 'B-C'), isNull);
    });

    test('unambiguous codes, re-saves and generated ids are accepted',
        () async {
      await h.save(warehouse('Main Store'));
      await h.save(warehouse('Shop-1'));
      await h.save(item('CABLE-2M'));
      await h.save(item('CABLE-3M'));
      final again = (await h.engine.fetch('Item', 'CABLE-2M'))!;
      again.payload['item_name'] = 'Cable 2 m';
      await h.save(again);
      final generated = await h.save(Document(
          id: '', docType: 'Item', payload: {'item_code': 'NEW-ONE'}));
      expect(generated.id, isNotEmpty);
      await buy(h, 'CABLE-2M', 'Shop-1', 3, 4);
      expect(asNum((await h.bin('CABLE-2M', 'Shop-1'))!.payload['actual_qty']),
          3);
    });
  });
}
