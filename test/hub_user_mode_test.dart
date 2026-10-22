import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_hub_app/features/hub_feature.dart';
import 'package:mercantis_hub_app/settings/hub_settings.dart';

/// HU6 — the Owner/Accountant persona is a façade over advancedMode.
void main() {
  test('Owner ⇔ advanced off, Accountant ⇔ advanced on', () {
    expect(const HubSettings(advancedMode: false).userMode, HubUserMode.owner);
    expect(const HubSettings(advancedMode: true).userMode, HubUserMode.accountant);
  });

  test('withUserMode flips advancedMode without touching other settings', () {
    const base = HubSettings(advancedMode: false, features: {HubFeature.stock});
    final acc = base.withUserMode(HubUserMode.accountant);
    expect(acc.advancedMode, isTrue);
    expect(acc.userMode, HubUserMode.accountant);
    expect(acc.features, {HubFeature.stock}); // unrelated setting preserved
    expect(acc.posEnabled, isFalse);

    final owner = acc.withUserMode(HubUserMode.owner);
    expect(owner.advancedMode, isFalse);
    expect(owner.userMode, HubUserMode.owner);
  });

  test('titles and blurbs are populated', () {
    expect(HubUserMode.owner.title, 'Owner');
    expect(HubUserMode.accountant.title, 'Accountant');
    expect(HubUserMode.owner.blurb, isNotEmpty);
    expect(HubUserMode.accountant.blurb, isNotEmpty);
  });
}
