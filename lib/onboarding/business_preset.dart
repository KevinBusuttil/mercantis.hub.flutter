import '../features/hub_feature.dart';

/// A business shape chosen during onboarding. Ported from the Swift Hub's
/// `HubPreset`. All presets seed the same foundational data (chart of
/// accounts, fiscal year, tax codes, company); they differ in which optional
/// [HubFeature]s start switched on and in the phone's primary destinations.
/// The selection is persisted on `Hub Settings` (see
/// `HubSettings.applyingPreset`). Every other feature stays one switch away in
/// Settings › Features.
class BusinessPreset {
  const BusinessPreset({
    required this.id,
    required this.label,
    required this.description,
    this.features = const {},
    this.suggested = const [],
  });

  final String id;
  final String label;
  final String description;

  /// Optional features this profile starts with.
  final Set<HubFeature> features;

  /// Features commonly added to this profile — offered (unticked) during
  /// onboarding, never switched on by default.
  final List<HubFeature> suggested;

  bool get enablesStock => features.contains(HubFeature.stock);
  bool get enablesProjects => features.contains(HubFeature.projects);
  bool get enablesPos => features.contains(HubFeature.pos);
  bool get enablesDeliveries => features.contains(HubFeature.deliveries);
  bool get enablesManufacturing => features.contains(HubFeature.manufacturing);
  bool get enablesFieldService => features.contains(HubFeature.fieldService);
  bool get enablesAppointments => features.contains(HubFeature.appointments);

  /// Independent professionals and service firms: quotes, invoices, expenses
  /// and getting paid. No stock, till or specialist verticals by default.
  static const services = BusinessPreset(
    id: 'services',
    label: 'Services',
    description: 'Quotes, invoices, expenses and getting paid. Add projects, '
        'appointments or field jobs whenever you need them.',
    suggested: [
      HubFeature.projects,
      HubFeature.appointments,
      HubFeature.fieldService,
      HubFeature.salesPipeline,
    ],
  );

  static const trade = BusinessPreset(
    id: 'trade',
    label: 'Trade / Distribution',
    description: 'Buy, stock and sell goods — stock control, deliveries and '
        'goods received, with stock valuation and margins.',
    features: {HubFeature.stock},
    suggested: [
      HubFeature.deliveries,
      HubFeature.salesPipeline,
      HubFeature.onlineChannels,
    ],
  );

  static const retail = BusinessPreset(
    id: 'retail',
    label: 'Retail / Shop',
    description: 'Sell over the counter — a one-device till with stock '
        'control. Fiscal-receipt approval depends on your country.',
    features: {HubFeature.stock, HubFeature.pos},
    suggested: [HubFeature.onlineChannels, HubFeature.hospitality],
  );

  static const manufacturing = BusinessPreset(
    id: 'manufacturing',
    label: 'Light Manufacturing',
    description: 'Make and sell products — stock control, bills of materials '
        'and work orders.',
    features: {HubFeature.stock, HubFeature.manufacturing},
    suggested: [HubFeature.deliveries],
  );

  static const mixed = BusinessPreset(
    id: 'mixed',
    label: 'Mixed Small Business',
    description: 'A bit of everything — starts with stock control and '
        'projects; add the till, manufacturing or deliveries from Settings '
        'as you need them.',
    features: {HubFeature.stock, HubFeature.projects},
    suggested: [HubFeature.pos, HubFeature.deliveries],
  );

  static const all = [services, trade, retail, manufacturing, mixed];

  /// The preset with [id], or [services] when unknown/blank (safe default:
  /// the least surface area).
  static BusinessPreset byId(String? id) => all.firstWhere(
        (p) => p.id == id,
        orElse: () => services,
      );
}
