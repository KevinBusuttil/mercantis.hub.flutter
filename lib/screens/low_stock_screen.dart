import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

import 'screen_providers.dart';

class LowStockScreen extends ConsumerWidget {
  const LowStockScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(lowStockProvider);
    final low = async.valueOrNull ?? const <LowStockRow>[];

    return ResponsiveScaffold(
      title: 'Low stock',
      subtitle: async.isLoading
          ? 'Loading…'
          : '${low.length} item(s) below reorder level',
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (rows) {
          if (rows.isEmpty) {
            return const EmptyState(
              title: 'Nothing below reorder',
              message:
                  'Items show here once their on-hand qty drops below the '
                  'reorder level set on the Item.',
              icon: Icons.check_circle_outline,
            );
          }
          return ErpDataTable(
            columns: const [
              ErpDataColumn(label: 'Item', flex: 4),
              ErpDataColumn(label: 'Warehouse', flex: 2),
              ErpDataColumn(label: 'On hand', flex: 2, numeric: true),
              ErpDataColumn(label: 'Reorder', flex: 2, numeric: true),
              ErpDataColumn(label: 'Status', flex: 2),
            ],
            rows: [
              for (final it in rows)
                ErpDataRow(cells: [
                  Text(it.itemName.isEmpty
                      ? it.itemCode
                      : '${it.itemCode} · ${it.itemName}'),
                  Text(it.warehouse),
                  Text('${it.qty.toStringAsFixed(0)} ${it.uom}'),
                  Text(it.reorderLevel.toStringAsFixed(0)),
                  const StatusChip(
                      label: 'Below', tone: StatusTone.overdue, dense: true),
                ]),
            ],
          );
        },
      ),
    );
  }
}
