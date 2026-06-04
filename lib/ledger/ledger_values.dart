/// Small value-coercion helpers shared across the ledger spine. Payload values
/// arrive as `dynamic` (num or String, depending on how a field was entered),
/// so every numeric/string read goes through these.
library;

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
