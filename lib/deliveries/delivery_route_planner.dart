/// Pure decisions behind the delivery-route status log (ported from the Swift
/// `DeliveryRoutePlanner`). Kept database-free so they're trivially testable.
abstract final class DeliveryRoutePlanner {
  /// A status event is appended only when a stop's status actually changes from
  /// the last recorded status for that stop.
  static bool shouldEmitEvent({String? lastStatus, required String current}) =>
      lastStatus != current;

  /// Deterministic id for a stop's nth status event, so re-firing the route's
  /// save event upserts in place rather than duplicating.
  static String eventId({
    required String routeId,
    required int sequence,
    required int existingCount,
  }) =>
      'DSE-$routeId-$sequence-$existingCount';
}
