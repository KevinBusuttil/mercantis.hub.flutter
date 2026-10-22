import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart' show documentEngineProvider;

import '../features/hub_feature.dart';
import '../onboarding/business_preset.dart';

/// Owner / Accountant persona (HU6 — the Swift `HubUserMode`), persisted
/// through [HubSettings.advancedMode]. It shapes the interface: Owner gets
/// plain business terms, task-first navigation and summary reports;
/// Accountant adds the ledgers, journals, audit, detailed reports and posting
/// tools, in engine terminology. It never changes posting or permissions.
enum HubUserMode {
  owner,
  accountant;

  String get title => this == HubUserMode.owner ? 'Owner' : 'Accountant';

  String get blurb => this == HubUserMode.owner
      ? 'Plain business words and only what you use day to day: customers, '
          'quotes, invoices, money in and out, and summary reports. Ledgers '
          'and journals stay one switch away.'
      : 'Everything in Owner view plus accounts, journals, the audit trail, '
          'detailed reports, posting tools and engine terminology.';

  /// What the switch does and does not change — shown beside the choice so
  /// nobody mistakes a simpler view for a permission.
  static const disclaimer = 'Changing the view only changes what is shown. '
      'Posting rules, numbering and permissions are identical in both views.';
}

/// Persisted Hub preferences (the Flutter analogue of the Swift
/// `HubVisibilitySettings`). Stored as a single `Hub Settings` document so it
/// survives restarts and rides the same sync engine as everything else.
///
/// Defaults describe a **fresh installation**: no optional feature on, Owner
/// view, no operator identity. Onboarding then applies the chosen business
/// profile. Installations that predate this model are read through
/// [HubSettings.fromPayload]'s legacy rules so nothing they could reach
/// before disappears (see [HubSettings.legacy]).
class HubSettings {
  const HubSettings({
    this.advancedMode = false,
    this.features = const {},
    this.classicNavigation = false,
    this.systemTools = false,
    this.businessPresetId = '',
    this.operatorName = '',
    this.operatorEmail = '',
  });

  /// An installation from before feature gating: every optional feature on,
  /// the classic full navigation (accountant surfaces shown whatever the
  /// persona) and system configuration visible — exactly what it could reach
  /// before. The operator can opt in to the simplified surface in Settings.
  factory HubSettings.legacy({
    bool advancedMode = false,
    String businessPresetId = '',
    String operatorName = '',
    String operatorEmail = '',
  }) =>
      HubSettings(
        advancedMode: advancedMode,
        features: HubFeature.values.toSet(),
        classicNavigation: true,
        systemTools: true,
        businessPresetId: businessPresetId,
        operatorName: operatorName,
        operatorEmail: operatorEmail,
      );

  /// Payload schema version. Absent on documents written before feature
  /// gating — the signal [fromPayload] uses to apply the legacy rules.
  static const currentVersion = 2;

  /// Owner (false) or Accountant (true) view — see [userMode].
  final bool advancedMode;

  /// Optional business functions switched on for this installation.
  final Set<HubFeature> features;

  /// Pre-gating installations keep the full classic navigation — accountant
  /// sections included — until the operator opts in to the simplified one.
  final bool classicNavigation;

  /// Show developer / system configuration (DocTypes, workflows, custom
  /// fields, users and roles).
  final bool systemTools;

  /// The [BusinessPreset] id chosen at onboarding ('' before onboarding or on
  /// installs that predate presets).
  final String businessPresetId;
  final String operatorName;
  final String operatorEmail;

  static const docType = 'Hub Settings';
  static const docId = 'hub-settings';

  bool has(HubFeature f) {
    if (!features.contains(f)) return false;
    final dep = f.requires;
    return dep == null || features.contains(dep);
  }

  bool get stockEnabled => has(HubFeature.stock);
  bool get projectsEnabled => has(HubFeature.projects);
  bool get fieldServiceEnabled => has(HubFeature.fieldService);
  bool get appointmentsEnabled => has(HubFeature.appointments);
  bool get posEnabled => has(HubFeature.pos);
  bool get manufacturingEnabled => has(HubFeature.manufacturing);
  bool get deliveriesEnabled => has(HubFeature.deliveries);

  /// The Owner/Accountant persona this settings state represents (HU6).
  HubUserMode get userMode =>
      advancedMode ? HubUserMode.accountant : HubUserMode.owner;

  /// Whether ledgers, journals, audit and raw registers are on the navigation:
  /// the Accountant view, or a classic (pre-gating) installation. Presentation
  /// only — posting and permission rules are identical in both views.
  bool get showsAccountantSurfaces => advancedMode || classicNavigation;

  /// Returns a copy in the given persona (flips [advancedMode] accordingly).
  HubSettings withUserMode(HubUserMode mode) =>
      copyWith(advancedMode: mode == HubUserMode.accountant);

  /// Returns a copy with [feature] switched [on].
  HubSettings withFeature(HubFeature feature, bool on) => copyWith(
      features: on ? {...features, feature} : ({...features}..remove(feature)));

  /// Returns a copy with the optional features set from [preset] — the moment
  /// a preset stops being a cosmetic label. Choosing a profile also opts the
  /// installation in to the simplified, profile-shaped navigation.
  HubSettings applyingPreset(BusinessPreset preset) => copyWith(
        businessPresetId: preset.id,
        features: preset.features,
        classicNavigation: false,
      );

  HubSettings copyWith({
    bool? advancedMode,
    Set<HubFeature>? features,
    bool? classicNavigation,
    bool? systemTools,
    bool? stockEnabled,
    bool? projectsEnabled,
    bool? fieldServiceEnabled,
    bool? appointmentsEnabled,
    bool? posEnabled,
    bool? manufacturingEnabled,
    bool? deliveriesEnabled,
    String? businessPresetId,
    String? operatorName,
    String? operatorEmail,
  }) {
    final next = {...(features ?? this.features)};
    void set(HubFeature f, bool? on) {
      if (on == null) return;
      on ? next.add(f) : next.remove(f);
    }

    // Per-module flags kept for existing callers (setup packs, Settings).
    set(HubFeature.stock, stockEnabled);
    set(HubFeature.projects, projectsEnabled);
    set(HubFeature.fieldService, fieldServiceEnabled);
    set(HubFeature.appointments, appointmentsEnabled);
    set(HubFeature.pos, posEnabled);
    set(HubFeature.manufacturing, manufacturingEnabled);
    set(HubFeature.deliveries, deliveriesEnabled);
    return HubSettings(
      advancedMode: advancedMode ?? this.advancedMode,
      features: next,
      classicNavigation: classicNavigation ?? this.classicNavigation,
      systemTools: systemTools ?? this.systemTools,
      businessPresetId: businessPresetId ?? this.businessPresetId,
      operatorName: operatorName ?? this.operatorName,
      operatorEmail: operatorEmail ?? this.operatorEmail,
    );
  }

  Map<String, dynamic> toPayload() => {
        'settings_version': currentVersion,
        'advanced_mode': advancedMode,
        for (final f in HubFeature.values) f.key: features.contains(f),
        'classic_navigation': classicNavigation,
        'system_tools': systemTools,
        'business_preset': businessPresetId,
        'operator_name': operatorName,
        'operator_email': operatorEmail,
      };

  /// Whether [p] predates feature gating (no schema version recorded).
  static bool isLegacyPayload(Map<String, dynamic> p) =>
      p['settings_version'] == null;

  factory HubSettings.fromPayload(Map<String, dynamic> p) {
    bool? flag(dynamic v) {
      if (v == null) return null;
      if (v is bool) return v;
      if (v is num) return v != 0;
      if (v is String) {
        if (v.isEmpty) return null;
        return v == '1' || v.toLowerCase() == 'true';
      }
      return null;
    }

    String str(dynamic v) => v is String ? v : '';

    final legacy = isLegacyPayload(p);

    // Before gating, every module without a toggle was always visible, and a
    // toggled module defaulted to visible: a missing key on a legacy document
    // therefore means "on". Sections that lived inside a toggled module
    // follow it (tables/kitchen sat in the POS section; construction in
    // Projects). On a current document a missing key means "off".
    bool legacyDefault(HubFeature f) => switch (f) {
          HubFeature.hospitality => flag(p[HubFeature.pos.key]) ?? true,
          HubFeature.construction => flag(p[HubFeature.projects.key]) ?? true,
          _ => true,
        };

    return HubSettings(
      advancedMode: flag(p['advanced_mode']) ?? false,
      features: {
        for (final f in HubFeature.values)
          if (flag(p[f.key]) ?? (legacy && legacyDefault(f))) f,
      },
      classicNavigation: flag(p['classic_navigation']) ?? legacy,
      systemTools: flag(p['system_tools']) ?? legacy,
      businessPresetId: str(p['business_preset']),
      operatorName: str(p['operator_name']),
      operatorEmail: str(p['operator_email']),
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

  /// Loads the settings document. A fresh installation (no document, no
  /// company) keeps the minimal defaults for onboarding to shape. A pre-gating
  /// installation — a legacy document, or a company with no settings document
  /// at all — is migrated to an explicit current document that keeps every
  /// surface it had (see [HubSettings.legacy]); the migration is written once
  /// so later default changes can never silently hide anything.
  Future<void> hydrate(DocumentEngine engine) async {
    final doc = await engine.fetch(HubSettings.docType, HubSettings.docId);
    if (doc != null) {
      state = HubSettings.fromPayload(doc.payload);
      if (HubSettings.isLegacyPayload(doc.payload)) await save(engine, state);
      return;
    }
    final companies = await engine.list('Company', userRoles: _roles);
    if (companies.isEmpty) {
      state = const HubSettings();
      return;
    }
    await save(engine, HubSettings.legacy());
  }

  /// Saves [next] through the app's document engine — what screens call.
  Future<void> apply(HubSettings next) async =>
      save(await ref.read(documentEngineProvider.future), next);

  Future<void> save(DocumentEngine engine, HubSettings next) async {
    state = next;
    await engine.save(
      Document(
          id: HubSettings.docId,
          docType: HubSettings.docType,
          payload: next.toPayload()),
      _roles,
    );
  }
}

final hubSettingsProvider =
    NotifierProvider<HubSettingsNotifier, HubSettings>(HubSettingsNotifier.new);
