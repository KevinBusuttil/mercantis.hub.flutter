import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';
import '../mock/mock_data.dart';

/// Prototype Sales Order list-detail screen using mock data.
/// On phone: only the list (taps push a detail route).
/// On tablet: list + detail.
/// On desktop: list + detail + activity.
class SalesOrdersScreen extends ConsumerStatefulWidget {
  const SalesOrdersScreen({super.key, this.initialId});
  final String? initialId;

  @override
  ConsumerState<SalesOrdersScreen> createState() => _SalesOrdersScreenState();
}

class _SalesOrdersScreenState extends ConsumerState<SalesOrdersScreen> {
  late String _selectedId;
  String _filter = 'all';
  String _query = '';

  @override
  void initState() {
    super.initState();
    _selectedId = widget.initialId ?? MockData.salesOrders.first.id;
  }

  List<HubSalesOrderMock> _rows() {
    return MockData.salesOrders.where((o) {
      if (_filter == 'draft' && o.docStatus != 0) return false;
      if (_filter == 'submitted' && o.docStatus != 1) return false;
      if (_filter == 'cancelled' && o.docStatus != 2) return false;
      if (_query.isEmpty) return true;
      final q = _query.toLowerCase();
      return o.id.toLowerCase().contains(q) ||
          o.customer.toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final bp = Breakpoint.of(context);
    final orders = _rows();
    final selected = MockData.salesOrders.firstWhere(
      (o) => o.id == _selectedId,
      orElse: () => orders.isNotEmpty ? orders.first : MockData.salesOrders.first,
    );

    final list = DocumentListPane(
      title: 'Sales Orders',
      subtitle: '${MockData.salesOrders.length} total',
      searchHint: 'Search by number or customer',
      onSearchChanged: (v) => setState(() => _query = v),
      filterChips: [
        for (final entry in const {
          'all': 'All', 'draft': 'Draft',
          'submitted': 'Submitted', 'cancelled': 'Cancelled',
        }.entries)
          FilterChip(
            label: Text(entry.value),
            selected: _filter == entry.key,
            onSelected: (_) => setState(() => _filter = entry.key),
          ),
      ],
      rows: [
        for (final o in orders)
          DocumentListPaneRow(
            id: o.id,
            title: '${o.id} · ${o.customer}',
            subtitle: 'Delivery ${o.deliveryDate}',
            amount: o.amount,
            statusLabel: _statusLabel(o.docStatus),
            statusTone: _statusTone(o.docStatus),
            timestamp: o.date,
          ),
      ],
      selectedId: _selectedId,
      onRowTap: (r) {
        if (bp.isPhone) {
          context.go('/form/Sales Order/${r.id}');
        } else {
          setState(() => _selectedId = r.id);
        }
      },
      onNew: () => context.go('/form/Sales Order/new'),
      newLabel: 'New Sales Order',
    );

    if (bp.isPhone) return Scaffold(body: list);

    final detail = _SalesOrderDetail(order: selected);
    final aside = _SalesOrderActivity(order: selected);

    return Scaffold(
      body: ResponsiveSplit(
        list: list,
        detail: detail,
        aside: aside,
      ),
    );
  }

  String _statusLabel(int s) => switch (s) {
        0 => 'Draft', 1 => 'Submitted', 2 => 'Cancelled', _ => 'Unknown',
      };
  StatusTone _statusTone(int s) => switch (s) {
        0 => StatusTone.draft,
        1 => StatusTone.submitted,
        2 => StatusTone.cancelled,
        _ => StatusTone.neutral,
      };
}

class _SalesOrderDetail extends StatelessWidget {
  const _SalesOrderDetail({required this.order});
  final HubSalesOrderMock order;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusLabel = switch (order.docStatus) {
      0 => 'Draft', 1 => 'Submitted', 2 => 'Cancelled', _ => 'Unknown',
    };
    final statusTone = switch (order.docStatus) {
      0 => StatusTone.draft,
      1 => StatusTone.submitted,
      2 => StatusTone.cancelled,
      _ => StatusTone.neutral,
    };
    return DocumentDetailPane(
      title: '${order.id} · ${order.customer}',
      subtitle: '${order.date}  ·  Delivery ${order.deliveryDate}',
      statusLabel: statusLabel,
      statusTone: statusTone,
      actions: [
        if (order.docStatus == 0) ...[
          WorkflowActionButton(
            label: 'Save', icon: Icons.save_outlined,
            style: WorkflowActionStyle.secondary,
            onPressed: () {},
          ),
          WorkflowActionButton(
            label: 'Submit', icon: Icons.check,
            style: WorkflowActionStyle.primary,
            onPressed: () {},
          ),
        ] else if (order.docStatus == 1)
          WorkflowActionButton(
            label: 'Cancel', icon: Icons.cancel_outlined,
            style: WorkflowActionStyle.danger,
            onPressed: () {},
          ),
      ],
      tabs: const ['Overview', 'Items', 'Timeline'],
      tabViews: [
        _Overview(order: order, theme: theme),
        _Items(order: order),
        _Timeline(order: order),
      ],
      child: const SizedBox.shrink(),
    );
  }
}

class _Overview extends StatelessWidget {
  const _Overview({required this.order, required this.theme});
  final HubSalesOrderMock order;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(MercantisSpacing.xl),
      children: [
        _kv('Customer', order.customer, theme),
        _kv('Order date', order.date, theme),
        _kv('Delivery date', order.deliveryDate, theme),
        _kv('Currency', 'EUR', theme),
        const SizedBox(height: MercantisSpacing.lg),
        Text('Totals', style: theme.textTheme.titleSmall),
        const SizedBox(height: MercantisSpacing.sm),
        _kv('Subtotal', order.amount, theme),
        _kv('Tax', '€0.00', theme),
        _kv('Grand total', order.amount, theme, bold: true),
      ],
    );
  }

  Widget _kv(String k, String v, ThemeData t, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 160,
            child: Text(k, style: t.textTheme.bodySmall),
          ),
          Expanded(
            child: Text(
              v,
              style: t.textTheme.bodyMedium?.copyWith(
                fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Items extends StatelessWidget {
  const _Items({required this.order});
  final HubSalesOrderMock order;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(MercantisSpacing.xl),
      children: [
        ErpDataTable(
          columns: const [
            ErpDataColumn(label: 'Qty', flex: 1, numeric: true),
            ErpDataColumn(label: 'Item', flex: 4),
            ErpDataColumn(label: 'Rate', flex: 2, numeric: true),
            ErpDataColumn(label: 'Amount', flex: 2, numeric: true),
          ],
          rows: [
            for (final l in order.items)
              ErpDataRow(cells: [
                Text(l.qty.toStringAsFixed(0)),
                Text('${l.itemCode} · ${l.itemName}'),
                Text(l.rate),
                Text(l.amount,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              ]),
          ],
        ),
      ],
    );
  }
}

class _Timeline extends StatelessWidget {
  const _Timeline({required this.order});
  final HubSalesOrderMock order;

  @override
  Widget build(BuildContext context) {
    return DocumentTimelinePanel(
      entries: [
        TimelineEntry(
          title: 'Order created',
          actor: 'A. Borg',
          timestamp: order.date,
          icon: Icons.add,
        ),
        if (order.docStatus >= 1)
          TimelineEntry(
            title: 'Submitted',
            actor: 'M. Said',
            timestamp: order.date,
            icon: Icons.check,
            tone: MercantisBrandColors.statusSubmitted,
          ),
        if (order.docStatus == 2)
          TimelineEntry(
            title: 'Cancelled',
            actor: 'K. Busuttil',
            timestamp: order.date,
            icon: Icons.cancel,
            tone: MercantisBrandColors.statusCancelled,
          ),
      ],
    );
  }
}

class _SalesOrderActivity extends StatelessWidget {
  const _SalesOrderActivity({required this.order});
  final HubSalesOrderMock order;

  @override
  Widget build(BuildContext context) {
    return DocumentActionPanel(
      title: 'Order ${order.id}',
      groups: [
        DocumentActionGroup(
          label: 'Workflow',
          actions: [
            if (order.docStatus == 0) ...[
              WorkflowActionButton(
                label: 'Submit', icon: Icons.check,
                style: WorkflowActionStyle.primary,
                onPressed: () {},
              ),
              WorkflowActionButton(
                label: 'Save', icon: Icons.save_outlined,
                onPressed: () {},
              ),
            ] else if (order.docStatus == 1) ...[
              WorkflowActionButton(
                label: 'Cancel', icon: Icons.cancel_outlined,
                style: WorkflowActionStyle.danger,
                onPressed: () {},
              ),
            ],
          ],
        ),
        DocumentActionGroup(
          label: 'Linked',
          actions: [
            WorkflowActionButton(
              label: 'Delivery Note', icon: Icons.local_shipping_outlined,
              onPressed: () {},
            ),
            WorkflowActionButton(
              label: 'Sales Invoice', icon: Icons.receipt_long_outlined,
              onPressed: () {},
            ),
          ],
        ),
        DocumentActionGroup(
          label: 'Share',
          actions: [
            WorkflowActionButton(
              label: 'Email PDF', icon: Icons.email_outlined,
              onPressed: () {},
            ),
            WorkflowActionButton(
              label: 'Print', icon: Icons.print_outlined,
              onPressed: () {},
            ),
          ],
        ),
      ],
    );
  }
}
