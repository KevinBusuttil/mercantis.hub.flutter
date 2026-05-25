import 'package:flutter/material.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';
import '../mock/mock_data.dart';

class DeliveryRouteScreen extends StatefulWidget {
  const DeliveryRouteScreen({super.key});

  @override
  State<DeliveryRouteScreen> createState() => _DeliveryRouteScreenState();
}

class _DeliveryRouteScreenState extends State<DeliveryRouteScreen> {
  String? _selectedStopId;

  @override
  Widget build(BuildContext context) {
    final route = MockData.routes.first;
    final bp = Breakpoint.of(context);

    final list = DocumentListPane(
      title: 'Route ${route.id}',
      subtitle: '${route.date} · ${route.driver}',
      searchHint: 'Search stops',
      onSearchChanged: (_) {},
      rows: [
        for (var i = 0; i < route.stops.length; i++)
          DocumentListPaneRow(
            id: route.stops[i].id,
            title: '${i + 1}. ${route.stops[i].customer}',
            subtitle: route.stops[i].address,
            statusLabel: route.stops[i].status == 'delivered' ? 'Delivered' : 'Pending',
            statusTone: route.stops[i].status == 'delivered'
                ? StatusTone.approved
                : StatusTone.pending,
            timestamp: route.stops[i].eta,
          ),
      ],
      selectedId: _selectedStopId ?? route.stops.first.id,
      onRowTap: (r) => setState(() => _selectedStopId = r.id),
    );

    if (bp.isPhone) return Scaffold(body: list);

    final selected = route.stops.firstWhere(
      (s) => s.id == (_selectedStopId ?? route.stops.first.id),
      orElse: () => route.stops.first,
    );

    return Scaffold(
      body: ResponsiveSplit(
        list: list,
        detail: _StopDetail(stop: selected),
      ),
    );
  }
}

class _StopDetail extends StatelessWidget {
  const _StopDetail({required this.stop});
  final HubDeliveryStop stop;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDelivered = stop.status == 'delivered';
    return DocumentDetailPane(
      title: stop.customer,
      subtitle: stop.address,
      statusLabel: isDelivered ? 'Delivered' : 'Pending',
      statusTone: isDelivered ? StatusTone.approved : StatusTone.pending,
      actions: [
        if (!isDelivered)
          WorkflowActionButton(
            label: 'Mark delivered',
            icon: Icons.check,
            style: WorkflowActionStyle.primary,
            onPressed: () {},
          ),
        WorkflowActionButton(
          label: 'Capture POD',
          icon: Icons.camera_alt_outlined,
          onPressed: () {},
        ),
      ],
      child: ListView(
        padding: const EdgeInsets.all(MercantisSpacing.xl),
        children: [
          Material(
            color: theme.colorScheme.surfaceContainerLow,
            borderRadius: MercantisRadius.rLg,
            child: Container(
              height: 200,
              alignment: Alignment.center,
              child: Text(
                'Map view (placeholder)',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
          const SizedBox(height: MercantisSpacing.lg),
          Text('Items', style: theme.textTheme.titleSmall),
          const SizedBox(height: MercantisSpacing.sm),
          Text('${stop.items} units to deliver',
            style: theme.textTheme.bodyMedium),
          const SizedBox(height: MercantisSpacing.lg),
          Text('ETA  ${stop.eta}', style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}
