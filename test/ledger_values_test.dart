import 'package:flutter_test/flutter_test.dart';
// Import only isStockItem: ledger_values also exports an `isTrue` helper that
// would collide with flutter_test's `isTrue` matcher.
import 'package:mercantis_hub_app/ledger/ledger_values.dart'
    show isStockItem, outstandingAmount;

/// `isStockItem` now reads the single `item_type` select that replaced the
/// is_stock_item / is_service_item checkbox pair, while still honouring the
/// legacy flags on records created before the field existed.
void main() {
  group('isStockItem', () {
    test('item_type Stock moves inventory; Service does not', () {
      expect(isStockItem({'item_type': 'Stock'}), isTrue);
      expect(isStockItem({'item_type': 'Service'}), isFalse);
      expect(isStockItem({'item_type': 'service'}), isFalse, reason: 'case-insensitive');
    });

    test('defaults to a stock item when nothing is set', () {
      expect(isStockItem({}), isTrue);
    });

    test('item_type takes precedence over the legacy flags', () {
      expect(isStockItem({'item_type': 'Stock', 'is_service_item': 1}), isTrue);
      expect(isStockItem({'item_type': 'Service', 'is_stock_item': 1}), isFalse);
    });

    test('falls back to legacy flags for pre-item_type records', () {
      expect(isStockItem({'is_service_item': 1}), isFalse);
      expect(isStockItem({'is_stock_item': 0}), isFalse);
      expect(isStockItem({'is_stock_item': 1}), isTrue);
    });
  });

  group('outstandingAmount', () {
    test('is exact to the cent after part payments', () {
      expect(outstandingAmount(141.60, [100]), 41.60);
      expect(outstandingAmount(141.60, [100, 41.60]), 0);
      expect(outstandingAmount(0.3, [0.1, 0.2]), 0);
      expect(outstandingAmount(100, [30, -30]), 100);
    });
  });
}
