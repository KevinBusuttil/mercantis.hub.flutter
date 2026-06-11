/// Heuristic receipt/invoice parser (ADR-049). Turns the raw text a recogniser
/// pulls off a photo into the handful of fields a reviewer confirms before a
/// draft voucher is created. Deliberately rule-based and local — no AI, no
/// service calls — and intentionally forgiving: anything it can't find is left
/// null for the human to fill, and `confidence` reflects how much it pinned
/// down so the UI can route a weak read to "Needs Review".
library;

/// The structured fields lifted from a receipt's text. All optional — the
/// parser never invents data.
class ParsedReceipt {
  const ParsedReceipt({
    this.merchantName,
    this.documentDate,
    this.invoiceNo,
    this.netTotal,
    this.vatTotal,
    this.grandTotal,
    this.currencyCode,
    this.confidence = 0,
  });

  final String? merchantName;

  /// ISO-8601 `yyyy-MM-dd`, or null if no date was recognised.
  final String? documentDate;
  final String? invoiceNo;
  final double? netTotal;
  final double? vatTotal;
  final double? grandTotal;

  /// ISO currency code (EUR/USD/GBP) inferred from a symbol or code, if any.
  final String? currencyCode;

  /// 0..1 — how confident the parse is. Drives Ready vs Needs Review.
  final double confidence;

  bool get isEmpty =>
      merchantName == null &&
      documentDate == null &&
      invoiceNo == null &&
      grandTotal == null;
}

abstract final class ReceiptParser {
  // A monetary token: digits with thousands groupings ending in a 2-digit
  // decimal part. Requiring the decimals keeps VAT/registration numbers,
  // percentages, quantities and dates from being mistaken for amounts.
  static final _amountToken = RegExp(r'\d[\d.,]*[.,]\d{2}(?![\d.,])');
  static final _vatKeyword = RegExp(r'\b(vat|tax|iva|mwst|tva|btw)\b');
  static final _netKeyword = RegExp(r'\b(sub[- ]?total|net|nett)\b');
  static final _grandKeyword = RegExp(
      r'\b(grand[- ]?total|total|amount due|balance due|to pay|total due)\b');

  /// Parse [text] (newline-separated OCR output). Always returns a result;
  /// fields that couldn't be found are null.
  static ParsedReceipt parse(String text) {
    final rawLines = text
        .split(RegExp(r'[\r\n]+'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    if (rawLines.isEmpty) return const ParsedReceipt();

    final merchant = _merchant(rawLines);
    final date = _date(text);
    final invoiceNo = _invoiceNo(rawLines);
    final currency = _currency(text);

    double? net;
    double? vat;
    double? grand;
    final allAmounts = <double>[];

    for (final line in rawLines) {
      final lower = line.toLowerCase();
      final amount = _lastAmountIn(line);
      if (amount != null) allAmounts.add(amount);
      // Order matters: sub-total/net before the broad "total" match.
      if (_netKeyword.hasMatch(lower)) {
        net ??= amount;
      } else if (_vatKeyword.hasMatch(lower)) {
        vat ??= amount;
      } else if (_grandKeyword.hasMatch(lower)) {
        // Keep the largest labelled total — "grand total" usually exceeds a
        // bare "total" line on the same receipt.
        if (amount != null && (grand == null || amount > grand)) grand = amount;
      }
    }

    var totalWasLabelled = grand != null;
    // Fallback: no labelled total — the largest amount on a receipt is almost
    // always the total.
    if (grand == null && allAmounts.isNotEmpty) {
      grand = allAmounts.reduce((a, b) => a > b ? a : b);
    }
    // Derive a missing VAT when net + grand are both known.
    if (vat == null && net != null && grand != null && grand > net) {
      vat = double.parse((grand - net).toStringAsFixed(2));
    }

    return ParsedReceipt(
      merchantName: merchant,
      documentDate: date,
      invoiceNo: invoiceNo,
      netTotal: net,
      vatTotal: vat,
      grandTotal: grand,
      currencyCode: currency,
      confidence: _confidence(
        merchant: merchant,
        date: date,
        invoiceNo: invoiceNo,
        vat: vat,
        grand: grand,
        totalWasLabelled: totalWasLabelled,
      ),
    );
  }

  // — field extractors —

  static String? _merchant(List<String> lines) {
    // The merchant is usually the top line — take the first line with real
    // letters that isn't itself a date or a pure amount.
    for (final line in lines.take(4)) {
      final letters = line.replaceAll(RegExp(r'[^A-Za-z]'), '');
      if (letters.length < 3) continue;
      if (_date(line) != null) continue;
      return line;
    }
    return null;
  }

  static String? _date(String text) {
    // dd/mm/yyyy, dd-mm-yyyy, dd.mm.yyyy (and yy), plus yyyy-mm-dd.
    final numeric = RegExp(
        r'\b(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})\b|\b(\d{1,2})[-/.](\d{1,2})[-/.](\d{2,4})\b');
    final m = numeric.firstMatch(text);
    if (m != null) {
      if (m.group(1) != null) {
        return _iso(int.parse(m.group(1)!), int.parse(m.group(2)!),
            int.parse(m.group(3)!));
      }
      var y = int.parse(m.group(6)!);
      if (y < 100) y += 2000;
      return _iso(y, int.parse(m.group(5)!), int.parse(m.group(4)!));
    }
    // dd Mon yyyy / Mon dd, yyyy
    const months = {
      'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
      'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
    };
    final named = RegExp(
        r'\b(\d{1,2})\s+([A-Za-z]{3,})\.?\s+(\d{4})\b|\b([A-Za-z]{3,})\.?\s+(\d{1,2}),?\s+(\d{4})\b');
    final nm = named.firstMatch(text);
    if (nm != null) {
      if (nm.group(1) != null) {
        final mon = months[nm.group(2)!.substring(0, 3).toLowerCase()];
        if (mon != null) {
          return _iso(int.parse(nm.group(3)!), mon, int.parse(nm.group(1)!));
        }
      } else {
        final mon = months[nm.group(4)!.substring(0, 3).toLowerCase()];
        if (mon != null) {
          return _iso(int.parse(nm.group(6)!), mon, int.parse(nm.group(5)!));
        }
      }
    }
    return null;
  }

  static String? _iso(int y, int m, int d) {
    if (m < 1 || m > 12 || d < 1 || d > 31) return null;
    final mm = m.toString().padLeft(2, '0');
    final dd = d.toString().padLeft(2, '0');
    return '$y-$mm-$dd';
  }

  static String? _invoiceNo(List<String> lines) {
    final re = RegExp(
        r'\b(?:invoice|receipt|fattura|bill|doc(?:ument)?|ref)\s*(?:no\.?|number|#|:)?\s*[:#]?\s*([A-Za-z0-9][A-Za-z0-9\-/]{2,})',
        caseSensitive: false);
    for (final line in lines) {
      final m = re.firstMatch(line);
      if (m != null) {
        final token = m.group(1)!;
        // Avoid catching a date or a money value as the number.
        if (RegExp(r'^\d{1,2}[-/.]\d').hasMatch(token)) continue;
        return token;
      }
    }
    return null;
  }

  static String? _currency(String text) {
    if (text.contains('€') || RegExp(r'\bEUR\b').hasMatch(text)) return 'EUR';
    if (text.contains('£') || RegExp(r'\bGBP\b').hasMatch(text)) return 'GBP';
    if (text.contains(r'$') || RegExp(r'\b(USD|US\$)\b').hasMatch(text)) {
      return 'USD';
    }
    return null;
  }

  /// The last monetary value on a line — the amount column sits on the right.
  static double? _lastAmountIn(String line) {
    double? last;
    for (final m in _amountToken.allMatches(line)) {
      final v = _money(m.group(0)!);
      // Require a decimal part or a $/€/£ nearby to avoid catching quantities.
      if (v != null) last = v;
    }
    return last;
  }

  /// Normalise a numeric token across EU ("1.234,56") and US ("1,234.56")
  /// groupings into a double.
  static double? _money(String token) {
    var t = token.trim();
    if (t.isEmpty) return null;
    final lastComma = t.lastIndexOf(',');
    final lastDot = t.lastIndexOf('.');
    String norm;
    if (lastComma >= 0 && lastDot >= 0) {
      norm = lastComma > lastDot
          ? t.replaceAll('.', '').replaceAll(',', '.') // comma is decimal
          : t.replaceAll(',', ''); // dot is decimal
    } else if (lastComma >= 0) {
      final decimals = t.length - lastComma - 1;
      norm = decimals == 2 ? t.replaceAll(',', '.') : t.replaceAll(',', '');
    } else if (lastDot >= 0 && '.'.allMatches(t).length > 1) {
      // Multiple dots ⇒ thousands separators; keep only the last as decimal.
      norm = t.substring(0, lastDot).replaceAll('.', '') + t.substring(lastDot);
    } else {
      norm = t;
    }
    return double.tryParse(norm);
  }

  static double _confidence({
    required String? merchant,
    required String? date,
    required String? invoiceNo,
    required double? vat,
    required double? grand,
    required bool totalWasLabelled,
  }) {
    var c = 0.0;
    if (grand != null) c += totalWasLabelled ? 0.45 : 0.2;
    if (date != null) c += 0.2;
    if (merchant != null) c += 0.15;
    if (vat != null) c += 0.12;
    if (invoiceNo != null) c += 0.08;
    return c > 1.0 ? 1.0 : c;
  }
}
