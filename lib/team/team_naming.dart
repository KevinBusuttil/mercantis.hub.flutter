import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

import 'team_session.dart';

/// Device-unique document ids for Atlas Team.
///
/// Naming-series counters (`SINV-.YYYY.-.####`) live in each device's own
/// database, so two Team devices both mint `SINV-.2026.-0001`. Both drafts
/// then land in the company log under one id: the second silently replaces
/// the first, and when both are posted the server sees one document (the
/// second submit replays the first). The multi-device test against the real
/// backend caught exactly that.
///
/// While connected to Team, a series id therefore carries this device's tag
/// before its counter: `SINV-.2026.-3FA2C1-0001`. The official number is
/// still the server's (`SINV-00001`); this id only has to be unique.
///
/// Not tagged: POS receipts (the till series already makes them unique per
/// register, and the receipt id is the fiscal number), explicit ids, and
/// non-series names (uuid, field-derived). Solo is untouched.
class TeamScopedNamingService extends NamingService {
  TeamScopedNamingService(this.deviceTag);

  /// This device's tag while connected to Team, else null.
  final String? Function() deviceTag;

  @override
  Future<String> resolve(
      DocType docType, Document document, NamingContext context) async {
    final id = await super.resolve(docType, document, context);
    final tag = deviceTag();
    if (tag == null || document.docType == 'POS Invoice') return id;
    if (!_usesSeries(docType)) return id;
    return teamScopedId(id, tag);
  }

  static bool _usesSeries(DocType docType) =>
      (docType.namingRule ?? '').contains('#') ||
      docType.namingRules.any((r) => r.series.contains('#'));
}

/// [id] with [tag] inserted before its trailing counter; unchanged when it
/// has no trailing counter.
String teamScopedId(String id, String tag) {
  final m = RegExp(r'^(.*?)(\d+)$').firstMatch(id);
  if (m == null) return id;
  return '${m.group(1)}$tag-${m.group(2)}';
}

/// A short, stable tag for a Team device: the first six hex digits of its
/// server-issued id, upper-cased.
String teamDeviceTag(String deviceId) {
  final hex = deviceId.replaceAll(RegExp(r'[^0-9A-Fa-f]'), '');
  return (hex.length >= 6 ? hex.substring(0, 6) : hex).toUpperCase();
}

/// Reads the live Team session at call time, like the posting guard.
final teamScopedNamingOverride = namingServiceProvider.overrideWith((ref) =>
    TeamScopedNamingService(() {
      final session = ref.read(teamSessionProvider);
      return session == null ? null : teamDeviceTag(session.deviceId);
    }));
