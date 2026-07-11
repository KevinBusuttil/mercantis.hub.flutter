import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

/// Conflict visibility (Phase 0.10, gap analysis §8-C6): the service that
/// lists documents stuck in `sync_state=conflict` and resolves them
/// keep-mine / take-theirs. Same identity as the document engine, so a
/// keep-mine re-push is attributed to this device and operator.
final conflictServiceProvider = FutureProvider<ConflictService>((ref) async {
  final db = (await ref.watch(mercantisDatabaseProvider.future)).db;
  final registry = await ref.watch(metadataRegistryProvider.future);
  final deviceId = await ref.watch(deviceIdProvider.future);
  final engine = SyncEngine(database: db, registry: registry);
  ref.onDispose(engine.dispose);
  return ConflictService(
    database: db,
    syncEngine: engine,
    deviceId: deviceId,
    userId: 'local-user',
  );
});

/// The open conflicts, newest first. Invalidate after resolving one.
final syncConflictsProvider = FutureProvider<List<SyncConflict>>(
    (ref) async =>
        (await ref.watch(conflictServiceProvider.future)).listConflicts());

/// Just the count — for the warning chip on the Team screen's sync card.
final conflictCountProvider = FutureProvider<int>(
    (ref) async => (await ref.watch(conflictServiceProvider.future)).count());
