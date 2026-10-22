import 'package:intl/intl.dart';

final _money = NumberFormat.currency(locale: 'en_US', symbol: '€', decimalDigits: 2);
final _whole = NumberFormat.currency(locale: 'en_US', symbol: '€', decimalDigits: 0);

/// "€10,213.60" — grouped, two decimals, sign before the symbol.
String formatMoney(num value) => _money.format(value);

/// "€10,214" — for headline figures where cents are noise.
String formatMoneyWhole(num value) => _whole.format(value);

/// Reads an amount back from a report cell ("1234.00", "1,234.00", "€1,234").
/// Null for blanks and non-numbers ("—").
num? parseAmount(String? cell) {
  if (cell == null) return null;
  final cleaned = cell.replaceAll(RegExp(r'[€,\s]'), '');
  if (cleaned.isEmpty) return null;
  return num.tryParse(cleaned);
}
