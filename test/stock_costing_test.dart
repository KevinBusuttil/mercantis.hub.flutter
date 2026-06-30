import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_hub_app/ledger/stock_costing.dart';

/// H5 valuation: pure cost-of-issue calculation for both valuation methods.
void main() {
  // Two receipt layers: 10 units @ 10, then 10 units @ 20.
  List<Map<String, dynamic>> layers() => [
        {'qty_change': 10, 'valuation_rate': 10},
        {'qty_change': 10, 'valuation_rate': 20},
      ];

  group('Moving average', () {
    test('issues at the running average regardless of qty', () {
      expect(StockCosting.issueRate(layers(), 5, StockCosting.movingAverage), 15);
      expect(StockCosting.issueRate(layers(), 18, StockCosting.movingAverage), 15);
    });

    test('is the default when no method is given', () {
      expect(StockCosting.issueRate(layers(), 5, null), 15);
    });
  });

  group('FIFO', () {
    test('consumes the oldest layer first', () {
      expect(StockCosting.issueRate(layers(), 5, StockCosting.fifo), 10);
    });

    test('blends layers once the first is exhausted', () {
      // 10 @ 10 + 5 @ 20 = 200 over 15 units.
      expect(StockCosting.issueRate(layers(), 15, StockCosting.fifo),
          closeTo(200 / 15, 1e-9));
    });

    test('respects prior issues when replaying layers', () {
      final prior = [
        ...layers(),
        {'qty_change': -10, 'valuation_rate': 10}, // first layer already gone
      ];
      // Only the 20-rate layer remains.
      expect(StockCosting.issueRate(prior, 5, StockCosting.fifo), 20);
    });

    test('costs an over-issue shortfall at the moving average', () {
      final prior = [
        {'qty_change': 5, 'valuation_rate': 10},
      ];
      // 5 @ 10 = 50, then 3 short @ MA(10) = 30 → 80 / 8.
      expect(StockCosting.issueRate(prior, 8, StockCosting.fifo),
          closeTo(80 / 8, 1e-9));
    });
  });

  test('empty ledger costs at zero', () {
    expect(StockCosting.issueRate(const [], 5, StockCosting.movingAverage), 0);
    expect(StockCosting.issueRate(const [], 5, StockCosting.fifo), 0);
  });

  test('a non-positive issue qty costs nothing', () {
    expect(StockCosting.issueRate(layers(), 0, StockCosting.fifo), 0);
  });
}
