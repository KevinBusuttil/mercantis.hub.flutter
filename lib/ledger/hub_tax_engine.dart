import 'ledger_values.dart';

/// Pure, database-free VAT/tax calculator (ported from the Swift `HubTaxEngine`).
///
/// It takes already-resolved line amounts plus their effective tax code and a
/// rate lookup, then produces the document's net total, one tax row per distinct
/// tax code, the total tax, and the grand total. Keeping it pure is what lets
/// Sales Invoice, Purchase Invoice (and later POS) reuse the exact same maths:
/// each caller resolves its own line/item/document/party tax defaults, then
/// hands flat numbers here.
abstract final class HubTaxEngine {
  /// `tax_type` of a withholding tax — deducted from the document total and
  /// posted to its own liability/asset account, rather than added like VAT.
  static const withholdingType = 'Withholding';

  /// One taxable line as seen by the engine: its amount and the tax code that
  /// applies (already resolved through the line → item → document → party
  /// fallback chain by the caller).
  ///
  /// With `inclusive: false` (default) line amounts are net (pre-tax) and tax
  /// is added on top. With `inclusive: true` — retail pricing — line amounts
  /// already CONTAIN the tax: each code's tax is extracted as
  /// `gross × r / (100 + r)`, the net total shrinks accordingly, and the
  /// grand total equals the entered line amounts. Withholding is always
  /// computed on the (post-extraction) taxable base and deducted, exactly as
  /// in exclusive mode.
  static TaxComputation compute(
    List<TaxLine> lines,
    Map<String, TaxRateInfo> rates, {
    bool inclusive = false,
  }) {
    var enteredTotal = 0.0;
    // Preserve first-seen order of codes for deterministic output.
    final orderedCodes = <String>[];
    final amountByCode = <String, double>{};

    for (final line in lines) {
      enteredTotal += line.netAmount;
      final codeId = line.taxCodeId;
      if (codeId == null || !rates.containsKey(codeId)) continue;
      if (!amountByCode.containsKey(codeId)) orderedCodes.add(codeId);
      amountByCode[codeId] = (amountByCode[codeId] ?? 0) + line.netAmount;
    }

    final rows = <ComputedTaxRow>[];
    var totalTax = 0.0;
    var extracted = 0.0; // inclusive: tax removed from the entered amounts
    for (final codeId in orderedCodes) {
      final info = rates[codeId];
      if (info == null) continue;
      final entered = round2(amountByCode[codeId] ?? 0);
      final isWithholding = info.taxType == withholdingType;

      final num taxable;
      final num magnitude;
      if (inclusive && !isWithholding) {
        // Entered amount is gross: extract the contained tax.
        magnitude = round2(entered * info.rate / (100.0 + info.rate));
        taxable = round2(entered - magnitude);
        extracted += magnitude;
      } else {
        taxable = entered;
        magnitude = round2(taxable * info.rate / 100.0);
      }
      // Withholding is deducted (it reduces what's owed), so its amount is
      // carried negative — that nets the grand total down and, downstream,
      // posts the ledger leg to the opposite side of VAT (a receivable on
      // sales, a payable on purchases) without any special-casing there.
      final taxAmount = isWithholding ? -magnitude : magnitude;
      totalTax += taxAmount;
      rows.add(ComputedTaxRow(
        taxCode: info.codeId,
        description: info.description,
        rate: info.rate,
        account: info.account,
        taxType: info.taxType,
        taxableAmount: taxable,
        taxAmount: taxAmount,
      ));
    }

    final net = round2(enteredTotal - extracted);
    final tax = round2(totalTax);
    return TaxComputation(
      netTotal: net,
      taxRows: rows,
      totalTax: tax,
      grandTotal: round2(net + tax),
    );
  }
}

/// Resolved information about a single tax code, built by the caller from a
/// `Tax Code` master record.
class TaxRateInfo {
  final String codeId;
  final String description;

  /// Percentage, e.g. `18` for 18% VAT. `0` for Zero / Exempt codes.
  final num rate;

  /// Posting account for the tax amount (output/input VAT account), or null.
  final String? account;

  /// "VAT", "SalesTax", … — mirrors `Tax Transaction.tax_type`.
  final String taxType;

  const TaxRateInfo({
    required this.codeId,
    required this.description,
    required this.rate,
    required this.account,
    this.taxType = 'VAT',
  });
}

/// One taxable line: its net (pre-tax) amount and the resolved tax code (or null
/// for an untaxed line, which still contributes to the net total).
class TaxLine {
  final num netAmount;
  final String? taxCodeId;

  const TaxLine(this.netAmount, this.taxCodeId);
}

/// One computed tax row, grouped by tax code. Becomes a `Tax Charge` child row
/// on the invoice and a `Tax Transaction` ledger row on submit.
class ComputedTaxRow {
  final String taxCode;
  final String description;
  final num rate;
  final String? account;
  final String taxType;
  final num taxableAmount;
  final num taxAmount;

  const ComputedTaxRow({
    required this.taxCode,
    required this.description,
    required this.rate,
    required this.account,
    required this.taxType,
    required this.taxableAmount,
    required this.taxAmount,
  });
}

/// The full result of a tax calculation for one document.
class TaxComputation {
  final num netTotal;
  final List<ComputedTaxRow> taxRows;
  final num totalTax;
  final num grandTotal;

  const TaxComputation({
    required this.netTotal,
    required this.taxRows,
    required this.totalTax,
    required this.grandTotal,
  });

  static const empty = TaxComputation(
    netTotal: 0,
    taxRows: [],
    totalTax: 0,
    grandTotal: 0,
  );
}
