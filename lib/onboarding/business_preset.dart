/// A business shape chosen during onboarding. Ported from the Swift Hub's
/// `HubPreset`. All presets seed the same foundational data (chart of
/// accounts, fiscal year, tax codes, company); they differ in which optional
/// modules the product shows. The selection is persisted on `Hub Settings`
/// (see `HubSettings.applyingPreset`) and drives workspace visibility — a
/// Services business never sees Stock, POS, Manufacturing or Deliveries
/// unless it enables them later from Settings.
class BusinessPreset {
  const BusinessPreset({
    required this.id,
    required this.label,
    required this.description,
    this.enablesStock = false,
    this.enablesProjects = false,
    this.enablesPos = false,
    this.enablesDeliveries = false,
    this.enablesManufacturing = false,
    this.enablesFieldService = false,
  });

  final String id;
  final String label;
  final String description;
  final bool enablesStock;
  final bool enablesProjects;
  final bool enablesPos;
  final bool enablesDeliveries;
  final bool enablesManufacturing;
  final bool enablesFieldService;

  static const services = BusinessPreset(
    id: 'services',
    label: 'Services',
    description: 'Quotes, invoices, projects and time tracking. No '
        'stock-heavy extras.',
    enablesProjects: true,
    enablesFieldService: true,
  );

  static const trade = BusinessPreset(
    id: 'trade',
    label: 'Trade / Distribution',
    description: 'Buy, stock, and deliver goods — adds stock control and '
        'delivery routes.',
    enablesStock: true,
    enablesDeliveries: true,
    enablesFieldService: true,
  );

  static const retail = BusinessPreset(
    id: 'retail',
    label: 'Retail / POS',
    description: 'Sell over the counter — adds stock control and the '
        'point-of-sale till.',
    enablesStock: true,
    enablesPos: true,
  );

  static const manufacturing = BusinessPreset(
    id: 'manufacturing',
    label: 'Light Manufacturing',
    description: 'Make and sell products — adds stock control, BOMs and '
        'work orders.',
    enablesStock: true,
    enablesManufacturing: true,
  );

  static const mixed = BusinessPreset(
    id: 'mixed',
    label: 'Mixed Small Business',
    description: 'A bit of everything — starts with stock control and '
        'projects; enable POS, manufacturing or deliveries from Settings as '
        'you need them.',
    enablesStock: true,
    enablesProjects: true,
  );

  static const all = [services, trade, retail, manufacturing, mixed];

  /// The preset with [id], or [services] when unknown/blank (safe default:
  /// the least surface area).
  static BusinessPreset byId(String? id) => all.firstWhere(
        (p) => p.id == id,
        orElse: () => services,
      );
}
