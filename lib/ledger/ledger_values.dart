/// Small value-coercion helpers shared across the ledger spine. Payload values
/// arrive as `dynamic` (num or String, depending on how a field was entered),
/// so every numeric/string read goes through these.
library;

import 'package:mercantis_core/mercantis_core.dart';

/// Coerces a payload value to a number; returns 0 for null/garbage so ledger
/// math never throws on a missing field.
num asNum(dynamic value) {
  if (value is num) return value;
  if (value is String) return num.tryParse(value) ?? 0;
  return 0;
}

/// Returns a trimmed non-empty string, or null. Used to decide whether an
/// optional link/party/warehouse field is actually set.
String? asNonEmpty(dynamic value) {
  if (value is! String) return null;
  final t = value.trim();
  return t.isEmpty ? null : t;
}

/// Truthiness for a payload flag stored as a bool, int, or string ("1").
bool isTrue(dynamic v) => v == true || v == 1 || v == '1';

/// Whether an item participates in inventory, read from its payload. Defaults
/// to true (a stock item) when `is_stock_item` is unset — matching the Item
/// DocType default — and a service item never does. The negative-stock guard
/// and the stock-ledger derivation both consult this so they agree on which
/// lines move inventory (a non-stock line must be skipped end-to-end, or it
/// would submit fine yet still spawn a phantom Stock Ledger Entry / Bin).
bool isStockItem(Map<String, dynamic> payload) {
  if (isTrue(payload['is_service_item'])) return false;
  final v = payload['is_stock_item'];
  return v == null ? true : isTrue(v);
}

/// The transaction→stock UOM conversion factor for [item] — 1.0 when the line
/// [lineUom] is the item's stock UOM (or unknown/missing). Reads `Item.uoms`
/// (UOM Conversion Detail) for a matching row with a positive
/// `conversion_factor`. Both the negative-stock guard and the stock-ledger
/// costing convert line quantities to stock units through this, so they agree
/// on how much inventory a line really moves.
num uomFactor(Document? item, String? lineUom) {
  if (item == null || lineUom == null) return 1;
  final stockUom = asNonEmpty(item.payload['stock_uom']);
  if (stockUom == null || stockUom == lineUom) return 1;
  for (final row in item.children['uoms'] ?? const <ChildRow>[]) {
    if (asNonEmpty(row.payload['uom']) == lineUom) {
      final f = asNum(row.payload['conversion_factor']);
      if (f > 0) return f;
    }
  }
  return 1;
}

/// Negates [value] when [when] is true; otherwise returns it unchanged.
/// This is the single primitive behind every sign flip in the ledger
/// (reversal-on-cancel, outbound vs inbound stock legs, payment reductions).
num negate(num value, bool when) => when ? -value : value;

/// `-reversal` id suffix used to keep reversal rows distinct from — and
/// deterministically paired with — their originals.
String reversalSuffix(bool reversal) => reversal ? '-reversal' : '';

/// Banker-free rounding matching the Swift `round2`/`round3` (half away from
/// zero) used by the stock balance calculator.
double round2(num v) => (v * 100).round() / 100;
double round3(num v) => (v * 1000).round() / 1000;

/// An invoice's outstanding balance: its grand total less everything settled
/// against it. Settlement allocations are already signed (reversals carry a
/// negative `allocated_amount`), so a plain sum nets cancellations correctly —
/// making this idempotent no matter how many times derivation re-fires.
num outstandingAmount(num grandTotal, Iterable<num> settledAllocations) =>
    grandTotal - settledAllocations.fold<num>(0, (sum, a) => sum + a);
