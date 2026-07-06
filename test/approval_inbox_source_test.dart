import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';
import 'package:mercantis_hub_app/manifest/hub_manifest.dart';
import 'package:mercantis_hub_app/navigation/hub_navigation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The approvals inbox is served by [MetadataApprovalInboxSource] (real
/// drafts from the document store), not mock data: a draft submittable
/// document appears in the pending list and disappears once submitted.
void main() {
  setUpAll(sqfliteFfiInit);

  const roles = {'System Manager'};

  test('inbox lists real drafts and drops them after submit', () async {
    final db = await MercantisDatabase.open(
        factory: databaseFactoryFfi, path: inMemoryDatabasePath);
    addTearDown(db.close);

    final container = ProviderContainer(overrides: [
      mercantisDatabaseProvider.overrideWith((ref) async => db),
      deviceIdProvider.overrideWith((ref) async => 'test-device'),
      currentUserProvider.overrideWithValue(const CurrentUser(
        id: 'u', displayName: 'Tester', roles: roles,
      )),
      metadataApprovalInboxSourceOverride,
    ]);
    addTearDown(container.dispose);

    final registry = await container.read(metadataRegistryProvider.future);
    final sync = await container.read(syncEngineProvider.future);
    await AppInstaller(database: db.db, registry: registry, syncEngine: sync)
        .install(HubManifest.build());

    final engine = await container.read(documentEngineProvider.future);
    await engine.save(
        Document(id: 'CUST-1', docType: 'Customer', payload: {
          'customer_name': 'Acme Buyer',
          'customer_type': 'Company',
        }),
        roles);
    final draft = await engine.save(
        Document(id: '', docType: 'Sales Order', payload: {
          'customer': 'CUST-1',
          'transaction_date':
              DateTime.now().toIso8601String().split('T').first,
        }),
        roles);

    final source = container.read(approvalInboxSourceProvider);
    expect(source, isA<MetadataApprovalInboxSource>());

    var pending = await source.fetchPending();
    expect(pending.map((e) => e.id), contains(draft.id));

    await engine.submit(draft, roles);
    pending = await source.fetchPending();
    expect(pending.map((e) => e.id), isNot(contains(draft.id)));
  });
}
