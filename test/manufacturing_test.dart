import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_hub_app/ledger/ledger_derivation.dart';
import 'package:mercantis_hub_app/manufacturing/manufacturing.dart';

/// Pure tests for the manufacturing helpers: BOM explosion + rollup, and the
/// completion Stock Entry (which posts via the existing Stock Entry derivation).
void main() {
  Document doc(
    String docType, {
    String id = 'X',
    Map<String, dynamic> payload = const {},
    Map<String, List<Map<String, dynamic>>> children = const {},
  }) {
    final d = Document(id: id, docType: docType, payload: Map.of(payload));
    children.forEach((table, rows) {
      d.children[table] = [
        for (var i = 0; i < rows.length; i++)
          ChildRow(id: '$table-$i', parentId: id, parentDocType: docType, tableName: table, rowIndex: i, payload: Map.of(rows[i])),
      ];
    });
    return d;
  }

  Document bom() => doc('BOM', id: 'BOM-1', payload: {'item': 'WIDGET', 'qty': 10}, children: {
        'items': [
          {'item': 'STEEL', 'qty': 2, 'rate': 5}, // 2 per 10 → 0.2/unit
          {'item': 'BOLT', 'qty': 20, 'rate': 0.5},
        ],
        'operations': [
          {'operation': 'CUT', 'time_minutes': 30, 'hour_rate': 60}, // 0.5h * 60 = 30
        ],
      });

  group('requiredItemsFromBom', () {
    test('scales components by qtyToProduce / bom.qty', () {
      final req = Manufacturing.requiredItemsFromBom(bom(), 50); // scale 5
      expect(req.length, 2);
      expect(req[0]['item'], 'STEEL');
      expect(req[0]['required_qty'], 10); // 2 * 5
      expect(req[1]['required_qty'], 100); // 20 * 5
    });

    test('fractional production scales down', () {
      final req = Manufacturing.requiredItemsFromBom(bom(), 5); // scale 0.5
      expect(req[0]['required_qty'], 1); // 2 * 0.5
      expect(req[1]['required_qty'], 10); // 20 * 0.5
    });
  });

  group('bomRollup', () {
    test('sums raw-material and operating costs', () {
      final r = Manufacturing.bomRollup(bom());
      // raw: 2*5 + 20*0.5 = 10 + 10 = 20 ; op: (30/60)*60 = 30
      expect(r.rawMaterialCost, 20);
      expect(r.operatingCost, 30);
      expect(r.totalCost, 50);
    });
  });

  group('completionStockEntry', () {
    Document workOrder() => doc('Work Order', id: 'WO-1', payload: {
          'item': 'WIDGET',
          'qty_to_produce': 50,
          'source_warehouse': 'RAW',
          'target_warehouse': 'FG',
        }, children: {
          'required_items': [
            {'item': 'STEEL', 'required_qty': 10},
            {'item': 'BOLT', 'required_qty': 100},
          ],
        });

    test('consumes raw from source and produces finished into target', () {
      final se = Manufacturing.completionStockEntry(workOrder());
      expect(se.id, 'SE-WO-1-completion');
      expect(se.payload['stock_entry_type'], 'Manufacturing');

      final rows = se.children['items']!;
      expect(rows.length, 3); // 2 raw + 1 finished
      expect(rows[0].payload, {'item': 'STEEL', 'qty': 10, 'source_warehouse': 'RAW'});
      expect(rows[2].payload, {'item': 'WIDGET', 'qty': 50, 'target_warehouse': 'FG'});
    });

    test('posts correct stock ledger entries via the Stock Entry derivation', () {
      final se = Manufacturing.completionStockEntry(workOrder());
      final sle = LedgerDerivation.derive(se, reversal: false);

      // Raw materials leave RAW (negative); finished good enters FG (positive).
      final steel = sle.firstWhere((r) => r.payload['item'] == 'STEEL');
      expect(steel.payload['warehouse'], 'RAW');
      expect(steel.payload['qty_change'], -10);
      expect(steel.payload['trans_type'], 'Production');

      final widget = sle.firstWhere((r) => r.payload['item'] == 'WIDGET');
      expect(widget.payload['warehouse'], 'FG');
      expect(widget.payload['qty_change'], 50);

      // Reversal returns everything.
      final rev = LedgerDerivation.derive(se, reversal: true);
      final steelRev = rev.firstWhere((r) => r.payload['item'] == 'STEEL');
      expect(steelRev.payload['qty_change'], 10);
    });
  });
}
