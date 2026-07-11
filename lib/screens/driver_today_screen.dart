import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

import '../deliveries/pod_capture.dart';
import 'screen_providers.dart';

/// The driver's working screen (S3/S12): today's stops with real actions —
/// Deliver captures proof (signature/photo/note) at the door; Failed
/// records why. Both write through the route so status events and the
/// Delivery Note mirror stay consistent.
class DriverTodayScreen extends ConsumerWidget {
  const DriverTodayScreen({super.key});

  Future<void> _deliver(BuildContext context, WidgetRef ref,
      DeliveryRouteView route, RouteStopView stop) async {
    final pod =
        await showPodCaptureSheet(context, customer: stop.customer);
    if (pod == null) return;
    final engine = await ref.read(documentEngineProvider.future);
    try {
      await markStopStatus(engine,
          routeId: route.id,
          sequence: stop.sequence,
          status: 'Delivered',
          pod: pod);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      ref.invalidate(latestDeliveryRouteProvider);
    }
  }

  Future<void> _fail(BuildContext context, WidgetRef ref,
      DeliveryRouteView route, RouteStopView stop) async {
    final noteCtrl = TextEditingController();
    final sure = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Could not deliver to ${stop.customer}?'),
        content: TextField(
          controller: noteCtrl,
          autofocus: true,
          decoration: const InputDecoration(
              labelText: 'What happened?', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Back')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Mark failed')),
        ],
      ),
    );
    if (sure != true) return;
    final engine = await ref.read(documentEngineProvider.future);
    try {
      await markStopStatus(engine,
          routeId: route.id,
          sequence: stop.sequence,
          status: 'Failed',
          pod: noteCtrl.text.trim().isEmpty
              ? null
              : PodCapture(note: noteCtrl.text.trim()));
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      ref.invalidate(latestDeliveryRouteProvider);
    }
  }

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
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (stop.hasPod)
                              const Padding(
                                padding: EdgeInsets.only(right: 6),
                                child: Icon(Icons.draw_outlined, size: 18),
                              ),
                            const StatusChip(
                                label: 'Delivered',
                                tone: StatusTone.approved,
                                dense: true),
                          ],
                        )
                      : stop.isFailed
                          ? const StatusChip(
                              label: 'Failed',
                              tone: StatusTone.overdue,
                              dense: true)
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                TextButton(
                                  onPressed: () =>
                                      _fail(context, ref, route, stop),
                                  child: const Text('Failed'),
                                ),
                                const SizedBox(width: 4),
                                FilledButton.icon(
                                  onPressed: () =>
                                      _deliver(context, ref, route, stop),
                                  icon: const Icon(Icons.done_outlined,
                                      size: 16),
                                  label: const Text('Deliver'),
                                ),
                              ],
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
