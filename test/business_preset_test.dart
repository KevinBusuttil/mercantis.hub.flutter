import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_hub_app/onboarding/business_preset.dart';
import 'package:mercantis_hub_app/settings/hub_settings.dart';
import 'package:mercantis_hub_app/workspaces/hub_workspaces.dart';

/// Presets are functional, not cosmetic: applying one sets the module
/// toggles, which in turn decide which workspaces (and the POS surfaces
/// inside Sales) exist at all.
void main() {
  Set<String> workspaceIds(HubSettings s) =>
      hubWorkspaces(s).map((w) => w.id).toSet();

  bool salesHasPos(HubSettings s) {
    final sales =
        hubWorkspaces(s).firstWhere((w) => w.id == 'sales_fulfilment');
    final hasSection =
        sales.sections.any((sec) => sec.label == 'Point of Sale');
    final hasAction = sales.quickActions.any((a) => a.id == 'sf_pos_till');
    expect(hasSection, hasAction); // section and action move together
    return hasSection;
  }

  test('services preset hides stock, POS, manufacturing and deliveries', () {
    final s = const HubSettings().applyingPreset(BusinessPreset.services);
    expect(s.businessPresetId, 'services');
    final ids = workspaceIds(s);
    expect(ids, isNot(contains('inventory')));
    expect(ids, isNot(contains('manufacturing')));
    expect(ids, isNot(contains('delivery')));
    expect(salesHasPos(s), isFalse);
    // The service business still sells, buys, and reports.
    expect(ids, containsAll(['home', 'sales_fulfilment', 'purchasing', 'finance', 'reports']));
  });

  test('trade preset enables stock and deliveries, not POS/manufacturing', () {
    final s = const HubSettings().applyingPreset(BusinessPreset.trade);
    final ids = workspaceIds(s);
    expect(ids, contains('inventory'));
    expect(ids, contains('delivery'));
    expect(ids, isNot(contains('manufacturing')));
    expect(salesHasPos(s), isFalse);
  });

  test('retail preset enables stock and POS', () {
    final s = const HubSettings().applyingPreset(BusinessPreset.retail);
    final ids = workspaceIds(s);
    expect(ids, contains('inventory'));
    expect(salesHasPos(s), isTrue);
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
  });

  test('pre-preset installs (blank preset id) keep every module visible', () {
    const s = HubSettings(); // defaults: everything on, no preset recorded
    final ids = workspaceIds(s);
    expect(ids, containsAll(['inventory', 'manufacturing', 'delivery']));
    expect(salesHasPos(s), isTrue);
  });

  test('byId falls back to services for unknown ids', () {
    expect(BusinessPreset.byId('nope').id, 'services');
    expect(BusinessPreset.byId(null).id, 'services');
    expect(BusinessPreset.byId('mixed').enablesStock, isTrue);
  });
}
