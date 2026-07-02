import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_hub_app/ledger/ledger_values.dart';

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
}
