import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

import '../manifest/hub_manifest.dart';
import 'numbering_recovery.dart';

/// One configured naming series resolved to its current counter for this year.
class NumberingSeriesRow {
  const NumberingSeriesRow({
    required this.docType,
    required this.pattern,
    required this.seriesKey,
    required this.width,
    required this.nextNumber,
    this.onHold = false,
    this.official = false,
  });

  /// New numbers are refused until the recovery decision (after a restore).
  final bool onHold;

  /// A business-facing series ([officialNumberingDocTypes]).
  final bool official;

  /// Human DocType name (e.g. 'Sales Invoice').
  final String docType;

  /// The raw pattern from the manifest (e.g. 'SINV-.YYYY.-.####').
  final String pattern;

  /// The resolved counter key the allocator sequences on (e.g. 'SINV-.2026.-').
  final String seriesKey;

  /// Zero-pad width of the counter.
  final int width;

  /// The next number this series will mint.
  final int nextNumber;

  /// A preview of the next id this series would produce.
  String get sample =>
      '$seriesKey${nextNumber.toString().padLeft(width, '0')}';
}

const _allocator = CounterBlockAllocator();

/// Every counter-bearing naming series across the Hub manifest, resolved to its
/// current next number. Read directly from the engine's allocator tables, so it
/// reflects exactly what the next save will mint. Patterns without a `#`
/// counter (fixed or field-derived names) are skipped.
final numberingSeriesProvider =
    FutureProvider<List<NumberingSeriesRow>>((ref) async {
  final mdb = await ref.watch(mercantisDatabaseProvider.future);
  final db = mdb.db;
  final manifest = HubManifest.build();

  final rows = <NumberingSeriesRow>[];
  final seen = <String>{};
  // What each series has actually issued (not the reserved block end).
  final issued = await _allocator.issuedThrough(db);
  for (final dt in manifest.docTypes) {
    final patterns = <String>[
      if (dt.namingRule != null) dt.namingRule!,
      for (final r in dt.namingRules) r.series,
    ];
    for (final pattern in patterns) {
      if (!seen.add('${dt.id}|$pattern')) continue;
      final s = NamingSeriesStrategy.expandSeries(pattern);
      if (s == null) continue;
      // A recovery series (after a restore) continues under its own key.
      final policy = await NamingSeriesPolicyStore.read(db, dt.name);
      final key = policy?.apply(s.prefix) ?? s.prefix;
      rows.add(NumberingSeriesRow(
        docType: dt.name,
        pattern: pattern,
        seriesKey: key,
        width: s.width,
        nextNumber: (issued[key] ?? 0) + 1,
        onHold: policy?.hold ?? false,
        official: officialNumberingDocTypes.contains(dt.name),
      ));
    }
  }
  rows.sort((a, b) => a.docType.compareTo(b.docType));
  return rows;
});

/// Force a series' next number (legacy migration / year-start reset), then
/// refresh the list.
final numberingSeriesControllerProvider =
    Provider<NumberingSeriesController>(NumberingSeriesController.new);

class NumberingSeriesController {
  NumberingSeriesController(this.ref);
  final Ref ref;

  /// Move a series forward. Lowering it below a number already issued is
  /// refused: that is exactly how a number gets issued twice (R3).
  Future<void> setNextNumber(String seriesKey, int nextNumber) async {
    final mdb = await ref.read(mercantisDatabaseProvider.future);
    final issued = (await _allocator.issuedThrough(mdb.db))[seriesKey] ?? 0;
    if (nextNumber <= issued) {
      throw ArgumentError('$seriesKey has already issued number $issued. The '
          'next number must be ${issued + 1} or more, so no number is '
          'issued twice.');
    }
    await _allocator.setNextNumber(mdb.db, seriesKey, nextNumber);
    await NumberingRecovery.recordManualChange(mdb.db, seriesKey, nextNumber,
        userId: currentOperatorId(ref),
        deviceId: await ref.read(deviceIdProvider.future));
    ref.invalidate(numberingSeriesProvider);
    ref.invalidate(numberingPolicyProvider);
  }

  Future<void> confirmLastIssued(Map<String, int> lastIssued) async {
    final mdb = await ref.read(mercantisDatabaseProvider.future);
    await NumberingRecovery.confirmLastIssued(mdb.db, lastIssued,
        userId: currentOperatorId(ref),
        deviceId: await ref.read(deviceIdProvider.future));
    ref.invalidate(numberingSeriesProvider);
    ref.invalidate(numberingPolicyProvider);
  }

  Future<String> startRecoverySeries() async {
    final mdb = await ref.read(mercantisDatabaseProvider.future);
    final segment = await NumberingRecovery.startRecoverySeries(mdb.db,
        userId: currentOperatorId(ref),
        deviceId: await ref.read(deviceIdProvider.future));
    ref.invalidate(numberingSeriesProvider);
    ref.invalidate(numberingPolicyProvider);
    return segment;
  }
}

/// The numbering policy in force, for the screen's banner.
final numberingPolicyProvider = FutureProvider<
    ({List<NamingSeriesPolicy> holds, String? segment})>((ref) async {
  final mdb = await ref.watch(mercantisDatabaseProvider.future);
  return (
    holds: await NumberingRecovery.holds(mdb.db),
    segment: await NumberingRecovery.activeSegment(mdb.db),
  );
});

String currentOperatorId(Ref ref) {
  try {
    return ref.read(currentUserProvider).id;
  } catch (_) {
    return 'operator';
  }
}
