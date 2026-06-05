import 'package:flutter/material.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';
import '../mock/mock_data.dart';

class LowStockScreen extends StatelessWidget {
  const LowStockScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final low = MockData.inventoryItems.where((i) => i.belowReorder).toList();
    return ResponsiveScaffold(
      title: 'Low stock',
      subtitle: '${low.length} items below reorder level',
      body: ErpDataTable(
        columns: const [
          ErpDataColumn(label: 'Item', flex: 4),
          ErpDataColumn(label: 'Warehouse', flex: 2),
          ErpDataColumn(label: 'On hand', flex: 2, numeric: true),
          ErpDataColumn(label: 'Reorder', flex: 2, numeric: true),
          ErpDataColumn(label: 'Status', flex: 2),
        ],
        rows: [
          for (final it in low)
            ErpDataRow(cells: [
              Text('${it.code} · ${it.name}'),
              Text(it.warehouse),
              Text('${it.qty.toStringAsFixed(0)} ${it.uom}'),
              Text(it.reorderLevel.toStringAsFixed(0)),
              const StatusChip(label: 'Below', tone: StatusTone.overdue, dense: true),
            ]),
        ],
      ),
    );
  }
}
