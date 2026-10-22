import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';
import 'package:mercantis_hub_app/features/hub_feature.dart';
import 'package:mercantis_hub_app/navigation/hub_surface.dart';
import 'package:mercantis_hub_app/onboarding/business_preset.dart';
import 'package:mercantis_hub_app/settings/hub_settings.dart';
import 'package:mercantis_hub_app/workspaces/hub_workspaces.dart';

/// Presets are functional, not cosmetic: applying one sets the feature
/// catalogue, which in turn decides which workspaces (and the till surfaces
/// inside Sales) exist at all.
void main() {
  Set<String> workspaceIds(HubSettings s) =>
      hubWorkspaces(HubSurface(s)).map((w) => w.id).toSet();

  bool salesHasPos(HubSettings s) {
    final sales = hubWorkspaces(HubSurface(s))
        .firstWhere((w) => w.id == 'sales_fulfilment');
    final hasSection = sales.sections.any((sec) =>
        sec.items.any((i) => i is CustomWorkspaceItem && i.routeName == 'pos-till'));
    final hasAction = sales.quickActions.any((a) => a.id == 'sf_pos_till');
    expect(hasSection, hasAction); // section and action move together
    return hasSection;
  }

  test('services preset turns on no optional feature', () {
    final s = const HubSettings().applyingPreset(BusinessPreset.services);
    expect(s.businessPresetId, 'services');
    expect(s.features, isEmpty);
    final ids = workspaceIds(s);
    for (final hidden in [
      'inventory', 'manufacturing', 'delivery', 'projects', 'field_service',
      'appointments', 'approvals',
    ]) {
      expect(ids, isNot(contains(hidden)), reason: hidden);
    }
    expect(salesHasPos(s), isFalse);
    // The service business still sells, buys, and gets paid.
    expect(ids, containsAll(['home', 'sales_fulfilment', 'purchasing', 'finance']));
  });

  test('trade preset enables stock only; deliveries are a suggestion', () {
    final s = const HubSettings().applyingPreset(BusinessPreset.trade);
    final ids = workspaceIds(s);
    expect(ids, contains('inventory'));
    expect(ids, isNot(contains('delivery')));
    expect(ids, isNot(contains('field_service')));
    expect(ids, isNot(contains('manufacturing')));
    expect(salesHasPos(s), isFalse);
    expect(BusinessPreset.trade.suggested, contains(HubFeature.deliveries));
  });

  test('retail preset enables stock and the till', () {
    final s = const HubSettings().applyingPreset(BusinessPreset.retail);
    final ids = workspaceIds(s);
    expect(ids, contains('inventory'));
    expect(salesHasPos(s), isTrue);
    expect(s.has(HubFeature.hospitality), isFalse);
    expect(ids, isNot(contains('manufacturing')));
    expect(ids, isNot(contains('delivery')));
  });

  test('manufacturing preset enables stock and manufacturing', () {
    final s = const HubSettings().applyingPreset(BusinessPreset.manufacturing);
    final ids = workspaceIds(s);
    expect(ids, containsAll(['inventory', 'manufacturing']));
    expect(salesHasPos(s), isFalse);
  });

  test('preset choice round-trips through the settings payload', () {
    final s = const HubSettings().applyingPreset(BusinessPreset.retail);
    final restored = HubSettings.fromPayload(s.toPayload());
    expect(restored.businessPresetId, 'retail');
    expect(restored.stockEnabled, isTrue);
    expect(restored.posEnabled, isTrue);
    expect(restored.manufacturingEnabled, isFalse);
    expect(restored.deliveriesEnabled, isFalse);
    expect(restored.classicNavigation, isFalse);
  });

  test('pre-preset installs keep every module visible', () {
    final s = HubSettings.legacy();
    final ids = workspaceIds(s);
    expect(ids, containsAll(['inventory', 'manufacturing', 'delivery',
        'projects', 'field_service', 'appointments']));
    expect(salesHasPos(s), isTrue);
  });

  test('byId falls back to services for unknown ids', () {
    expect(BusinessPreset.byId('nope').id, 'services');
    expect(BusinessPreset.byId(null).id, 'services');
    expect(BusinessPreset.byId('mixed').enablesStock, isTrue);
  });
}
