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
  });
  final String? partyType;
  final num baseAmount;
  final num taxAmount;
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

/// Pure tax-return aggregation (H2 — ported from the Swift `TaxReturnBuilder`).
/// Folds a period's tax rows into output/input tax, the net due, the taxable
/// bases, and the numbered return boxes. Database-free.
abstract final class TaxReturnBuilder {
  static TaxReturnResult build(Iterable<TaxReturnRow> rows) {
    num outputTax = 0, inputTax = 0, salesBase = 0, purchasesBase = 0;
    for (final r in rows) {
      if (r.partyType == 'Customer') {
        outputTax += r.taxAmount;
        salesBase += r.baseAmount;
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

    return TaxReturnResult(
      outputTax: outputTax,
      inputTax: inputTax,
      netTax: net,
      taxableSales: salesBase,
      taxablePurchases: purchasesBase,
      boxes: [
        TaxReturnBoxLine('1', 'Output tax (sales)', outputTax, true),
        TaxReturnBoxLine('2', 'Input tax (purchases)', inputTax, true),
        TaxReturnBoxLine('3', 'Net tax due', net, true),
        TaxReturnBoxLine('4', 'Taxable sales', salesBase, false),
        TaxReturnBoxLine('5', 'Taxable purchases', purchasesBase, false),
      ],
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
          ),
    ];

    final r = TaxReturnBuilder.build(rows);
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
