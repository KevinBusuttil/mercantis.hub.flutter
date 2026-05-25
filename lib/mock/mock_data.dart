import 'package:flutter/material.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

/// All mock data for the redesigned ERP prototype lives here.
/// Replace with backend-driven data sources once the domain layer is ready.

class HubKpi {
  const HubKpi({
    required this.id,
    required this.title,
    required this.value,
    this.subtitle,
    this.trend,
    this.trendLabel,
    this.icon,
    this.accent,
  });

  final String id;
  final String title;
  final String value;
  final String? subtitle;
  final KpiTrend? trend;
  final String? trendLabel;
  final IconData? icon;
  final Color? accent;
}

class HubRecentDocument {
  const HubRecentDocument({
    required this.id,
    required this.docType,
    required this.title,
    required this.subtitle,
    required this.timestamp,
    this.amount,
    this.statusLabel,
    this.statusTone,
  });

  final String id;
  final String docType;
  final String title;
  final String subtitle;
  final String timestamp;
  final String? amount;
  final String? statusLabel;
  final StatusTone? statusTone;
}

class HubSalesOrderMock {
  const HubSalesOrderMock({
    required this.id,
    required this.customer,
    required this.date,
    required this.deliveryDate,
    required this.amount,
    required this.docStatus,
    required this.items,
  });

  final String id;
  final String customer;
  final String date;
  final String deliveryDate;
  final String amount;
  final int docStatus;
  final List<HubSalesOrderItem> items;
}

class HubSalesOrderItem {
  const HubSalesOrderItem({
    required this.qty,
    required this.itemCode,
    required this.itemName,
    required this.rate,
    required this.amount,
  });

  final double qty;
  final String itemCode;
  final String itemName;
  final String rate;
  final String amount;
}

class HubInventoryItem {
  const HubInventoryItem({
    required this.code,
    required this.name,
    required this.qty,
    required this.uom,
    required this.warehouse,
    required this.reorderLevel,
  });

  final String code;
  final String name;
  final double qty;
  final String uom;
  final String warehouse;
  final double reorderLevel;

  bool get belowReorder => qty < reorderLevel;
}

class HubDeliveryStop {
  const HubDeliveryStop({
    required this.id,
    required this.customer,
    required this.address,
    required this.eta,
    required this.status,
    required this.items,
  });

  final String id;
  final String customer;
  final String address;
  final String eta;
  final String status; // 'pending','arrived','delivered'
  final int items;
}

class HubRoute {
  const HubRoute({
    required this.id,
    required this.driver,
    required this.date,
    required this.km,
    required this.stops,
  });

  final String id;
  final String driver;
  final String date;
  final int km;
  final List<HubDeliveryStop> stops;
}

class MockData {
  const MockData._();

  // ─── Sales ────────────────────────────────────────────────────────────────
  static const salesKpis = <HubKpi>[
    HubKpi(
      id: 'sales_today',
      title: 'Sales today',
      value: '€12,450',
      subtitle: '23 orders',
      trend: KpiTrend.up,
      trendLabel: '+18%',
      icon: Icons.trending_up,
      accent: MercantisBrandColors.accentSales,
    ),
    HubKpi(
      id: 'open_orders',
      title: 'Open orders',
      value: '14',
      subtitle: '€31,820',
      trend: KpiTrend.up,
      trendLabel: '+2',
      icon: Icons.shopping_cart_outlined,
      accent: MercantisBrandColors.accentSales,
    ),
    HubKpi(
      id: 'overdue_receivables',
      title: 'Overdue',
      value: '€4,210',
      subtitle: '3 customers',
      trend: KpiTrend.flat,
      icon: Icons.error_outline,
      accent: MercantisBrandColors.statusOverdue,
    ),
    HubKpi(
      id: 'avg_lead_time',
      title: 'Avg lead time',
      value: '3.2 d',
      subtitle: 'last 30 days',
      trend: KpiTrend.down,
      trendLabel: '-0.5 d',
      icon: Icons.schedule,
      accent: MercantisBrandColors.accentSales,
    ),
  ];

  static const salesRecent = <HubRecentDocument>[
    HubRecentDocument(
      id: 'SO-0142', docType: 'Sales Order',
      title: 'SO-0142', subtitle: 'ACME Ltd',
      timestamp: '2 min ago',
      amount: '€1,820',
      statusLabel: 'Draft', statusTone: StatusTone.draft,
    ),
    HubRecentDocument(
      id: 'SINV-321', docType: 'Sales Invoice',
      title: 'SINV-321', subtitle: 'BetaCo',
      timestamp: '12 min ago',
      amount: '€640',
      statusLabel: 'Submitted', statusTone: StatusTone.submitted,
    ),
    HubRecentDocument(
      id: 'SO-0141', docType: 'Sales Order',
      title: 'SO-0141', subtitle: 'Delta Industrial',
      timestamp: '1 h ago',
      amount: '€2,975',
      statusLabel: 'Submitted', statusTone: StatusTone.submitted,
    ),
    HubRecentDocument(
      id: 'PAY-88', docType: 'Payment Entry',
      title: 'PAY-88', subtitle: 'Echo Trading',
      timestamp: '3 h ago',
      amount: '€1,100',
      statusLabel: 'Paid', statusTone: StatusTone.paid,
    ),
  ];

  static const salesOrders = <HubSalesOrderMock>[
    HubSalesOrderMock(
      id: 'SO-0142',
      customer: 'ACME Ltd',
      date: '25 May 2026',
      deliveryDate: '31 May 2026',
      amount: '€1,820.00',
      docStatus: 0,
      items: [
        HubSalesOrderItem(qty: 1, itemCode: 'WGT-A',
          itemName: 'Widget A', rate: '€1,000.00', amount: '€1,000.00'),
        HubSalesOrderItem(qty: 2, itemCode: 'WGT-B',
          itemName: 'Widget B', rate: '€410.00', amount: '€820.00'),
      ],
    ),
    HubSalesOrderMock(
      id: 'SO-0141',
      customer: 'BetaCo',
      date: '24 May 2026',
      deliveryDate: '30 May 2026',
      amount: '€640.00',
      docStatus: 1,
      items: [
        HubSalesOrderItem(qty: 4, itemCode: 'WGT-C',
          itemName: 'Widget C', rate: '€160.00', amount: '€640.00'),
      ],
    ),
    HubSalesOrderMock(
      id: 'SO-0140',
      customer: 'Delta Industrial',
      date: '23 May 2026',
      deliveryDate: '02 Jun 2026',
      amount: '€2,975.00',
      docStatus: 1,
      items: [
        HubSalesOrderItem(qty: 5, itemCode: 'WGT-A',
          itemName: 'Widget A', rate: '€595.00', amount: '€2,975.00'),
      ],
    ),
    HubSalesOrderMock(
      id: 'SO-0139',
      customer: 'Echo Trading',
      date: '22 May 2026',
      deliveryDate: '28 May 2026',
      amount: '€1,100.00',
      docStatus: 1,
      items: [
        HubSalesOrderItem(qty: 10, itemCode: 'WGT-B',
          itemName: 'Widget B', rate: '€110.00', amount: '€1,100.00'),
      ],
    ),
    HubSalesOrderMock(
      id: 'SO-0138',
      customer: 'Foxtrot Supplies',
      date: '21 May 2026',
      deliveryDate: '27 May 2026',
      amount: '€915.00',
      docStatus: 2,
      items: [
        HubSalesOrderItem(qty: 3, itemCode: 'WGT-C',
          itemName: 'Widget C', rate: '€305.00', amount: '€915.00'),
      ],
    ),
  ];

  // ─── Inventory ────────────────────────────────────────────────────────────
  static const inventoryKpis = <HubKpi>[
    HubKpi(
      id: 'inv_stock_value', title: 'Stock value', value: '€84,210',
      subtitle: '3 warehouses',
      icon: Icons.inventory_2_outlined,
      accent: MercantisBrandColors.accentInventory,
    ),
    HubKpi(
      id: 'inv_low_stock', title: 'Below reorder', value: '7',
      subtitle: 'items',
      icon: Icons.warning_amber_outlined,
      accent: MercantisBrandColors.statusOverdue,
    ),
    HubKpi(
      id: 'inv_to_receive', title: 'To receive', value: '12',
      subtitle: 'PO lines',
      icon: Icons.local_shipping_outlined,
      accent: MercantisBrandColors.accentInventory,
    ),
    HubKpi(
      id: 'inv_to_pick', title: 'To pick', value: '5',
      subtitle: 'orders',
      icon: Icons.checklist_outlined,
      accent: MercantisBrandColors.accentInventory,
    ),
  ];

  static const inventoryItems = <HubInventoryItem>[
    HubInventoryItem(code: 'WGT-A', name: 'Widget A',
      qty: 124, uom: 'pcs', warehouse: 'Stores',  reorderLevel: 50),
    HubInventoryItem(code: 'WGT-B', name: 'Widget B',
      qty: 18,  uom: 'pcs', warehouse: 'Stores',  reorderLevel: 40),
    HubInventoryItem(code: 'WGT-C', name: 'Widget C',
      qty: 5,   uom: 'pcs', warehouse: 'Stores',  reorderLevel: 20),
    HubInventoryItem(code: 'BLT-12', name: 'Bolt M12',
      qty: 980, uom: 'pcs', warehouse: 'FG',      reorderLevel: 200),
    HubInventoryItem(code: 'BLT-16', name: 'Bolt M16',
      qty: 42,  uom: 'pcs', warehouse: 'FG',      reorderLevel: 100),
    HubInventoryItem(code: 'OIL-5L', name: 'Lubricating oil 5L',
      qty: 7,   uom: 'btl', warehouse: 'Stores',  reorderLevel: 15),
  ];

  // ─── Approvals ────────────────────────────────────────────────────────────
  static List<ApprovalEntry> approvals() => [
        ApprovalEntry(
          id: 'SO-0142', docType: 'Sales Order',
          title: 'SO-0142 — ACME Ltd',
          requestedBy: 'A. Borg',
          requestedAt: DateTime.now().subtract(const Duration(minutes: 12)),
          amount: '€1,820',
          subtitle: 'Discount > 10%',
          icon: Icons.shopping_cart_outlined,
          workspaceId: 'sales_fulfilment',
        ),
        ApprovalEntry(
          id: 'PINV-77', docType: 'Purchase Invoice',
          title: 'PINV-77 — Apex Supplies',
          requestedBy: 'M. Said',
          requestedAt: DateTime.now().subtract(const Duration(hours: 1)),
          amount: '€920',
          subtitle: 'Above budget',
          icon: Icons.receipt_long_outlined,
          workspaceId: 'purchasing',
        ),
        ApprovalEntry(
          id: 'STE-31', docType: 'Stock Entry',
          title: 'STE-31 — Warehouse transfer',
          requestedBy: 'J. Vella',
          requestedAt: DateTime.now().subtract(const Duration(hours: 3)),
          subtitle: 'Cross-warehouse',
          icon: Icons.swap_horiz,
          workspaceId: 'inventory',
        ),
      ];

  // ─── Delivery ─────────────────────────────────────────────────────────────
  static const routes = <HubRoute>[
    HubRoute(
      id: 'RT-22', driver: 'J. Borg', date: 'Mon 26 May', km: 87,
      stops: [
        HubDeliveryStop(id: 'S1', customer: 'ACME Ltd',
          address: '12 Main St, Birkirkara',
          eta: '09:00', status: 'delivered', items: 6),
        HubDeliveryStop(id: 'S2', customer: 'BetaCo',
          address: '4 Cross Rd, Sliema',
          eta: '09:45', status: 'delivered', items: 3),
        HubDeliveryStop(id: 'S3', customer: 'Delta Industrial',
          address: 'Industrial Estate, Marsa',
          eta: '10:30', status: 'pending', items: 5),
        HubDeliveryStop(id: 'S4', customer: 'Echo Trading',
          address: '8 Harbour Rd, Valletta',
          eta: '11:20', status: 'pending', items: 2),
        HubDeliveryStop(id: 'S5', customer: 'Foxtrot Supplies',
          address: '20 Industry Way, Qormi',
          eta: '12:15', status: 'pending', items: 4),
      ],
    ),
  ];
}
