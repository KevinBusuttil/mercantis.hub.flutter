import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mercantis_core/mercantis_core.dart';

/// Persisted Hub preferences (the Flutter analogue of the Swift
/// `HubVisibilitySettings`). Stored as a single `Hub Settings` document so it
/// survives restarts and rides the same sync engine as everything else.
class HubSettings {
  const HubSettings({
    this.advancedMode = false,
    this.posEnabled = true,
    this.manufacturingEnabled = true,
    this.deliveriesEnabled = true,
    this.operatorName = 'Kevin Busuttil',
    this.operatorEmail = 'kevin@mercantis.local',
  });

  final bool advancedMode;
  final bool posEnabled;
  final bool manufacturingEnabled;
  final bool deliveriesEnabled;
  final String operatorName;
  final String operatorEmail;

  static const docType = 'Hub Settings';
  static const docId = 'hub-settings';

  HubSettings copyWith({
    bool? advancedMode,
    bool? posEnabled,
    bool? manufacturingEnabled,
    bool? deliveriesEnabled,
    String? operatorName,
    String? operatorEmail,
  }) =>
      HubSettings(
        advancedMode: advancedMode ?? this.advancedMode,
        posEnabled: posEnabled ?? this.posEnabled,
        manufacturingEnabled: manufacturingEnabled ?? this.manufacturingEnabled,
        deliveriesEnabled: deliveriesEnabled ?? this.deliveriesEnabled,
        operatorName: operatorName ?? this.operatorName,
        operatorEmail: operatorEmail ?? this.operatorEmail,
      );

  Map<String, dynamic> toPayload() => {
        'advanced_mode': advancedMode,
        'pos_enabled': posEnabled,
        'manufacturing_enabled': manufacturingEnabled,
        'deliveries_enabled': deliveriesEnabled,
        'operator_name': operatorName,
        'operator_email': operatorEmail,
      };

  factory HubSettings.fromPayload(Map<String, dynamic> p) {
    bool flag(dynamic v, bool fallback) {
      if (v == null) return fallback;
      if (v is bool) return v;
      if (v is num) return v != 0;
      if (v is String) return v == '1' || v.toLowerCase() == 'true';
      return fallback;
    }

    String str(dynamic v, String fallback) =>
        (v is String && v.trim().isNotEmpty) ? v : fallback;

    const d = HubSettings();
    return HubSettings(
      advancedMode: flag(p['advanced_mode'], d.advancedMode),
      posEnabled: flag(p['pos_enabled'], d.posEnabled),
      manufacturingEnabled: flag(p['manufacturing_enabled'], d.manufacturingEnabled),
      deliveriesEnabled: flag(p['deliveries_enabled'], d.deliveriesEnabled),
      operatorName: str(p['operator_name'], d.operatorName),
      operatorEmail: str(p['operator_email'], d.operatorEmail),
    );
  }
}

/// Holds the live [HubSettings]. Hydrated once at boot from the singleton doc;
/// [save] persists changes and updates the in-memory state so dependents
/// (e.g. the current-user override) react immediately.
class HubSettingsNotifier extends Notifier<HubSettings> {
  static const _roles = {'System Manager'};

  @override
  HubSettings build() => const HubSettings();

  Future<void> hydrate(DocumentEngine engine) async {
    final doc = await engine.fetch(HubSettings.docType, HubSettings.docId);
    if (doc != null) state = HubSettings.fromPayload(doc.payload);
  }

  Future<void> save(DocumentEngine engine, HubSettings next) async {
    state = next;
    await engine.save(
      Document(id: HubSettings.docId, docType: HubSettings.docType, payload: next.toPayload()),
      _roles,
    );
  }
}

final hubSettingsProvider =
    NotifierProvider<HubSettingsNotifier, HubSettings>(HubSettingsNotifier.new);
