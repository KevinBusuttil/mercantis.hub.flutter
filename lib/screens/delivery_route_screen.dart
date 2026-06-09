import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

import 'screen_providers.dart';

class DeliveryRouteScreen extends ConsumerStatefulWidget {
  const DeliveryRouteScreen({super.key});

  @override
  ConsumerState<DeliveryRouteScreen> createState() =>
      _DeliveryRouteScreenState();
}

class _DeliveryRouteScreenState extends ConsumerState<DeliveryRouteScreen> {
  int? _selectedSeq;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(latestDeliveryRouteProvider);
    final bp = Breakpoint.of(context);

    return async.when(
      loading: () => const Scaffold(
          body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Text('Error: $e'))),
      data: (route) {
        if (route == null || route.stops.isEmpty) {
          return const Scaffold(
            body: EmptyState(
              title: 'No route planned',
              message: 'Plan a Delivery Route to see its stops here.',
              icon: Icons.alt_route_outlined,
            ),
          );
        }

        final list = DocumentListPane(
          title: route.routeName,
          subtitle: '${route.date} · ${route.driverName}',
          searchHint: 'Search stops',
          onSearchChanged: (_) {},
          rows: [
            for (final s in route.stops)
              DocumentListPaneRow(
                id: '${s.sequence}',
                title: '${s.sequence}. ${s.customer}',
                subtitle: s.address,
                statusLabel: s.isDone ? 'Delivered' : s.status,
                statusTone:
                    s.isDone ? StatusTone.approved : StatusTone.pending,
              ),
          ],
          selectedId: '${_selectedSeq ?? route.stops.first.sequence}',
          onRowTap: (r) =>
              setState(() => _selectedSeq = int.tryParse(r.id)),
        );

        if (bp.isPhone) return Scaffold(body: list);

        final selected = route.stops.firstWhere(
          (s) => s.sequence == (_selectedSeq ?? route.stops.first.sequence),
          orElse: () => route.stops.first,
        );

        return Scaffold(
          body: ResponsiveSplit(
            list: list,
            detail: _StopDetail(stop: selected),
          ),
        );
      },
    );
  }
}

class _StopDetail extends StatelessWidget {
  const _StopDetail({required this.stop});
  final RouteStopView stop;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DocumentDetailPane(
      title: stop.customer,
      subtitle: stop.address,
      statusLabel: stop.isDone ? 'Delivered' : stop.status,
      statusTone: stop.isDone ? StatusTone.approved : StatusTone.pending,
      actions: [
        if (!stop.isDone)
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
          Text('Stop ${stop.sequence}', style: theme.textTheme.titleSmall),
          const SizedBox(height: MercantisSpacing.sm),
          Text('Status: ${stop.status}', style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}
