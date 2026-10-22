import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';
import 'package:mercantis_hub_app/features/hub_feature.dart';
import 'package:mercantis_hub_app/navigation/hub_shell.dart';
import 'package:mercantis_hub_app/navigation/hub_surface.dart';
import 'package:mercantis_hub_app/onboarding/business_preset.dart';
import 'package:mercantis_hub_app/settings/hub_settings.dart';
import 'package:mercantis_hub_app/workspaces/hub_workspaces.dart';

import '../support/hub_app_harness.dart';

/// Product scope by profile, at workspace, section, item and quick-action
/// level (Solo mobile-first UX brief, sections A–D).
void main() {
  List<WorkspaceDescriptor> ws(HubSettings s, {bool team = false}) =>
      hubWorkspaces(HubSurface(s, teamConnected: team));

  Iterable<String> customRoutes(List<WorkspaceDescriptor> all) => [
        for (final w in all)
          for (final sec in w.sections)
            for (final i in sec.items)
              if (i is CustomWorkspaceItem) i.routeName,
      ];

  Iterable<String> docTypes(List<WorkspaceDescriptor> all) => [
        for (final w in all)
          for (final sec in w.sections)
            for (final i in sec.items)
              if (i is DocTypeWorkspaceItem) i.docType,
      ];

  Iterable<String> sectionLabels(List<WorkspaceDescriptor> all) =>
      [for (final w in all) for (final sec in w.sections) sec.label];

  Iterable<QuickAction> quickActions(List<WorkspaceDescriptor> all) =>
      [for (final w in all) ...w.quickActions];

  final services = presetSettings(BusinessPreset.services);
  final trade = presetSettings(BusinessPreset.trade);
  final retail = presetSettings(BusinessPreset.retail);

  group('a new Services business', () {
    final all = ws(services);

    test('sees no vertical, stock, till or team workspace', () {
      expect(all.map((w) => w.id), [
        'home', 'sales_fulfilment', 'purchasing', 'finance', 'reports', 'setup',
      ]);
    });

    test('sees no vertical section, item or route', () {
      expect(
          customRoutes(all),
          isNot(anyOf([
            contains('rentals'), contains('rent-roll'), contains('members'),
            contains('contracts'), contains('assets'), contains('pos-till'),
            contains('tables'), contains('kitchen'), contains('schedule'),
            contains('dispatch'), contains('inbox'), contains('low-stock'),
          ])));
      expect(
          docTypes(all),
          isNot(anyOf([
            contains('Rental Unit'), contains('Property'), contains('Lease'),
            contains('Membership'), contains('Construction Contract'),
            contains('Asset'), contains('Sales Channel'), contains('Warehouse'),
            contains('Stock Entry'), contains('BOM'), contains('Journal Entry'),
            contains('GL Entry'), contains('DocType'),
          ])));
      expect(
          sectionLabels(all),
          isNot(anyOf([
            contains('Rentals'), contains('Online channels'),
            contains('Memberships'), contains('Fixed assets'),
            contains('Property'), contains('Construction'),
          ])));
    });

    test('quick actions only point at things it can use', () {
      final ids = quickActions(all).map((q) => q.id).toSet();
      expect(ids, isNot(contains('sf_pos_till')));
      final labels = quickActions(all).map((q) => q.label);
      expect(labels, containsAll(['New invoice', 'New quote', 'Receive payment']));
      expect(labels, isNot(contains('Move stock')));
    });

    test('has no approvals card or action without Atlas Team', () {
      final home = all.first;
      expect(home.quickActions.map((q) => q.routeName),
          isNot(contains('/w/approvals/inbox')));
    });
  });

  test('switching a feature on brings its whole surface back', () {
    final s = services.withFeature(HubFeature.rentals, true);
    expect(customRoutes(ws(s)), contains('rentals'));
    expect(sectionLabels(ws(s)), contains('Rentals'));
    final p = services.withFeature(HubFeature.property, true);
    expect(sectionLabels(ws(p)), contains('Property & tenancies'));
  });

  test('Trade sees stock and selling; Retail sees the till', () {
    expect(ws(trade).map((w) => w.id), contains('inventory'));
    expect(customRoutes(ws(trade)), isNot(contains('pos-till')));
    expect(customRoutes(ws(retail)), contains('pos-till'));
    expect(customRoutes(ws(retail)), isNot(contains('tables')));
  });

  test('Approvals appear with Atlas Team', () {
    expect(ws(services, team: true).map((w) => w.id), contains('approvals'));
  });

  group('Owner and Accountant views', () {
    test('Accountant adds the ledger, journals and report builder', () {
      final owner = ws(services);
      final acc = ws(services.withUserMode(HubUserMode.accountant));
      expect(docTypes(owner), isNot(contains('Journal Entry')));
      expect(docTypes(acc), containsAll(['Journal Entry', 'Account', 'Cost Center']));
      expect(docTypes(owner), isNot(contains('Cost Center')));
      expect(customRoutes(owner), isNot(contains('report-builder')));
      expect(customRoutes(acc), contains('report-builder'));
    });

    test('both views reach the financial statements', () {
      for (final s in [services, services.withUserMode(HubUserMode.accountant)]) {
        expect(customRoutes(ws(s)), contains('reports'));
      }
    });

    test('Owner uses business words, Accountant engine words', () {
      final owner = ws(services).firstWhere((w) => w.id == 'finance');
      final acc = ws(services.withUserMode(HubUserMode.accountant))
          .firstWhere((w) => w.id == 'finance');
      expect(owner.label, 'Money');
      expect(acc.label, isNot('Money'));
    });
  });

  test('a legacy installation keeps every workspace it had', () {
    final legacy = HubSettings.fromPayload({'pos_enabled': true});
    expect(ws(legacy).map((w) => w.id), containsAll([
      'home', 'sales_fulfilment', 'field_service', 'appointments', 'projects',
      'purchasing', 'inventory', 'manufacturing', 'delivery', 'finance',
      'reports', 'setup',
    ]));
    expect(customRoutes(ws(legacy)),
        containsAll(['rentals', 'rent-roll', 'members', 'contracts', 'assets',
            'pos-till', 'tables', 'report-builder']));
    // Classic installs keep the ledger whatever the persona.
    expect(docTypes(ws(legacy)), contains('Journal Entry'));
  });

  group('every visible link is reachable', () {
    final profiles = <String, HubSettings>{
      for (final p in BusinessPreset.all) p.id: presetSettings(p),
      'services-accountant':
          services.withUserMode(HubUserMode.accountant),
      'legacy': HubSettings.legacy(),
    };
    for (final MapEntry(key: name, value: s) in profiles.entries) {
      test('$name: no visible item leads to a hidden-feature page', () {
        final surface = HubSurface(s);
        for (final w in hubWorkspaces(surface)) {
          expect(surface.allows(hubRequirementFor(w.id, null)), isTrue,
              reason: w.id);
          for (final r in customRoutes([w])) {
            expect(surface.allows(hubRequirementFor(w.id, r)), isTrue,
                reason: '${w.id}/$r');
          }
          for (final q in w.quickActions) {
            final route = q.routeName;
            if (route == null) continue;
            final seg = Uri.parse(route).pathSegments;
            if (seg.length < 2 || seg.first != 'w') continue;
            expect(surface.allows(hubRequirementFor(
                    seg[1], seg.length > 2 ? seg[2] : null)),
                isTrue, reason: '${q.id} → $route');
          }
        }
      });
    }
  });

  group('phone destinations', () {
    List<String> labels(HubSettings s) =>
        hubPhoneDestinations(HubSurface(s)).map((d) => d.label).toList();

    test('match the profile', () {
      expect(labels(services), ['Today', 'Customers', 'Invoices', 'Money']);
      expect(labels(trade), ['Today', 'Sales', 'Stock', 'Money']);
      expect(labels(retail), ['Today', 'Till', 'Stock', 'Money']);
      expect(labels(presetSettings(BusinessPreset.manufacturing)),
          ['Today', 'Sales', 'Stock', 'Money']);
    });

    test('never point at a switched-off feature', () {
      final noTill = retail.withFeature(HubFeature.pos, false);
      expect(labels(noTill), ['Today', 'Sales', 'Stock', 'Money']);
      final noStock = trade.withFeature(HubFeature.stock, false);
      expect(labels(noStock), ['Today', 'Sales', 'Invoices', 'Money']);
    });

    test('are at most four plus More', () {
      for (final p in BusinessPreset.all) {
        expect(hubPhoneDestinations(HubSurface(presetSettings(p))).length,
            lessThanOrEqualTo(kMaxPhonePrimaryDestinations));
      }
    });
  });
}
