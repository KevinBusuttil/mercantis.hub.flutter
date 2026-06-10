import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_hub_app/manufacturing/manufacturing_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The Work-Order → completion-Stock-Entry auto-post: when a Work Order reaches
/// `Completed` (a `wf-work-order` transition fans out a [WorkflowTransitionEvent]),
/// [ManufacturingDerivationService] posts and submits the completion Stock Entry.
void main() {
  setUpAll(sqfliteFfiInit);

  late MercantisDatabase database;
  late DocumentEngine engine;
  late EventEmitter emitter;
  late ManufacturingDerivationService service;
  const roles = {'System Manager'};

  setUp(() async {
    database = await MercantisDatabase.open(
        factory: databaseFactoryFfi, path: inMemoryDatabasePath);
    final registry = MetadataRegistry(database.db);
    emitter = EventEmitter();
    engine = DocumentEngine(
      database: database.db,
      registry: registry,
      metaComposer: MetaComposer(registry, database.db),
      permissionEngine: const PermissionEngine(),
      workflowEngine: WorkflowEngine(database.db),
      expressionEvaluator: ExpressionEvaluator(),
      namingService: NamingService(),
      syncEngine: SyncEngine(database: database.db, registry: registry),
      emitter: emitter,
      deviceId: 'test',
      userId: 'test',
      interceptors: const [],
    );

    await registry.register(const DocType(
        id: 'Work Order Item', name: 'Work Order Item', isChild: true, fields: [
      FieldDefinition(key: 'item', label: 'Item', type: FieldType.data),
      FieldDefinition(key: 'required_qty', label: 'Req Qty', type: FieldType.float),
    ]));
    await registry.register(const DocType(id: 'Work Order', name: 'Work Order', fields: [
      FieldDefinition(key: 'item', label: 'Item', type: FieldType.data),
      FieldDefinition(key: 'qty_to_produce', label: 'Qty', type: FieldType.float),
      FieldDefinition(key: 'source_warehouse', label: 'Src', type: FieldType.data),
      FieldDefinition(key: 'target_warehouse', label: 'Tgt', type: FieldType.data),
      FieldDefinition(key: 'required_items', label: 'Required', type: FieldType.table, tableDocType: 'Work Order Item'),
    ]));
    await registry.register(const DocType(
        id: 'Stock Entry Detail', name: 'Stock Entry Detail', isChild: true, fields: [
      FieldDefinition(key: 'item', label: 'Item', type: FieldType.data),
      FieldDefinition(key: 'qty', label: 'Qty', type: FieldType.float),
      FieldDefinition(key: 'source_warehouse', label: 'Src', type: FieldType.data),
      FieldDefinition(key: 'target_warehouse', label: 'Tgt', type: FieldType.data),
    ]));
    await registry.register(const DocType(
        id: 'Stock Entry', name: 'Stock Entry', isSubmittable: true, fields: [
      FieldDefinition(key: 'stock_entry_type', label: 'Type', type: FieldType.data),
      FieldDefinition(key: 'posting_date', label: 'Date', type: FieldType.data),
      FieldDefinition(key: 'items', label: 'Items', type: FieldType.table, tableDocType: 'Stock Entry Detail'),
    ]));

    service = ManufacturingDerivationService(engine: engine, emitter: emitter);
    service.start();

    final wo = Document(id: 'WO-1', docType: 'Work Order', payload: {
      'item': 'WIDGET',
      'qty_to_produce': 50,
      'source_warehouse': 'RAW',
      'target_warehouse': 'FG',
    });
    wo.children['required_items'] = [
      ChildRow(id: '', parentId: 'WO-1', parentDocType: 'Work Order', tableName: 'required_items', rowIndex: 0, payload: {'item': 'STEEL', 'required_qty': 10}),
      ChildRow(id: '', parentId: 'WO-1', parentDocType: 'Work Order', tableName: 'required_items', rowIndex: 1, payload: {'item': 'BOLT', 'required_qty': 100}),
    ];
    await engine.save(wo, roles);
  });

  tearDown(() => database.close());

  // The service handles events fire-and-forget and posts then submits in
  // separate async steps; poll until the SE is not just present but submitted,
  // so the assertion can't race the submit.
  Future<Document?> awaitSe(String id) async {
    for (var i = 0; i < 80; i++) {
      final d = await engine.fetch('Stock Entry', id);
      if (d != null && d.docStatus == 1) return d;
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    return engine.fetch('Stock Entry', id);
  }

  WorkflowTransitionEvent completed(String woId) => WorkflowTransitionEvent(
        documentId: woId,
        workflow: 'wf-work-order',
        fromState: 'Submitted',
        toState: 'Completed',
        action: 'Complete',
        userId: 'system',
      );

  test('auto-posts a submitted completion Stock Entry on WO Completed', () async {
    emitter.publish(completed('WO-1'));
    final se = await awaitSe('SE-WO-1-completion');
    expect(se, isNotNull);
    expect(se!.docStatus, 1, reason: 'completion Stock Entry must be submitted');
    expect(se.children['items'], hasLength(3)); // 2 raw consumed + 1 finished
  });

  test('is idempotent — a repeat Completed event posts no second entry', () async {
    emitter.publish(completed('WO-1'));
    await awaitSe('SE-WO-1-completion');
    emitter.publish(completed('WO-1'));
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final all = await engine.list('Stock Entry');
    expect(all.where((d) => d.id == 'SE-WO-1-completion'), hasLength(1));
  });

  test('ignores non-completion transitions', () async {
    emitter.publish(const WorkflowTransitionEvent(
      documentId: 'WO-1',
      workflow: 'wf-work-order',
      fromState: 'Draft',
      toState: 'Submitted',
      action: 'Submit',
      userId: 'system',
    ));
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(await engine.fetch('Stock Entry', 'SE-WO-1-completion'), isNull);
  });
}
