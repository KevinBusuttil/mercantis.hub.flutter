import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

import '../ledger/ledger_values.dart';

/// Real data sources for the Hub's bespoke custom screens, replacing the old
/// `MockData` prototypes. Each provider reads the live document store via
/// `DocumentEngine.list`.

// ─── Low stock ───────────────────────────────────────────────────────────────

/// One Item/Warehouse below its configured reorder level.
class LowStockRow {
  const LowStockRow({
    required this.itemCode,
    required this.itemName,
    required this.warehouse,
    required this.uom,
    required this.qty,
    required this.reorderLevel,
  });

  final String itemCode;
  final String itemName;
  final String warehouse;
  final String uom;
  final double qty;
  final double reorderLevel;
}

/// Bins whose on-hand qty is below the item's `reorder_level` (items with no
/// reorder level configured are ignored), neediest first.
final lowStockProvider = FutureProvider<List<LowStockRow>>((ref) async {
  final engine = await ref.watch(documentEngineProvider.future);
  final items = await engine.list('Item');
  final bins = await engine.list('Bin');

  final byItem = {for (final it in items) it.id: it};

  final rows = <LowStockRow>[];
  for (final bin in bins) {
    final itemId = asNonEmpty(bin.payload['item']);
    final item = itemId == null ? null : byItem[itemId];
    if (item == null) continue;
    final reorder = asNum(item.payload['reorder_level']).toDouble();
    if (reorder <= 0) continue;
    final qty = asNum(bin.payload['actual_qty']).toDouble();
    if (qty >= reorder) continue;
    rows.add(LowStockRow(
      itemCode: asNonEmpty(item.payload['item_code']) ?? item.id,
      itemName: asNonEmpty(item.payload['item_name']) ?? '',
      warehouse: asNonEmpty(bin.payload['warehouse']) ?? '',
      uom: asNonEmpty(item.payload['stock_uom']) ?? '',
      qty: qty,
      reorderLevel: reorder,
    ));
  }
  rows.sort((a, b) => a.qty.compareTo(b.qty));
  return rows;
});

// ─── Customer accounts ───────────────────────────────────────────────────────

/// A customer plus their open receivable balance.
class CustomerAccountRow {
  const CustomerAccountRow({
    required this.customerId,
    required this.customerName,
    required this.outstanding,
    required this.openInvoices,
  });

  final String customerId;
  final String customerName;
  final double outstanding;
  final int openInvoices;
}

/// Every customer with their total outstanding (summed from submitted Sales
/// Invoices' `outstanding_amount`), largest balance first.
final customerAccountsProvider =
    FutureProvider<List<CustomerAccountRow>>((ref) async {
  final engine = await ref.watch(documentEngineProvider.future);
  final customers = await engine.list('Customer');
  final invoices = await engine.list('Sales Invoice');

  final outstandingByCust = <String, double>{};
  final openByCust = <String, int>{};
  for (final inv in invoices) {
    if (inv.docStatus != 1) continue; // submitted only
    final cust = asNonEmpty(inv.payload['customer']);
    if (cust == null) continue;
    final out = asNum(inv.payload['outstanding_amount']).toDouble();
    if (out <= 0) continue;
    outstandingByCust[cust] = (outstandingByCust[cust] ?? 0) + out;
    openByCust[cust] = (openByCust[cust] ?? 0) + 1;
  }

  final rows = [
    for (final c in customers)
      CustomerAccountRow(
        customerId: c.id,
        customerName: asNonEmpty(c.payload['customer_name']) ?? c.id,
        outstanding: outstandingByCust[c.id] ?? 0,
        openInvoices: openByCust[c.id] ?? 0,
      ),
  ];
  rows.sort((a, b) => b.outstanding.compareTo(a.outstanding));
  return rows;
});
