import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

import '../ledger/ledger_values.dart';

/// Real data sources for the Hub's bespoke custom screens, replacing the old
/// `MockData` prototypes. Each provider reads the live document store via
/// `DocumentEngine.list`.

/// Shared light currency format (no intl locale dependency).
String money(num v) => '€${v.toDouble().toStringAsFixed(2)}';

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

// ─── Delivery route (today) ──────────────────────────────────────────────────

class RouteStopView {
  const RouteStopView({
    required this.sequence,
    required this.customer,
    required this.address,
    required this.status,
  });

  final int sequence;
  final String customer;
  final String address;
  final String status;

  bool get isDone => status.toLowerCase() == 'delivered';
}

class DeliveryRouteView {
  const DeliveryRouteView({
    required this.id,
    required this.routeName,
    required this.driverName,
    required this.date,
    required this.status,
    required this.stops,
  });

  final String id;
  final String routeName;
  final String driverName;
  final String date;
  final String status;
  final List<RouteStopView> stops;

  int get delivered => stops.where((s) => s.isDone).length;
}

/// The most recent Delivery Route (by `route_date`), with its stops resolved to
/// customer/driver names. Returns null when no routes exist.
final latestDeliveryRouteProvider =
    FutureProvider<DeliveryRouteView?>((ref) async {
  final engine = await ref.watch(documentEngineProvider.future);
  final routes = await engine.list('Delivery Route');
  if (routes.isEmpty) return null;

  routes.sort((a, b) => (asNonEmpty(b.payload['route_date']) ?? '')
      .compareTo(asNonEmpty(a.payload['route_date']) ?? ''));
  final route = await engine.fetch('Delivery Route', routes.first.id) ??
      routes.first;

  String? driverName;
  final driverId = asNonEmpty(route.payload['driver']);
  if (driverId != null) {
    final d = await engine.fetch('Driver', driverId);
    driverName = asNonEmpty(d?.payload['driver_name']) ?? driverId;
  }

  final customers = {
    for (final c in await engine.list('Customer'))
      c.id: asNonEmpty(c.payload['customer_name']) ?? c.id,
  };

  final stops = [
    for (final s in route.children['stops'] ?? const [])
      RouteStopView(
        sequence: asNum(s.payload['sequence']).toInt(),
        customer: customers[asNonEmpty(s.payload['customer'])] ??
            asNonEmpty(s.payload['customer']) ??
            '—',
        address: asNonEmpty(s.payload['address']) ?? '',
        status: asNonEmpty(s.payload['status']) ?? 'Pending',
      ),
  ]..sort((a, b) => a.sequence.compareTo(b.sequence));

  return DeliveryRouteView(
    id: route.id,
    routeName: asNonEmpty(route.payload['route_name']) ?? route.id,
    driverName: driverName ?? 'Unassigned',
    date: asNonEmpty(route.payload['route_date']) ?? '',
    status: asNonEmpty(route.payload['status']) ?? 'Draft',
    stops: stops,
  );
});

// ─── Sales orders ────────────────────────────────────────────────────────────

class SalesOrderRow {
  const SalesOrderRow({
    required this.id,
    required this.customer,
    required this.date,
    required this.deliveryDate,
    required this.amount,
    required this.docStatus,
  });

  final String id;
  final String customer;
  final String date;
  final String deliveryDate;
  final String amount;
  final int docStatus;
}

/// All Sales Orders (customer resolved, grand total formatted), newest first.
final salesOrdersProvider = FutureProvider<List<SalesOrderRow>>((ref) async {
  final engine = await ref.watch(documentEngineProvider.future);
  final orders = await engine.list('Sales Order');
  final customers = {
    for (final c in await engine.list('Customer'))
      c.id: asNonEmpty(c.payload['customer_name']) ?? c.id,
  };
  final rows = [
    for (final o in orders)
      SalesOrderRow(
        id: o.id,
        customer: customers[asNonEmpty(o.payload['customer'])] ??
            asNonEmpty(o.payload['customer']) ??
            '—',
        date: asNonEmpty(o.payload['transaction_date']) ?? '',
        deliveryDate: asNonEmpty(o.payload['delivery_date']) ?? '',
        amount: money(asNum(o.payload['grand_total'])),
        docStatus: o.docStatus,
      ),
  ];
  rows.sort((a, b) => b.date.compareTo(a.date));
  return rows;
});

class SalesOrderLine {
  const SalesOrderLine({
    required this.qty,
    required this.item,
    required this.rate,
    required this.amount,
  });

  final String qty;
  final String item;
  final String rate;
  final String amount;
}

class SalesOrderDetail {
  const SalesOrderDetail({
    required this.header,
    required this.currency,
    required this.subtotal,
    required this.grandTotal,
    required this.items,
  });

  final SalesOrderRow header;
  final String currency;
  final String subtotal;
  final String grandTotal;
  final List<SalesOrderLine> items;
}

/// One Sales Order with its line items resolved to item names. Null if missing.
final salesOrderDetailProvider =
    FutureProvider.family<SalesOrderDetail?, String>((ref, id) async {
  final engine = await ref.watch(documentEngineProvider.future);
  final doc = await engine.fetch('Sales Order', id);
  if (doc == null) return null;

  Future<String> resolveCustomerName() async {
    final cid = asNonEmpty(doc.payload['customer']);
    if (cid == null) return '—';
    final c = await engine.fetch('Customer', cid);
    return asNonEmpty(c?.payload['customer_name']) ?? cid;
  }
  final itemsCat = {
    for (final it in await engine.list('Item'))
      it.id: asNonEmpty(it.payload['item_name']) ?? it.id,
  };

  final lines = [
    for (final r in doc.children['items'] ?? const [])
      SalesOrderLine(
        qty: asNum(r.payload['qty']).toString(),
        item: () {
          final iid = asNonEmpty(r.payload['item']);
          final name = iid == null ? null : itemsCat[iid];
          return name == null ? (iid ?? '—') : '$iid · $name';
        }(),
        rate: money(asNum(r.payload['rate'])),
        amount: money(asNum(r.payload['amount'])),
      ),
  ];

  return SalesOrderDetail(
    header: SalesOrderRow(
      id: doc.id,
      customer: await resolveCustomerName(),
      date: asNonEmpty(doc.payload['transaction_date']) ?? '',
      deliveryDate: asNonEmpty(doc.payload['delivery_date']) ?? '',
      amount: money(asNum(doc.payload['grand_total'])),
      docStatus: doc.docStatus,
    ),
    currency: asNonEmpty(doc.payload['currency']) ?? 'EUR',
    subtotal: money(asNum(doc.payload['total'])),
    grandTotal: money(asNum(doc.payload['grand_total'])),
    items: lines,
  );
});
