import 'ledger_values.dart';
import 'stock_balance.dart';

/// Pure cost-of-issue calculation for stock leaving a warehouse (H5).
///
/// The pure [LedgerDerivation] can't cost an issue — the cost depends on the
/// item's on-hand history — so the runtime service feeds the prior ledger rows
/// for an (item, warehouse) here and stamps the result onto the outgoing Stock
/// Ledger Entry. Getting this right keeps the Bin's running stock value sane:
/// an issue must remove inventory at *cost*, never at the selling price.
abstract final class StockCosting {
  static const movingAverage = 'Moving Average';
  static const fifo = 'FIFO';

  /// The cost per stock unit to issue [qty] units, given the chronological
  /// [prior] ledger rows for the (item, warehouse) and the item's [method]
  /// (defaults to moving average). For FIFO, any shortfall beyond the available
  /// receipt layers (i.e. issuing into negative stock) is costed at the
  /// moving-average rate so the issue is never valued at zero.
  static num issueRate(
      List<Map<String, dynamic>> prior, num qty, String? method) {
    if (qty <= 0) return 0;
    if (method == fifo) return _fifoRate(prior, qty);
    return StockBalance.compute(prior).valuationRate;
  }

  /// Weighted-average unit cost of the [qty] units FIFO would consume next,
  /// after replaying [prior] into its remaining receipt layers.
  static num _fifoRate(List<Map<String, dynamic>> prior, num qty) {
    final layers = _remainingLayers(prior);
    num need = qty;
    num cost = 0;
    num taken = 0;
    var i = 0;
    while (need > 0 && i < layers.length) {
      final layer = layers[i];
      final take = layer.qty <= need ? layer.qty : need;
      cost += take * layer.rate;
      taken += take;
      need -= take;
      if (layer.qty <= take) {
        i++;
      } else {
        layer.qty -= take;
      }
    }
    if (need > 0) {
      // Issuing more than is on hand: cost the shortfall at the moving average
      // (or 0 when there is no history) rather than leaving it free.
      final fallback = StockBalance.compute(prior).valuationRate;
      cost += need * fallback;
      taken += need;
    }
    return taken > 0 ? cost / taken : 0;
  }

  /// Folds [prior] into the FIFO layers still on hand, oldest first. Receipts
  /// (positive `qty_change`) push a layer at their valuation rate; issues
  /// (negative) consume from the oldest layers.
  static List<_Layer> _remainingLayers(List<Map<String, dynamic>> prior) {
    final layers = <_Layer>[];
    for (final row in prior) {
      final q = asNum(row['qty_change']);
      if (q > 0) {
        layers.add(_Layer(q, asNum(row['valuation_rate'])));
      } else if (q < 0) {
        num consume = -q;
        while (consume > 0 && layers.isNotEmpty) {
          final layer = layers.first;
          if (layer.qty <= consume) {
            consume -= layer.qty;
            layers.removeAt(0);
          } else {
            layer.qty -= consume;
            consume = 0;
          }
        }
      }
    }
    return layers;
  }
}

class _Layer {
  num qty;
  final num rate;
  _Layer(this.qty, this.rate);
}
