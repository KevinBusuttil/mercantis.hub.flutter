import 'package:mercantis_core/mercantis_core.dart';

import '../ledger/ledger_values.dart';

const _systemRoles = {'System Manager'};

/// Picks the route the driver should be looking at (S12). Pure, so the
/// selection rules are unit-testable:
///  * cancelled routes never show;
///  * when [driver] is set, only that driver's routes count;
///  * routes dated [today] win, preferring ones still in motion
///    (Dispatched, then Draft, then Completed);
///  * with nothing dated today, fall back to the most recent route so the
///    screen still shows yesterday's unfinished run.
Document? selectTodayRoute(
  List<Document> routes, {
  String? driver,
  required String today,
}) {
  final candidates = [
    for (final r in routes)
      if ('${r.payload['status']}' != 'Cancelled' &&
          (driver == null || asNonEmpty(r.payload['driver']) == driver))
        r,
  ];
  if (candidates.isEmpty) return null;

  int liveliness(Document r) => switch ('${r.payload['status']}') {
        'Dispatched' => 0,
        'Draft' => 1,
        _ => 2,
      };

  final todays = [
    for (final r in candidates)
      if (asNonEmpty(r.payload['route_date']) == today) r,
  ]..sort((a, b) => liveliness(a).compareTo(liveliness(b)));
  if (todays.isNotEmpty) return todays.first;

  candidates.sort((a, b) => (asNonEmpty(b.payload['route_date']) ?? '')
      .compareTo(asNonEmpty(a.payload['route_date']) ?? ''));
  return candidates.first;
}

/// "Start route": every waiting stop (Pending/Loaded) goes Out for
/// Delivery and the route itself is Dispatched — one save, so the route
/// service emits one event per stop.
Future<void> startRoute(
  DocumentEngine engine,
  String routeId, {
  Set<String> roles = _systemRoles,
}) async {
  final route = await engine.fetch('Delivery Route', routeId);
  if (route == null) throw StateError('Delivery Route $routeId not found.');
  for (final stop in route.children['stops'] ?? const <ChildRow>[]) {
    final status = '${stop.payload['status']}';
    if (status == 'Pending' || status == 'Loaded') {
      stop.payload['status'] = 'Out for Delivery';
    }
  }
  route.payload['status'] = 'Dispatched';
  await engine.save(route, roles);
}
