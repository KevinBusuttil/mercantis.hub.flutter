import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_hub_app/settings/hub_settings.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test('payload round-trips', () {
    const s = HubSettings(
      advancedMode: true,
      posEnabled: false,
      operatorName: 'Sam',
      operatorEmail: 'sam@x.io',
    );
    final r = HubSettings.fromPayload(s.toPayload());
    expect(r.advancedMode, true);
    expect(r.posEnabled, false);
    expect(r.manufacturingEnabled, true);
    expect(r.operatorName, 'Sam');
    expect(r.operatorEmail, 'sam@x.io');
  });

  test('fromPayload falls back to defaults for missing/blank values', () {
    final r = HubSettings.fromPayload({'operator_name': '   '});
    expect(r.posEnabled, true);
    expect(r.advancedMode, false);
    expect(r.operatorName, 'Kevin Busuttil');
  });

  group('persistence', () {
    setUpAll(sqfliteFfiInit);

    test('save then hydrate restores state from the singleton doc', () async {
      final db = await MercantisDatabase.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
      final registry = MetadataRegistry(db.db);
      final engine = DocumentEngine(
        database: db.db,
        registry: registry,
        metaComposer: MetaComposer(registry, db.db),
        permissionEngine: const PermissionEngine(),
        workflowEngine: WorkflowEngine(db.db),
        expressionEvaluator: ExpressionEvaluator(),
        namingService: NamingService(),
        syncEngine: SyncEngine(database: db.db, registry: registry),
        emitter: EventEmitter(),
        deviceId: 'test-device',
        userId: 'test-user',
        interceptors: const [],
      );
      await registry.register(const DocType(id: 'Hub Settings', name: 'Hub Settings', fields: [
        FieldDefinition(key: 'advanced_mode', label: 'a', type: FieldType.check),
        FieldDefinition(key: 'pos_enabled', label: 'p', type: FieldType.check),
        FieldDefinition(key: 'manufacturing_enabled', label: 'm', type: FieldType.check),
        FieldDefinition(key: 'deliveries_enabled', label: 'd', type: FieldType.check),
        FieldDefinition(key: 'operator_name', label: 'n', type: FieldType.data),
        FieldDefinition(key: 'operator_email', label: 'e', type: FieldType.data),
      ]));

      final c1 = ProviderContainer();
      addTearDown(c1.dispose);
      await c1.read(hubSettingsProvider.notifier).save(
            engine,
            const HubSettings(advancedMode: true, deliveriesEnabled: false, operatorName: 'Sam'),
          );
      expect(c1.read(hubSettingsProvider).operatorName, 'Sam');

      // A fresh container hydrates from the persisted doc.
      final c2 = ProviderContainer();
      addTearDown(c2.dispose);
      await c2.read(hubSettingsProvider.notifier).hydrate(engine);
      final restored = c2.read(hubSettingsProvider);
      expect(restored.advancedMode, true);
      expect(restored.deliveriesEnabled, false);
      expect(restored.operatorName, 'Sam');

      await db.close();
    });
  });
}
