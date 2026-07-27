import 'package:mercantis_core/mercantis_core.dart';

import '../../ledger/ledger_values.dart';

/// One Tax Transaction reduced to what the return needs: which side it's on
/// (a Customer party = output/sales, a Supplier party = input/purchases) and
/// its taxable base + tax amounts (reversals already carry negated amounts, so
/// summing nets cancellations).
class TaxReturnRow {
  const TaxReturnRow({
    required this.partyType,
    required this.baseAmount,
    required this.taxAmount,
    this.rate = 0,
    this.category,
  });
  final String? partyType;
  final num baseAmount;
  final num taxAmount;

  /// The tax rate (%) the row was computed at — what jurisdiction layouts
  /// split supplies by (e.g. Malta's standard-vs-reduced sections). 0 when
  /// the source didn't record it.
  final num rate;

  /// The tax code's VAT category label (Exempt / Zero-Rated / …), resolved
  /// from the Tax Code master. Exempt is the one rate can't express: two
  /// 0% codes report in DIFFERENT places on returns that separate exempt
  /// supplies (Malta). Null = classify by rate alone.
  final String? category;
}

/// One line of the computed return.
class TaxReturnBoxLine {
  const TaxReturnBoxLine(this.number, this.description, this.amount, this.isTax);
  final String number;
  final String description;
  final num amount;
  final bool isTax;
}

/// The figures a tax return resolves to.
class TaxReturnResult {
  const TaxReturnResult({
    required this.outputTax,
    required this.inputTax,
    required this.netTax,
    required this.taxableSales,
    required this.taxablePurchases,
    required this.boxes,
  });
  final num outputTax;
  final num inputTax;
  final num netTax;
  final num taxableSales;
  final num taxablePurchases;
  final List<TaxReturnBoxLine> boxes;
}

/// Pure tax-return aggregation (H2 — ported from the Swift `TaxReturnBuilder`;
/// jurisdiction layouts added in Phase 8). Folds a period's tax rows into
/// output/input tax, the net due, the taxable bases, and the numbered return
/// boxes of the chosen [jurisdiction] layout. Database-free.
///
/// Layouts:
///  * `Generic` — the 5-line summary (unchanged default).
///  * `United Kingdom` — the VAT100's nine boxes. EU/NI acquisition boxes
///    (2, 8, 9) render as 0 — Atlas doesn't track those flows yet, and a 0
///    on the form is the honest value for a business that has none.
///  * `Malta` — the CFR VAT return's flow: supplies split standard-rate
///    (18%) vs reduced/other rates, total output, input, net.
abstract final class TaxReturnBuilder {
  /// Malta's standard VAT rate — what splits the supplies sections.
  static const _maltaStandardRate = 18;

  static TaxReturnResult build(Iterable<TaxReturnRow> rows,
      {String jurisdiction = 'Generic'}) {
    num outputTax = 0, inputTax = 0, salesBase = 0, purchasesBase = 0;
    // Output split by rate, for layouts with per-rate sections (Malta).
    // Exempt supplies are tracked apart: they belong in their own section
    // on returns that separate them, never inside "reduced/other rates".
    num exemptSalesBase = 0;
    final outputTaxByRate = <num, num>{};
    final salesBaseByRate = <num, num>{};
    for (final r in rows) {
      if (r.partyType == 'Customer') {
        outputTax += r.taxAmount;
        salesBase += r.baseAmount;
        if (r.category == 'Exempt') {
          exemptSalesBase += r.baseAmount;
        } else {
          outputTaxByRate[r.rate] =
              (outputTaxByRate[r.rate] ?? 0) + r.taxAmount;
          salesBaseByRate[r.rate] =
              (salesBaseByRate[r.rate] ?? 0) + r.baseAmount;
        }
      } else if (r.partyType == 'Supplier') {
        inputTax += r.taxAmount;
        purchasesBase += r.baseAmount;
      }
    }
    outputTax = round2(outputTax);
    inputTax = round2(inputTax);
    salesBase = round2(salesBase);
    purchasesBase = round2(purchasesBase);
    final net = round2(outputTax - inputTax);

    final List<TaxReturnBoxLine> boxes;
    switch (jurisdiction) {
      case 'United Kingdom':
        boxes = [
          TaxReturnBoxLine('1', 'VAT due on sales and other outputs', outputTax, true),
          const TaxReturnBoxLine('2', 'VAT due on acquisitions of goods in NI from the EU', 0, true),
          TaxReturnBoxLine('3', 'Total VAT due (box 1 + box 2)', outputTax, true),
          TaxReturnBoxLine('4', 'VAT reclaimed on purchases and other inputs', inputTax, true),
          TaxReturnBoxLine('5', 'Net VAT to pay to HMRC or reclaim', round2((outputTax - inputTax).abs()), true),
          TaxReturnBoxLine('6', 'Total value of sales excluding VAT', salesBase, false),
          TaxReturnBoxLine('7', 'Total value of purchases excluding VAT', purchasesBase, false),
          const TaxReturnBoxLine('8', 'Total value of dispatches of goods from NI to the EU', 0, false),
          const TaxReturnBoxLine('9', 'Total value of acquisitions of goods in NI from the EU', 0, false),
        ];
      case 'Malta':
        num standardBase = 0, standardTax = 0, otherBase = 0, otherTax = 0;
        for (final entry in salesBaseByRate.entries) {
          if (entry.key == _maltaStandardRate) {
            standardBase += entry.value;
            standardTax += outputTaxByRate[entry.key] ?? 0;
          } else {
            otherBase += entry.value;
            otherTax += outputTaxByRate[entry.key] ?? 0;
          }
        }
        boxes = [
          TaxReturnBoxLine('M1', 'Supplies at the standard rate (18%) — value', round2(standardBase), false),
          TaxReturnBoxLine('M2', 'Output VAT at the standard rate (18%)', round2(standardTax), true),
          TaxReturnBoxLine('M3', 'Supplies at reduced / other rates — value', round2(otherBase), false),
          TaxReturnBoxLine('M4', 'Output VAT at reduced / other rates', round2(otherTax), true),
          // Exempt supplies (e.g. medical care) carry no output VAT and
          // report in their own section — not among the rated supplies.
          TaxReturnBoxLine('M4a', 'Exempt supplies — value', round2(exemptSalesBase), false),
          TaxReturnBoxLine('M5', 'Total output VAT', outputTax, true),
          TaxReturnBoxLine('M6', 'Purchases — value', purchasesBase, false),
          TaxReturnBoxLine('M7', 'Input VAT claimed', inputTax, true),
          TaxReturnBoxLine('M8', 'Net VAT payable (negative = refund due)', net, true),
        ];
      default:
        boxes = [
          TaxReturnBoxLine('1', 'Output tax (sales)', outputTax, true),
          TaxReturnBoxLine('2', 'Input tax (purchases)', inputTax, true),
          TaxReturnBoxLine('3', 'Net tax due', net, true),
          TaxReturnBoxLine('4', 'Taxable sales', salesBase, false),
          TaxReturnBoxLine('5', 'Taxable purchases', purchasesBase, false),
        ];
    }

    return TaxReturnResult(
      outputTax: outputTax,
      inputTax: inputTax,
      netTax: net,
      taxableSales: salesBase,
      taxablePurchases: purchasesBase,
      boxes: boxes,
    );
  }
}

/// Fills a `Tax Filing` from the `Tax Transaction`s in its period: it gathers
/// the rows of the filing's tax type whose posting date falls in the range,
/// runs [TaxReturnBuilder], and writes the headline totals + box rows back onto
/// the filing.
class TaxReturnService {
  TaxReturnService({required this.engine, this.roles = const {'System Manager'}});

  final DocumentEngine engine;
  final Set<String> roles;

  Future<Document> prepare(String filingId) async {
    final filing = await engine.fetch('Tax Filing', filingId);
    if (filing == null) {
      throw StateError('Tax Filing $filingId not found');
    }
    final from = '${filing.payload['from_date']}';
    final to = '${filing.payload['to_date']}';
    final taxType = '${filing.payload['tax_type']}';

    // Tax Transactions carry the tax code (`tax`); the code's VAT category
    // decides where a return that separates exempt supplies reports it.
    final categoryByCode = <String, String>{
      for (final c in await engine.list('Tax Code', userRoles: roles))
        if (asNonEmpty(c.payload['vat_category']) != null)
          c.id: '${c.payload['vat_category']}',
    };

    final txns = await engine.list('Tax Transaction',
        filters: {'tax_type': taxType}, userRoles: roles);
    final rows = [
      for (final t in txns)
        // Multi-company books: only this filing's company's rows count.
        if (t.company == filing.company &&
            _inRange('${t.payload['posting_date']}', from, to))
          TaxReturnRow(
            partyType: asNonEmpty(t.payload['party_type']),
            baseAmount: asNum(t.payload['base_amount']),
            taxAmount: asNum(t.payload['tax_amount']),
            rate: asNum(t.payload['rate']),
            category: categoryByCode[asNonEmpty(t.payload['tax']) ?? ''],
          ),
    ];

    final r = TaxReturnBuilder.build(rows,
        jurisdiction: asNonEmpty(filing.payload['jurisdiction']) ?? 'Generic');
    filing.payload['output_tax'] = r.outputTax;
    filing.payload['input_tax'] = r.inputTax;
    filing.payload['net_tax'] = r.netTax;
    filing.payload['taxable_sales'] = r.taxableSales;
    filing.payload['taxable_purchases'] = r.taxablePurchases;
    filing.children['boxes'] = [
      for (var i = 0; i < r.boxes.length; i++)
        ChildRow(
          id: '',
          parentId: filing.id,
          parentDocType: 'Tax Filing',
          tableName: 'boxes',
          rowIndex: i,
          payload: {
            'box_number': r.boxes[i].number,
            'description': r.boxes[i].description,
            'amount': r.boxes[i].amount,
            'is_tax': r.boxes[i].isTax ? 1 : 0,
          },
        ),
    ];
    return engine.save(filing, roles);
  }

  /// Inclusive ISO-date range check (string compare is valid for yyyy-MM-dd).
  static bool _inRange(String date, String from, String to) =>
      date.compareTo(from) >= 0 && date.compareTo(to) <= 0;
}
