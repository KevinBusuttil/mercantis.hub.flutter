import 'dart:convert';

import 'package:crypto/crypto.dart';

/// A versioned, declarative, composable setup bundle
/// (ATLAS_SETUP_LIBRARY_AND_RULE_FIRST_AI.md §2). A pack configures Atlas
/// for a business shape by contributing masters (accounts, tax codes,
/// items…), company default accounts, module toggles, and deterministic
/// rules — all mapped onto machinery that already exists. Applying is
/// idempotent and produces a recorded diff (see SetupPackApplier).
///
/// Packs travel as JSON bundles. `integritySha256` covers the canonical
/// JSON of everything except itself, so a downloaded or side-loaded bundle
/// is tamper-evident today; the `signature` field is reserved in the format
/// for the signed-catalogue step (Ed25519 over the same bytes) so bundles
/// created now stay valid then.
class SetupPack {
  const SetupPack({
    required this.id,
    required this.name,
    required this.version,
    this.description = '',
    this.dependsOn = const [],
    this.conflictsWith = const [],
    this.masters = const [],
    this.companyDefaults = const {},
    this.moduleToggles = const {},
    this.rules = const [],
  });

  final String id;
  final String name;

  /// Semantic version, e.g. `1.0.0`. Re-applying the same version is a
  /// recorded no-op; a higher version applies as an upgrade.
  final String version;
  final String description;
  final List<String> dependsOn;
  final List<String> conflictsWith;

  /// Documents to ensure exist: `{doctype, id, payload}`. Ensure-if-absent —
  /// a pack never overwrites documents the user already has (that would be
  /// silent data loss); an existing id is recorded as skipped.
  final List<PackMaster> masters;

  /// Company default-account keys to fill IF BLANK (e.g.
  /// `default_inventory_account` → `Stock`).
  final Map<String, String> companyDefaults;

  /// Module visibility this pack implies (e.g. `stock: true`). Returned to
  /// the caller to apply through HubSettings — settings live in their own
  /// persistence, not in the applier.
  final Map<String, bool> moduleToggles;

  /// Deterministic Setup Rule payloads this pack contributes; saved with
  /// provenance `built-in` and `source_pack` stamped.
  final List<Map<String, dynamic>> rules;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'version': version,
        'description': description,
        'depends_on': dependsOn,
        'conflicts_with': conflictsWith,
        'masters': [for (final m in masters) m.toJson()],
        'company_defaults': companyDefaults,
        'module_toggles': moduleToggles,
        'rules': rules,
      };

  factory SetupPack.fromJson(Map<String, dynamic> json) => SetupPack(
        id: json['id'] as String,
        name: json['name'] as String,
        version: json['version'] as String,
        description: '${json['description'] ?? ''}',
        dependsOn: [for (final d in json['depends_on'] ?? []) '$d'],
        conflictsWith: [for (final c in json['conflicts_with'] ?? []) '$c'],
        masters: [
          for (final m in json['masters'] ?? [])
            PackMaster.fromJson(Map<String, dynamic>.from(m as Map)),
        ],
        companyDefaults: {
          for (final e in ((json['company_defaults'] ?? {}) as Map).entries)
            '${e.key}': '${e.value}',
        },
        moduleToggles: {
          for (final e in ((json['module_toggles'] ?? {}) as Map).entries)
            '${e.key}': e.value == true,
        },
        rules: [
          for (final r in json['rules'] ?? [])
            Map<String, dynamic>.from(r as Map),
        ],
      );

  /// The canonical content hash a bundle's `integritySha256` must match.
  String contentSha256() =>
      sha256.convert(utf8.encode(jsonEncode(toJson()))).toString();

  /// Serialises the pack as a distributable bundle (pack + integrity hash).
  String toBundleJson() => jsonEncode({
        'pack': toJson(),
        'integritySha256': contentSha256(),
      });

  /// Parses a bundle, verifying its integrity hash. Throws [FormatException]
  /// on tamper or corruption — a damaged setup bundle must never half-apply.
  static SetupPack fromBundleJson(String bundle) {
    final decoded = jsonDecode(bundle);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('not a setup pack bundle');
    }
    final pack = SetupPack.fromJson(
        Map<String, dynamic>.from(decoded['pack'] as Map));
    final claimed = '${decoded['integritySha256'] ?? ''}';
    if (claimed != pack.contentSha256()) {
      throw const FormatException(
          'setup pack integrity check failed — the bundle was modified or '
          'corrupted in transit');
    }
    return pack;
  }
}

/// One document a pack ensures exists.
class PackMaster {
  const PackMaster({
    required this.docType,
    required this.id,
    required this.payload,
  });

  final String docType;
  final String id;
  final Map<String, dynamic> payload;

  Map<String, dynamic> toJson() =>
      {'doctype': docType, 'id': id, 'payload': payload};

  factory PackMaster.fromJson(Map<String, dynamic> json) => PackMaster(
        docType: json['doctype'] as String,
        id: json['id'] as String,
        payload: Map<String, dynamic>.from(json['payload'] as Map),
      );
}
