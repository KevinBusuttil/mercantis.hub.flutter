import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/hub_feature.dart';
import '../settings/hub_settings.dart';
import '../team/team_session.dart';

/// Everything that shapes what the interface shows: the persisted settings
/// (business profile, optional features, Owner/Accountant view) plus whether
/// this device is connected to Atlas Team. Navigation, labels and reports are
/// pure functions of it, so the same engine and records sit underneath every
/// shape of the product.
class HubSurface {
  const HubSurface(this.settings, {this.teamConnected = false});

  final HubSettings settings;
  final bool teamConnected;

  bool has(HubFeature f) => settings.has(f);

  /// Ledgers, journals, audit, raw registers and detailed reports.
  bool get accountant => settings.showsAccountantSurfaces;

  /// Owner wording (Post invoice, Supplier bills, Money …) rather than the
  /// engine's own terms. A classic installation keeps the terms it had.
  bool get plainLanguage =>
      !settings.advancedMode && !settings.classicNavigation;

  bool get systemTools => settings.systemTools;

  bool allows(Requirement? r) => switch (r) {
        null => true,
        NeedsFeature(:final feature) => has(feature),
        NeedsAnyFeature(:final features) => features.any(has),
        NeedsAccountant() => accountant,
        NeedsTeam() => teamConnected,
        NeedsSystemTools() => systemTools,
      };

  /// Owner wording when [plainLanguage], otherwise the engine/ERP term.
  T say<T>(T plain, T engine) => plainLanguage ? plain : engine;
}

final hubSurfaceProvider = Provider<HubSurface>((ref) => HubSurface(
      ref.watch(hubSettingsProvider),
      teamConnected: ref.watch(teamSessionProvider) != null,
    ));
