import 'package:flutter/material.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';
import '../mock/mock_data.dart';

class DriverTodayScreen extends StatelessWidget {
  const DriverTodayScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final route = MockData.routes.first;
    final delivered = route.stops.where((s) => s.status == 'delivered').length;
    return ResponsiveScaffold(
      title: 'Today · ${route.id}',
      subtitle: '${route.driver} · ${route.stops.length} stops · ${route.km} km',
      body: ListView.separated(
        itemCount: route.stops.length,
        separatorBuilder: (_, __) => const SizedBox(height: MercantisSpacing.sm),
        itemBuilder: (context, i) {
          final stop = route.stops[i];
          final isDone = stop.status == 'delivered';
          return Material(
            color: Theme.of(context).colorScheme.surface,
            shape: RoundedRectangleBorder(
              borderRadius: MercantisRadius.rMd,
              side: BorderSide(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: isDone
                    ? MercantisBrandColors.statusApproved.withValues(alpha: 0.15)
                    : MercantisBrandColors.accentDelivery.withValues(alpha: 0.15),
                foregroundColor: isDone
                    ? MercantisBrandColors.statusApproved
                    : MercantisBrandColors.accentDelivery,
                child: Text('${i + 1}'),
              ),
              title: Text(stop.customer,
                style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text('${stop.eta} · ${stop.address} · ${stop.items} items'),
              trailing: isDone
                  ? const StatusChip(label: 'Delivered', tone: StatusTone.approved, dense: true)
                  : FilledButton.icon(
                      onPressed: () {},
                      icon: const Icon(Icons.navigation_outlined, size: 16),
                      label: const Text('Navigate'),
                    ),
            ),
          );
        },
      ),
      padBody: true,
      leading: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: MercantisBrandColors.accentDelivery.withValues(alpha: 0.12),
          borderRadius: MercantisRadius.rPill,
        ),
        child: Text(
          '$delivered/${route.stops.length} done',
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            color: MercantisBrandColors.accentDelivery,
          ),
        ),
      ),
    );
  }
}
