import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_hub_app/payments/pos_checkout.dart';
import 'package:mercantis_hub_app/team/team_naming.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/books_harness.dart';

/// Team series ids are device-scoped so two devices never mint the same
/// draft id; Solo ids and till receipts keep their shape.
void main() {
  sqfliteFfiInit();

  test('the tag goes before the counter', () {
    expect(teamScopedId('SINV-.2026.-0001', 'A1B2C3'), 'SINV-.2026.-A1B2C3-0001');
    expect(teamScopedId('no-counter', 'A1B2C3'), 'no-counter');
    expect(teamDeviceTag('3fa2c1d0-1111-2222-3333-444455556666'), '3FA2C1');
  });

  test('series ids carry the tag only while connected to Team', () async {
    final root = await Directory.systemTemp.createTemp('team-naming');
    String? tag;
    final h = await BooksHarness.open(p.join(root.path, 'b.db'),
        namingService: TeamScopedNamingService(() => tag));
    try {
      await h.save(Document(id: 'C', docType: 'Customer', payload: {
        'customer_name': 'C',
        'customer_type': 'Company',
      }));
      await h.save(Document(id: 'X', docType: 'Item', payload: {
        'item_code': 'X',
        'item_name': 'X',
        'item_type': 'Service',
        'stock_uom': 'Nos',
      }));
      Document quote() => Document(id: '', docType: 'Quotation', payload: {
            'customer': 'C',
            'transaction_date': isoToday(),
          });
      final solo = await h.save(quote());
      expect(solo.id, isNot(contains('A1B2C3')), reason: 'Solo unchanged');

      tag = 'A1B2C3';
      final team = await h.save(quote());
      expect(team.id, matches(RegExp(r'-A1B2C3-\d+$')));

      // A till receipt keeps its fiscal shape: the till series already
      // makes it unique per register.
      final receipt = await h.save(PosCheckout.buildPosInvoice(
        postingDate: isoToday(),
        tillSeries: 'T1',
        lines: const [PosCartLine(item: 'X', qty: 1, rate: 1)],
        tenders: const [PosTender(type: 'Cash', amount: 1)],
      ));
      expect(receipt.id, startsWith('POS-.T1.-'));
      expect(receipt.id, isNot(contains('A1B2C3')));
    } finally {
      await h.close();
      await root.delete(recursive: true);
    }
  });
}
