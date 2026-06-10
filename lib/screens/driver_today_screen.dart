import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

import 'screen_providers.dart';

class DriverTodayScreen extends ConsumerWidget {
  const DriverTodayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(latestDeliveryRouteProvider);

    return async.when(
      loading: () => const ResponsiveScaffold(
        title: 'Today',
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => ResponsiveScaffold(
        title: 'Today',
        body: Center(child: Text('Error: $e')),
      ),
      data: (route) {
        if (route == null || route.stops.isEmpty) {
          return const ResponsiveScaffold(
            title: 'Today',
            body: EmptyState(
              title: 'No route assigned',
              message: 'Stops appear here once a Delivery Route is planned.',
              icon: Icons.local_shipping_outlined,
            ),
          );
        }
        return ResponsiveScaffold(
          title: 'Today · ${route.routeName}',
          subtitle:
              '${route.driverName} · ${route.stops.length} stops · ${route.delivered} delivered',
          body: ListView.separated(
            itemCount: route.stops.length,
            separatorBuilder: (_, __) =>
                const SizedBox(height: MercantisSpacing.sm),
            itemBuilder: (context, i) {
              final stop = route.stops[i];
              final isDone = stop.isDone;
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
                        ? MercantisBrandColors.statusApproved
                            .withValues(alpha: 0.15)
                        : MercantisBrandColors.accentDelivery
                            .withValues(alpha: 0.15),
                    foregroundColor: isDone
                        ? MercantisBrandColors.statusApproved
                        : MercantisBrandColors.accentDelivery,
                    child: Text('${stop.sequence}'),
                  ),
                  title: Text(stop.customer,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(stop.address.isEmpty
                      ? stop.status
                      : '${stop.address} · ${stop.status}'),
                  trailing: isDone
                      ? const StatusChip(
                          label: 'Delivered',
                          tone: StatusTone.approved,
                          dense: true)
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
              '${route.delivered}/${route.stops.length} done',
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: MercantisBrandColors.accentDelivery,
              ),
            ),
          ),
        );
      },
    );
  }
}
