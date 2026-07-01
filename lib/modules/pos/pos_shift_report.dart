import 'package:mercantis_core/mercantis_core.dart';

import '../../ledger/ledger_values.dart';

/// One tender line on a POS sale (its type and amount; refunds are negative).
class PosTender {
  const PosTender(this.type, this.amount);
  final String type; // Cash / Card / Other
  final num amount;
}

/// One POS sale as the shift report sees it. A refund is a sale with a negative
/// grand total / quantities / tenders (an is_return POS Invoice).
class PosSale {
  const PosSale({
    required this.grandTotal,
    required this.taxTotal,
    required this.qty,
    required this.tenders,
  });
  final num grandTotal;
  final num taxTotal;
  final num qty;
  final List<PosTender> tenders;
}

/// The figures of an X-report (mid-shift snapshot) or Z-report (shift close).
class PosShiftReport {
  const PosShiftReport({
    required this.transactions,
    required this.grossSales,
    required this.refunds,
    required this.netSales,
    required this.itemsSold,
    required this.taxCollected,
    required this.tenderTotals,
    required this.openingFloat,
    required this.expectedCash,
    required this.isZReport,
    this.countedCash,
    this.overShort,
  });

  final int transactions;
  final num grossSales; // positive sales
  final num refunds; // absolute value of negative sales
  final num netSales; // gross − refunds
  final num itemsSold; // net quantity
  final num taxCollected;
  final Map<String, num> tenderTotals; // by tender type
  final num openingFloat;
  final num expectedCash; // float + net cash tenders

  /// Z-report only: the cash counted in the drawer and the variance
  /// (counted − expected). Null on an X-report.
  final num? countedCash;
  final num? overShort;

  final bool isZReport;
}

/// Pure POS shift-report aggregation (H8 — ported from the Swift
/// `POSShiftReportBuilder`). Folds a shift's sales into the X/Z figures; passing
/// [countedCash] makes it a Z-report and computes the cash over/short.
abstract final class PosShiftReportBuilder {
  static const cashTender = 'Cash';

  static PosShiftReport build(
    Iterable<PosSale> sales, {
    required num openingFloat,
    num? countedCash,
  }) {
    var transactions = 0;
    num gross = 0, refunds = 0, items = 0, tax = 0;
    final tenders = <String, num>{};
    for (final s in sales) {
      transactions++;
      if (s.grandTotal >= 0) {
        gross += s.grandTotal;
      } else {
        refunds += -s.grandTotal;
      }
      items += s.qty;
      tax += s.taxTotal;
      for (final t in s.tenders) {
        tenders[t.type] = round2((tenders[t.type] ?? 0) + t.amount);
      }
    }
    gross = round2(gross);
    refunds = round2(refunds);
    tax = round2(tax);
    final net = round2(gross - refunds);
    final expectedCash = round2(openingFloat + (tenders[cashTender] ?? 0));

    return PosShiftReport(
      transactions: transactions,
      grossSales: gross,
      refunds: refunds,
      netSales: net,
      itemsSold: round2(items),
      taxCollected: tax,
      tenderTotals: tenders,
      openingFloat: round2(openingFloat),
      expectedCash: expectedCash,
      isZReport: countedCash != null,
      countedCash: countedCash == null ? null : round2(countedCash),
      overShort: countedCash == null ? null : round2(countedCash - expectedCash),
    );
  }
}

/// Builds shift reports off the engine and closes a shift.
class PosShiftReportService {
  PosShiftReportService({required this.engine, this.roles = const {'System Manager'}});

  final DocumentEngine engine;
  final Set<String> roles;

  /// The X/Z report for [sessionId] over its submitted POS Invoices. Supplying
  /// [countedCash] produces a Z-report (with the cash variance).
  Future<PosShiftReport> report(String sessionId, {num? countedCash}) async {
    final session = await engine.fetch('POS Session', sessionId);
    final openingFloat = asNum(session?.payload['opening_amount']);
    final sales = await _sales(sessionId);
    return PosShiftReportBuilder.build(sales,
        openingFloat: openingFloat, countedCash: countedCash);
  }

  /// Closes the shift: writes the Z-report totals + counted cash onto the
  /// session and marks it Closed. Returns the saved session.
  Future<Document> closeShift(String sessionId,
      {required num countedCash, String? closingDate}) async {
    final session = await engine.fetch('POS Session', sessionId);
    if (session == null) throw StateError('POS Session $sessionId not found');
    final z = PosShiftReportBuilder.build(
      await _sales(sessionId),
      openingFloat: asNum(session.payload['opening_amount']),
      countedCash: countedCash,
    );
    session.payload['status'] = 'Closed';
    session.payload['closing_amount'] = z.countedCash;
    session.payload['total_sales'] = z.netSales;
    session.payload['total_qty'] = z.itemsSold;
    if (closingDate != null) session.payload['closing_date'] = closingDate;
    await engine.save(session, roles);
    return session;
  }

  /// The submitted POS Invoices of [sessionId], each reduced to a [PosSale]
  /// (fetched individually so the tender/item child tables hydrate).
  Future<List<PosSale>> _sales(String sessionId) async {
    final listed = await engine.list('POS Invoice',
        filters: {'pos_session': sessionId}, userRoles: roles);
    final sales = <PosSale>[];
    for (final row in listed) {
      if (row.docStatus != 1) continue;
      final inv = await engine.fetch('POS Invoice', row.id) ?? row;
      num qty = 0;
      for (final item in inv.children['items'] ?? const <ChildRow>[]) {
        qty += asNum(item.payload['qty']);
      }
      final tenders = [
        for (final t in inv.children['tenders'] ?? const <ChildRow>[])
          PosTender(
              asNonEmpty(t.payload['tender_type']) ?? PosShiftReportBuilder.cashTender,
              asNum(t.payload['amount'])),
      ];
      sales.add(PosSale(
        grandTotal: asNum(inv.payload['grand_total']),
        taxTotal: asNum(inv.payload['tax_total']),
        qty: qty,
        tenders: tenders,
      ));
    }
    return sales;
  }
}
