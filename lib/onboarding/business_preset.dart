/// A business shape chosen during onboarding. Ported from the Swift Hub's
/// `HubPreset`. All presets seed the same foundational data (chart of accounts,
/// fiscal year, tax codes, company); they differ only in which optional modules
/// they would enable. POS / Manufacturing / full Deliveries are not yet ported,
/// so those flags are recorded for forward-compatibility but have no effect yet.
class BusinessPreset {
  const BusinessPreset({
    required this.id,
    required this.label,
    required this.description,
    this.enablesPos = false,
    this.enablesDeliveries = false,
    this.enablesManufacturing = false,
  });

  final String id;
  final String label;
  final String description;
  final bool enablesPos;
  final bool enablesDeliveries;
  final bool enablesManufacturing;

  static const services = BusinessPreset(
    id: 'services',
    label: 'Services',
    description: 'Quotes, invoices, and payments. No stock-heavy extras.',
  );

  static const trade = BusinessPreset(
    id: 'trade',
    label: 'Trade / Distribution',
    description: 'Buy, stock, and deliver goods — adds delivery routes.',
    enablesDeliveries: true,
  );

  static const retail = BusinessPreset(
    id: 'retail',
    label: 'Retail / POS',
    description: 'Sell over the counter — adds the point-of-sale till.',
    enablesPos: true,
  );

  static const manufacturing = BusinessPreset(
    id: 'manufacturing',
    label: 'Light Manufacturing',
    description: 'Make and sell products — adds BOMs and work orders.',
    enablesManufacturing: true,
  );

  static const all = [services, trade, retail, manufacturing];
}
