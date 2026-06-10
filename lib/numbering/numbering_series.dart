import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

import '../manifest/hub_manifest.dart';

/// One configured naming series resolved to its current counter for this year.
class NumberingSeriesRow {
  const NumberingSeriesRow({
    required this.docType,
    required this.pattern,
    required this.seriesKey,
    required this.width,
    required this.nextNumber,
  });

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
  for (final dt in manifest.docTypes) {
    final patterns = <String>[
      if (dt.namingRule != null) dt.namingRule!,
      for (final r in dt.namingRules) r.series,
    ];
    for (final pattern in patterns) {
      if (!seen.add('${dt.id}|$pattern')) continue;
      final s = NamingSeriesStrategy.expandSeries(pattern);
      if (s == null) continue;
      final through = await _allocator.peek(db, s.prefix);
      rows.add(NumberingSeriesRow(
        docType: dt.name,
        pattern: pattern,
        seriesKey: s.prefix,
        width: s.width,
        nextNumber: through + 1,
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

  Future<void> setNextNumber(String seriesKey, int nextNumber) async {
    final mdb = await ref.read(mercantisDatabaseProvider.future);
    await _allocator.setNextNumber(mdb.db, seriesKey, nextNumber);
    ref.invalidate(numberingSeriesProvider);
  }
}
