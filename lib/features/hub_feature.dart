import 'package:flutter/material.dart';

/// Optional business functions — the feature/module catalogue. Each one is
/// switched per installation (Settings › Features) and decides whether its
/// workspaces, sections, items, quick actions and routes are shown.
///
/// Hiding a feature is presentation only: its DocTypes, records, services and
/// postings are untouched, and its records stay reachable by link and search
/// of the record lists. Visibility is never a security boundary.
enum HubFeature {
  stock(
    key: 'stock_enabled',
    label: 'Stock & warehouses',
    description: 'Stocked items, stock movements, counts, deliveries and goods '
        'received, with stock valuation and gross margin.',
    icon: Icons.inventory_2_outlined,
    group: HubFeatureGroup.operations,
  ),
  pos(
    key: 'pos_enabled',
    label: 'Point of sale (till)',
    description: 'A one-device till for over-the-counter sales with Z-reports. '
        'Fiscal-receipt certification is jurisdiction-specific and is not '
        'implied by turning this on.',
    icon: Icons.point_of_sale_outlined,
    group: HubFeatureGroup.selling,
  ),
  hospitality(
    key: 'hospitality_enabled',
    label: 'Tables & kitchen',
    description: 'Floor map, tabs, kitchen tickets and the void & comp audit, '
        'on top of the till.',
    icon: Icons.table_bar_outlined,
    group: HubFeatureGroup.verticals,
  ),
  salesPipeline(
    key: 'sales_pipeline_enabled',
    label: 'Leads & opportunities',
    description: 'Track prospects before they become customers.',
    icon: Icons.flag_outlined,
    group: HubFeatureGroup.selling,
  ),
  projects(
    key: 'projects_enabled',
    label: 'Projects & time',
    description: 'Projects, tasks, timesheets and billable expenses, billed '
        'from the project.',
    icon: Icons.work_outline,
    group: HubFeatureGroup.services,
  ),
  appointments(
    key: 'appointments_enabled',
    label: 'Appointments',
    description: 'Front-desk booking with deposits, a resource calendar and '
        'staff commissions.',
    icon: Icons.event_available_outlined,
    group: HubFeatureGroup.services,
  ),
  fieldService(
    key: 'field_service_enabled',
    label: 'Field service',
    description: 'Service requests, jobs, dispatch, technician day view and '
        'maintenance contracts.',
    icon: Icons.home_repair_service_outlined,
    group: HubFeatureGroup.services,
  ),
  deliveries(
    key: 'deliveries_enabled',
    label: 'Delivery routes',
    description: 'Routes, drivers, vehicles and proof of delivery.',
    icon: Icons.local_shipping_outlined,
    group: HubFeatureGroup.operations,
  ),
  manufacturing(
    key: 'manufacturing_enabled',
    label: 'Manufacturing',
    description: 'Bills of materials, work orders and production.',
    icon: Icons.precision_manufacturing_outlined,
    group: HubFeatureGroup.operations,
  ),
  onlineChannels(
    key: 'online_channels_enabled',
    label: 'Online store orders',
    description: 'Import storefront orders for review and posting. In Solo, '
        'imports are manual or polled while the app runs.',
    icon: Icons.storefront_outlined,
    group: HubFeatureGroup.selling,
  ),
  memberships(
    key: 'memberships_enabled',
    label: 'Memberships',
    description: 'Plans whose fees bill themselves.',
    icon: Icons.card_membership_outlined,
    group: HubFeatureGroup.verticals,
  ),
  rentals(
    key: 'rentals_enabled',
    label: 'Rentals / hire',
    description: 'Hire out units with availability, deposits and day billing.',
    icon: Icons.handshake_outlined,
    group: HubFeatureGroup.verticals,
  ),
  property(
    key: 'property_enabled',
    label: 'Property & tenancies',
    description: 'Properties, leases and a rent roll whose rent bills itself.',
    icon: Icons.apartment_outlined,
    group: HubFeatureGroup.verticals,
  ),
  construction(
    key: 'construction_enabled',
    label: 'Construction contracts',
    description: 'Interim valuations billed less retention.',
    icon: Icons.engineering_outlined,
    group: HubFeatureGroup.verticals,
  ),
  fixedAssets(
    key: 'fixed_assets_enabled',
    label: 'Fixed assets',
    description: 'An asset register with depreciation runs.',
    icon: Icons.precision_manufacturing_outlined,
    group: HubFeatureGroup.finance,
  );

  const HubFeature({
    required this.key,
    required this.label,
    required this.description,
    required this.icon,
    required this.group,
  });

  /// Payload key on the `Hub Settings` document.
  final String key;
  final String label;
  final String description;
  final IconData icon;
  final HubFeatureGroup group;

  /// Features that only make sense on top of another (e.g. tables need the
  /// till). Turning the dependency off hides the dependant too.
  HubFeature? get requires => switch (this) {
        HubFeature.hospitality => HubFeature.pos,
        _ => null,
      };
}

enum HubFeatureGroup {
  selling('Selling'),
  services('Services'),
  operations('Stock & operations'),
  finance('Finance'),
  verticals('Specialist');

  const HubFeatureGroup(this.label);
  final String label;
}

/// How a navigation entry is gated. Essential functions have no requirement;
/// the rest need an optional feature, the Accountant view, Atlas Team or the
/// system-configuration toggle.
sealed class Requirement {
  const Requirement();
}

class NeedsFeature extends Requirement {
  const NeedsFeature(this.feature);
  final HubFeature feature;
}

/// Any of several features (e.g. the schedule serves appointments and field
/// service alike).
class NeedsAnyFeature extends Requirement {
  const NeedsAnyFeature(this.features);
  final List<HubFeature> features;
}

/// Accountant / advanced functions: ledgers, journals, audit, raw registers.
class NeedsAccountant extends Requirement {
  const NeedsAccountant();
}

/// Multi-user functions that only mean something with Atlas Team connected.
class NeedsTeam extends Requirement {
  const NeedsTeam();
}

/// Developer / system configuration (DocTypes, workflows, custom fields).
class NeedsSystemTools extends Requirement {
  const NeedsSystemTools();
}
