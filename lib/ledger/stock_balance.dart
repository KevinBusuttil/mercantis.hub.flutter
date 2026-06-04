import 'ledger_values.dart';

/// The recomputed running balance for one (item, warehouse) pair.
class BinSnapshot {
  final double actualQty;
  final double valuationRate;
  final double stockValue;

  /// Raw posting-date value of the latest movement (epoch int or ISO string,
  /// preserved as stored), or null if there were no rows.
  final dynamic lastMovementDate;

  const BinSnapshot({
    required this.actualQty,
    required this.valuationRate,
    required this.stockValue,
    required this.lastMovementDate,
  });
}

/// Pure stock-balance fold, ported from the Swift `StockBalanceCalculator`.
/// Reads the FULL set of stock-ledger rows for an (item, warehouse) pair —
/// including `is_reversal` rows, whose negated `qty_change` nets naturally —
/// and produces the Bin snapshot. No database access.
abstract final class StockBalance {
  static BinSnapshot compute(List<Map<String, dynamic>> sleRows) {
    num qty = 0;
    num value = 0;
    dynamic latestRaw;
    DateTime? latestDate;

    for (final row in sleRows) {
      final q = asNum(row['qty_change']);
      final rate = asNum(row['valuation_rate']);
      qty += q;
      value += q * rate;

      final raw = row['posting_date'];
      final d = _toDate(raw);
      if (d != null && (latestDate == null || d.isAfter(latestDate))) {
        latestDate = d;
        latestRaw = raw;
      }
    }

    final actualQty = round3(qty);
    final stockValue = round2(value);
    final valuationRate = actualQty != 0 ? round2(stockValue / actualQty) : 0.0;

    return BinSnapshot(
      actualQty: actualQty,
      valuationRate: valuationRate,
      stockValue: stockValue,
      lastMovementDate: latestRaw,
    );
  }

  static DateTime? _toDate(dynamic value) {
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}
