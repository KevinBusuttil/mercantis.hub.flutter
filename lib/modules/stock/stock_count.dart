import 'package:mercantis_core/mercantis_core.dart';

/// One item's count-sheet row: what the system says vs what the shelf says.
class StockCountLine {
  const StockCountLine({
    required this.item,
    required this.onHand,
    required this.counted,
    this.valuationRate = 0,
  });

  final String item;
  final num onHand;
  final num counted;

  /// The bin's current valuation rate — count-ups enter at this cost so the
  /// adjustment is valued like the stock around it. Issues are re-costed by
  /// the runtime anyway (moving average / FIFO).
  final num valuationRate;

  num get delta => counted - onHand;
}

/// Builds the draft Stock Entry for a stock count (Phase 1B A5): each
/// difference becomes an adjustment leg — count-ups receive into the
/// warehouse, count-downs issue out of it. Uses the dedicated `Stock Count`
/// purpose, which posts SLEs with trans type Adjustment; the runtime's stock
/// GL legs then post Dr Inventory / Cr Stock Adjustment (gains) or
/// Dr Stock Adjustment / Cr Inventory (losses). Zero-delta lines are skipped;
/// an all-correct count returns an entry with no rows (callers should treat
/// that as "nothing to post").
Document buildStockCountEntry({
  required String warehouse,
  required String postingDate,
  required List<StockCountLine> lines,
  String? company,
}) {
  final doc = Document(
    id: '',
    docType: 'Stock Entry',
    company: company,
    payload: {
      'stock_entry_type': 'Stock Count',
      'posting_date': postingDate,
    },
  );
  final rows = <ChildRow>[];
  for (final line in lines) {
    final delta = line.delta;
    if (delta == 0) continue;
    rows.add(ChildRow(
      id: '',
      parentId: '',
      parentDocType: 'Stock Entry',
      tableName: 'items',
      rowIndex: rows.length,
      payload: {
        'item': line.item,
        'qty': delta.abs(),
        if (delta > 0) 'target_warehouse': warehouse,
        if (delta < 0) 'source_warehouse': warehouse,
        // Gains enter at the bin's current cost; losses are re-costed by the
        // runtime at the item's valuation method.
        if (delta > 0) 'valuation_rate': line.valuationRate,
      },
    ));
  }
  doc.children['items'] = rows;
  return doc;
}
