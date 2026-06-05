import 'package:mercantis_core/mercantis_core.dart';

/// The Hub's 5 dashboards, resolved against the real document store by the Core
/// [DashboardEngine]. Monetary tiles use the `sum` widget (added to Core) so
/// receivables / sales / stock value read live data; `count` tiles count
/// documents, `list` tiles show recent rows, `chart` tiles embed a report.
abstract final class HubDashboards {
  static List<DashboardDefinition> all() => const [
        DashboardDefinition(
          id: 'home',
          name: 'Home',
          widgets: [
            DashboardWidget(id: 'home_open_orders', type: 'count', label: 'Open Sales Orders', config: {
              'docType': 'Sales Order',
            }),
            DashboardWidget(id: 'home_receivables', type: 'sum', label: 'Receivables', config: {
              'docType': 'Sales Invoice',
              'field': 'outstanding_amount',
            }),
            DashboardWidget(id: 'home_payables', type: 'sum', label: 'Payables', config: {
              'docType': 'Purchase Invoice',
              'field': 'outstanding_amount',
            }),
            DashboardWidget(id: 'home_recent_sales', type: 'list', label: 'Recent Invoices', config: {
              'docType': 'Sales Invoice',
              'columns': ['id', 'customer', 'grand_total'],
              'limit': 5,
            }),
          ],
        ),
        DashboardDefinition(
          id: 'finance',
          name: 'Finance',
          widgets: [
            DashboardWidget(id: 'fin_receivables', type: 'sum', label: 'Total Receivable', config: {
              'docType': 'Sales Invoice',
              'field': 'outstanding_amount',
            }),
            DashboardWidget(id: 'fin_payables', type: 'sum', label: 'Total Payable', config: {
              'docType': 'Purchase Invoice',
              'field': 'outstanding_amount',
            }),
            DashboardWidget(id: 'fin_payments', type: 'count', label: 'Payments', config: {
              'docType': 'Payment Entry',
            }),
            DashboardWidget(id: 'fin_gl', type: 'chart', label: 'General Ledger', config: {
              'reportId': 'general_ledger',
            }),
          ],
        ),
        DashboardDefinition(
          id: 'sales',
          name: 'Sales',
          widgets: [
            DashboardWidget(id: 'sales_orders', type: 'count', label: 'Sales Orders', config: {
              'docType': 'Sales Order',
            }),
            DashboardWidget(id: 'sales_invoiced', type: 'sum', label: 'Invoiced', config: {
              'docType': 'Sales Invoice',
              'field': 'grand_total',
            }),
            DashboardWidget(id: 'sales_recent', type: 'list', label: 'Recent Orders', config: {
              'docType': 'Sales Order',
              'columns': ['id', 'customer', 'grand_total'],
              'limit': 5,
            }),
            DashboardWidget(id: 'sales_all', type: 'shortcut', label: 'All Sales Orders', config: {
              'route': '/list/Sales Order',
            }),
          ],
        ),
        DashboardDefinition(
          id: 'buying',
          name: 'Buying',
          widgets: [
            DashboardWidget(id: 'buy_orders', type: 'count', label: 'Purchase Orders', config: {
              'docType': 'Purchase Order',
            }),
            DashboardWidget(id: 'buy_invoiced', type: 'sum', label: 'Billed', config: {
              'docType': 'Purchase Invoice',
              'field': 'grand_total',
            }),
            DashboardWidget(id: 'buy_recent', type: 'list', label: 'Recent Orders', config: {
              'docType': 'Purchase Order',
              'columns': ['id', 'supplier', 'grand_total'],
              'limit': 5,
            }),
            DashboardWidget(id: 'buy_all', type: 'shortcut', label: 'All Purchase Orders', config: {
              'route': '/list/Purchase Order',
            }),
          ],
        ),
        DashboardDefinition(
          id: 'inventory',
          name: 'Inventory',
          widgets: [
            DashboardWidget(id: 'inv_bins', type: 'count', label: 'Stocked Item/Warehouses', config: {
              'docType': 'Bin',
            }),
            DashboardWidget(id: 'inv_value', type: 'sum', label: 'Stock Value', config: {
              'docType': 'Bin',
              'field': 'stock_value',
            }),
            DashboardWidget(id: 'inv_recent', type: 'list', label: 'Recent Movements', config: {
              'docType': 'Stock Ledger Entry',
              'columns': ['item', 'warehouse', 'qty_change'],
              'limit': 5,
            }),
            DashboardWidget(id: 'inv_balance', type: 'chart', label: 'Stock Balance', config: {
              'reportId': 'stock_balance',
            }),
          ],
        ),
      ];
}
