import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

import 'screen_providers.dart';

/// Sales Order list-detail screen on real data.
/// Phone: list only (taps push the generic record form).
/// Tablet/desktop: list + detail (+ activity aside).
class SalesOrdersScreen extends ConsumerStatefulWidget {
  const SalesOrdersScreen({super.key, this.initialId});
  final String? initialId;

  @override
  ConsumerState<SalesOrdersScreen> createState() => _SalesOrdersScreenState();
}

class _SalesOrdersScreenState extends ConsumerState<SalesOrdersScreen> {
  String? _selectedId;
  String _filter = 'all';
  String _query = '';

  @override
  void initState() {
    super.initState();
    _selectedId = widget.initialId;
  }

  List<SalesOrderRow> _filtered(List<SalesOrderRow> all) {
    return all.where((o) {
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
    final async = ref.watch(salesOrdersProvider);

    return async.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Text('Error: $e'))),
      data: (allOrders) {
        if (allOrders.isEmpty) {
          return Scaffold(
            body: EmptyState(
              title: 'No sales orders yet',
              message: 'Create your first Sales Order to get started.',
              icon: Icons.shopping_cart_outlined,
              action: FilledButton.icon(
                onPressed: () => context.go('/form/Sales Order/new'),
                icon: const Icon(Icons.add),
                label: const Text('New Sales Order'),
              ),
            ),
          );
        }

        final orders = _filtered(allOrders);
        final selectedId = _selectedId ??
            (orders.isNotEmpty ? orders.first.id : allOrders.first.id);

        final list = DocumentListPane(
          title: 'Sales Orders',
          subtitle: '${allOrders.length} total',
          searchHint: 'Search by number or customer',
          onSearchChanged: (v) => setState(() => _query = v),
          filterChips: [
            for (final entry in const {
              'all': 'All',
              'draft': 'Draft',
              'submitted': 'Submitted',
              'cancelled': 'Cancelled',
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
                subtitle: o.deliveryDate.isEmpty
                    ? null
                    : 'Delivery ${o.deliveryDate}',
                amount: o.amount,
                statusLabel: _statusLabel(o.docStatus),
                statusTone: _statusTone(o.docStatus),
                timestamp: o.date,
              ),
          ],
          selectedId: selectedId,
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

        final detailAsync = ref.watch(salesOrderDetailProvider(selectedId));
        final detail = detailAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
          data: (d) => d == null
              ? const Center(child: Text('Order not found'))
              : _SalesOrderDetail(detail: d),
        );

        return Scaffold(
          body: ResponsiveSplit(
            list: list,
            detail: detail,
            aside: _SalesOrderActivity(id: selectedId),
          ),
        );
      },
    );
  }

  String _statusLabel(int s) => switch (s) {
        0 => 'Draft',
        1 => 'Submitted',
        2 => 'Cancelled',
        _ => 'Unknown',
      };
  StatusTone _statusTone(int s) => switch (s) {
        0 => StatusTone.draft,
        1 => StatusTone.submitted,
        2 => StatusTone.cancelled,
        _ => StatusTone.neutral,
      };
}

class _SalesOrderDetail extends StatelessWidget {
  const _SalesOrderDetail({required this.detail});
  final SalesOrderDetail detail;

  @override
  Widget build(BuildContext context) {
    final s = detail.header.docStatus;
    final statusLabel = switch (s) {
      0 => 'Draft',
      1 => 'Submitted',
      2 => 'Cancelled',
      _ => 'Unknown',
    };
    final statusTone = switch (s) {
      0 => StatusTone.draft,
      1 => StatusTone.submitted,
      2 => StatusTone.cancelled,
      _ => StatusTone.neutral,
    };
    return DocumentDetailPane(
      title: '${detail.header.id} · ${detail.header.customer}',
      subtitle: detail.header.deliveryDate.isEmpty
          ? detail.header.date
          : '${detail.header.date}  ·  Delivery ${detail.header.deliveryDate}',
      statusLabel: statusLabel,
      statusTone: statusTone,
      tabs: const ['Overview', 'Items'],
      tabViews: [
        _Overview(detail: detail),
        _Items(items: detail.items),
      ],
      child: const SizedBox.shrink(),
    );
  }
}

class _Overview extends StatelessWidget {
  const _Overview({required this.detail});
  final SalesOrderDetail detail;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(MercantisSpacing.xl),
      children: [
        AtlasSectionCard(
          name: 'Order',
          child: Column(
            children: [
              AtlasFieldRow(
                  label: 'Customer',
                  value: detail.header.customer,
                  placeholder: '—',
                  readOnly: true),
              AtlasFieldRow(
                  label: 'Order date',
                  value: detail.header.date,
                  placeholder: '—',
                  readOnly: true),
              AtlasFieldRow(
                  label: 'Delivery date',
                  value: detail.header.deliveryDate,
                  placeholder: '—',
                  readOnly: true),
              AtlasFieldRow(
                  label: 'Currency',
                  value: detail.currency,
                  placeholder: '—',
                  readOnly: true),
            ],
          ),
        ),
        const SizedBox(height: MercantisSpacing.lg),
        AtlasSectionCard(
          name: 'Totals',
          child: Column(
            children: [
              AtlasTotalRow(label: 'Subtotal', value: detail.subtotal),
              AtlasTotalRow(
                  label: 'Grand total',
                  value: detail.grandTotal,
                  emphasize: true),
            ],
          ),
        ),
      ],
    );
  }
}

class _Items extends StatelessWidget {
  const _Items({required this.items});
  final List<SalesOrderLine> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const EmptyState(
        title: 'No line items',
        icon: Icons.list_alt_outlined,
      );
    }
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
            for (final l in items)
              ErpDataRow(cells: [
                Text(l.qty),
                Text(l.item),
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

class _SalesOrderActivity extends StatelessWidget {
  const _SalesOrderActivity({required this.id});
  final String id;

  @override
  Widget build(BuildContext context) {
    return DocumentActionPanel(
      title: 'Order $id',
      groups: [
        DocumentActionGroup(
          label: 'Open',
          actions: [
            WorkflowActionButton(
              label: 'Open full record',
              icon: Icons.open_in_full,
              style: WorkflowActionStyle.primary,
              onPressed: () => context.go('/form/Sales Order/$id'),
            ),
          ],
        ),
        DocumentActionGroup(
          label: 'Linked',
          actions: [
            WorkflowActionButton(
              label: 'Delivery Note',
              icon: Icons.local_shipping_outlined,
              onPressed: () => context.go('/list/Delivery Note'),
            ),
            WorkflowActionButton(
              label: 'Sales Invoice',
              icon: Icons.receipt_long_outlined,
              onPressed: () => context.go('/list/Sales Invoice'),
            ),
          ],
        ),
      ],
    );
  }
}
