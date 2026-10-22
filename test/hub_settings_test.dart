import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_hub_app/features/hub_feature.dart';
import 'package:mercantis_hub_app/settings/hub_settings.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test('payload round-trips', () {
    const s = HubSettings(
      advancedMode: true,
      features: {HubFeature.manufacturing},
      operatorName: 'Sam',
      operatorEmail: 'sam@x.io',
    );
    final r = HubSettings.fromPayload(s.toPayload());
    expect(r.advancedMode, true);
    expect(r.posEnabled, false);
    expect(r.manufacturingEnabled, true);
    expect(r.features, {HubFeature.manufacturing});
    expect(r.operatorName, 'Sam');
    expect(r.operatorEmail, 'sam@x.io');
  });

  test('a legacy payload (no version) keeps every feature and classic nav', () {
    final r = HubSettings.fromPayload({'operator_name': 'Sam'});
    expect(r.features, HubFeature.values.toSet());
    expect(r.classicNavigation, isTrue);
    expect(r.systemTools, isTrue);
    expect(r.advancedMode, false);
    expect(r.operatorName, 'Sam');
  });

  test('legacy toggles that were off stay off; dependants follow them', () {
    final r = HubSettings.fromPayload({
      'pos_enabled': false,
      'manufacturing_enabled': '1',
      'projects_enabled': 0,
    });
    expect(r.posEnabled, isFalse);
    expect(r.has(HubFeature.hospitality), isFalse); // lived inside the POS section
    expect(r.has(HubFeature.construction), isFalse); // lived inside Projects
    expect(r.manufacturingEnabled, isTrue);
    expect(r.has(HubFeature.rentals), isTrue); // had no toggle: was always on
  });

  test('a current payload treats missing feature keys as off', () {
    final r = HubSettings.fromPayload({'settings_version': 2});
    expect(r.features, isEmpty);
    expect(r.classicNavigation, isFalse);
    expect(r.systemTools, isFalse);
  });

  test('fresh defaults carry no operator identity and no optional feature', () {
    const s = HubSettings();
    expect(s.operatorName, isEmpty);
    expect(s.operatorEmail, isEmpty);
    expect(s.features, isEmpty);
    expect(s.userMode, HubUserMode.owner);
  });

  test('hospitality needs the till', () {
    const s = HubSettings(features: {HubFeature.hospitality});
    expect(s.has(HubFeature.hospitality), isFalse);
    expect(s.withFeature(HubFeature.pos, true).has(HubFeature.hospitality),
        isTrue);
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
            const HubSettings(advancedMode: true, features: {HubFeature.stock}, operatorName: 'Sam'),
          );
      expect(c1.read(hubSettingsProvider).operatorName, 'Sam');

      // A fresh container hydrates from the persisted doc.
      final c2 = ProviderContainer();
      addTearDown(c2.dispose);
      await c2.read(hubSettingsProvider.notifier).hydrate(engine);
      final restored = c2.read(hubSettingsProvider);
      expect(restored.advancedMode, true);
      expect(restored.deliveriesEnabled, false);
      expect(restored.stockEnabled, true);
      expect(restored.operatorName, 'Sam');

      await db.close();
    });

    Future<(MercantisDatabase, DocumentEngine)> openEngine() async {
      final db = await MercantisDatabase.open(
          factory: databaseFactoryFfi, path: inMemoryDatabasePath);
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
      await registry.register(const DocType(
          id: 'Hub Settings', name: 'Hub Settings', fields: []));
      await registry.register(const DocType(id: 'Company', name: 'Company', fields: [
        FieldDefinition(key: 'company_name', label: 'n', type: FieldType.data),
      ]));
      return (db, engine);
    }

    test('a legacy settings document is migrated once, keeping everything',
        () async {
      final (db, engine) = await openEngine();
      await engine.save(
          Document(id: HubSettings.docId, docType: HubSettings.docType,
              payload: {'advanced_mode': false, 'pos_enabled': false,
                  'operator_name': 'Sam'}),
          {'System Manager'});

      final c = ProviderContainer();
      addTearDown(c.dispose);
      await c.read(hubSettingsProvider.notifier).hydrate(engine);
      final s = c.read(hubSettingsProvider);
      expect(s.classicNavigation, isTrue);
      expect(s.posEnabled, isFalse); // an explicit "off" is respected
      expect(s.has(HubFeature.rentals), isTrue);
      expect(s.operatorName, 'Sam');

      final stored = await engine.fetch(HubSettings.docType, HubSettings.docId);
      expect(stored!.payload['settings_version'], HubSettings.currentVersion);
      expect(stored.payload['rentals_enabled'], isTrue);
      await db.close();
    });

    test('an existing company without a settings document keeps everything',
        () async {
      final (db, engine) = await openEngine();
      await engine.save(
          Document(id: 'ACME', docType: 'Company',
              payload: {'company_name': 'ACME'}),
          {'System Manager'});
      final c = ProviderContainer();
      addTearDown(c.dispose);
      await c.read(hubSettingsProvider.notifier).hydrate(engine);
      final s = c.read(hubSettingsProvider);
      expect(s.features, HubFeature.values.toSet());
      expect(s.classicNavigation, isTrue);
      expect(await engine.fetch(HubSettings.docType, HubSettings.docId),
          isNotNull);
      await db.close();
    });

    test('a brand-new installation starts minimal for onboarding', () async {
      final (db, engine) = await openEngine();
      final c = ProviderContainer();
      addTearDown(c.dispose);
      await c.read(hubSettingsProvider.notifier).hydrate(engine);
      final s = c.read(hubSettingsProvider);
      expect(s.features, isEmpty);
      expect(s.classicNavigation, isFalse);
      expect(s.operatorName, isEmpty);
      await db.close();
    });
  });
}
