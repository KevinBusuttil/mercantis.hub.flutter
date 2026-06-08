import 'package:mercantis_core/mercantis_core.dart';

import '../ledger/ledger_values.dart';

/// Pure manufacturing helpers (ported from the Swift `ManufacturingDerivation`).
/// Manufacturing is stock-only: the BOM explodes into a Work Order's required
/// items, and a completed Work Order yields a Manufacturing Stock Entry that
/// consumes raw materials and produces the finished good — posted by the
/// existing Stock Entry derivation (`Manufacturing` → `Production`).
abstract final class Manufacturing {
  /// Explodes a [bom] for [qtyToProduce] into Work Order required-item payloads.
  /// Each component's required qty = `component.qty * (qtyToProduce / bom.qty)`.
  static List<Map<String, dynamic>> requiredItemsFromBom(Document bom, num qtyToProduce) {
    final batch = asNum(bom.payload['qty']);
    final base = batch <= 0 ? 1 : batch;
    final scale = (qtyToProduce == 0 ? 1 : qtyToProduce) / base;
    final items = bom.children['items'] ?? const [];
    return [
      for (final r in items)
        if (asNonEmpty(r.payload['item']) != null)
          {
            'item': r.payload['item'],
            'required_qty': round3(asNum(r.payload['qty']) * scale),
            'transferred_qty': 0,
            'consumed_qty': 0,
          },
    ];
  }

  /// BOM cost rollup: raw-material cost (Σ qty×rate), operating cost
  /// (Σ time/60 × hour_rate), and their total.
  static ({num rawMaterialCost, num operatingCost, num totalCost}) bomRollup(Document bom) {
    num raw = 0;
    for (final r in bom.children['items'] ?? const []) {
      raw += asNum(r.payload['qty']) * asNum(r.payload['rate']);
    }
    num op = 0;
    for (final r in bom.children['operations'] ?? const []) {
      op += (asNum(r.payload['time_minutes']) / 60) * asNum(r.payload['hour_rate']);
    }
    return (rawMaterialCost: round2(raw), operatingCost: round2(op), totalCost: round2(raw + op));
  }

  /// Builds the Manufacturing Stock Entry for a completed Work Order [wo]:
  /// one outbound (source-warehouse) row per required item, plus one inbound
  /// (target-warehouse) row for the produced item. Deterministic id
  /// `SE-<workOrderId>-completion`; submitting it posts the stock moves.
  static Document completionStockEntry(Document wo, {num? producedQty, String? postingDate}) {
    final id = wo.id;
    final source = asNonEmpty(wo.payload['source_warehouse']);
    final target = asNonEmpty(wo.payload['target_warehouse']);
    final fromWo = asNum(wo.payload['produced_qty']);
    final produced = producedQty ?? (fromWo > 0 ? fromWo : asNum(wo.payload['qty_to_produce']));

    final se = Document(
      id: 'SE-$id-completion',
      docType: 'Stock Entry',
      company: wo.company,
      payload: {
        'stock_entry_type': 'Manufacturing',
        'posting_date': postingDate ?? _todayIso(),
      },
    );

    final rows = <ChildRow>[];
    var i = 0;
    for (final r in wo.children['required_items'] ?? const []) {
      final item = asNonEmpty(r.payload['item']);
      if (item == null) continue;
      rows.add(_row(i++, {
        'item': item,
        'qty': asNum(r.payload['required_qty']),
        if (source != null) 'source_warehouse': source,
      }));
    }
    rows.add(_row(i++, {
      'item': wo.payload['item'],
      'qty': produced,
      if (target != null) 'target_warehouse': target,
    }));
    se.children['items'] = rows;
    return se;
  }

  static ChildRow _row(int index, Map<String, dynamic> payload) => ChildRow(
        id: '',
        parentId: '',
        parentDocType: 'Stock Entry',
        tableName: 'items',
        rowIndex: index,
        payload: payload,
      );

  static String _todayIso() => DateTime.now().toIso8601String().split('T').first;
}
