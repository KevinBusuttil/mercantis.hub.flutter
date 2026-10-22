import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_hub_app/ledger/hub_interceptors.dart';
import 'package:mercantis_hub_app/ledger/ledger_derivation_service.dart';
import 'package:mercantis_hub_app/ledger/ledger_values.dart' show asNum, round2;
import 'package:mercantis_hub_app/manifest/hub_manifest.dart';
import 'package:mercantis_hub_app/onboarding/hub_seeder.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const systemRoles = {'System Manager'};

/// A production-shaped Atlas Solo book on a real SQLite file: the Hub
/// manifest, every production interceptor (including the posting outbox) and
/// the ledger derivation service, wired the way the app wires them at boot.
///
/// Opening a second harness on the same [path] after [close] is how tests
/// model "the app restarted" (and, after a restore, "a clean installation").
class BooksHarness {
  BooksHarness._(this.path, this.db, this.engine, this.emitter, this.ledger);

  final String path;
  final MercantisDatabase db;
  final DocumentEngine engine;
  final EventEmitter emitter;
  LedgerDerivationService? ledger;

  static Future<BooksHarness> open(
    String path, {
    bool startLedger = true,
    bool seed = true,
    String deviceId = 'device-a',
    List<DocumentInterceptor> interceptors = hubInterceptors,
  }) async {
    final db = await MercantisDatabase.open(
        factory: databaseFactoryFfi, path: path);
    final registry = MetadataRegistry(db.db);
    final sync = SyncEngine(database: db.db, registry: registry);
    final installer =
        AppInstaller(database: db.db, registry: registry, syncEngine: sync);
    final manifest = HubManifest.build();
    if (await installer.isInstalled(manifest.id)) {
      await installer.syncMetadata(manifest);
    } else {
      await installer.install(manifest);
    }
    final emitter = EventEmitter();
    final engine = DocumentEngine(
      database: db.db,
      registry: registry,
      metaComposer: MetaComposer(registry, db.db),
      permissionEngine: const PermissionEngine(),
      workflowEngine: WorkflowEngine(db.db),
      expressionEvaluator: ExpressionEvaluator(),
      namingService: NamingService(),
      syncEngine: sync,
      emitter: emitter,
      deviceId: deviceId,
      userId: 'owner',
      interceptors: interceptors,
    );
    final h = BooksHarness._(path, db, engine, emitter, null);
    if (seed && (await engine.list('Company', userRoles: systemRoles)).isEmpty) {
      await HubSeeder(engine, roles: systemRoles).seed(
          businessName: 'Harbour Lane Trading',
          currencyCode: 'EUR',
          year: DateTime.now().year);
    }
    if (startLedger) await h.startLedger();
    return h;
  }

  /// Start derivation and run startup recovery, exactly as boot does.
  Future<List<PostingBatch>> startLedger() async {
    final l = LedgerDerivationService(
        engine: engine, emitter: emitter, database: db.db);
    l.start();
    ledger = l;
    return l.recoverPendingPostings();
  }

  Future<void> close() async {
    ledger?.dispose();
    await db.close();
  }

  Future<num> balance(String account) async {
    num bal = 0;
    for (final r in await engine.list('GL Entry',
        filters: {'account': account}, userRoles: systemRoles)) {
      bal += asNum(r.payload['debit']) - asNum(r.payload['credit']);
    }
    return round2(bal);
  }

  /// Σ debit − Σ credit over every GL row (0 for balanced books).
  Future<num> trialBalanceDifference() async {
    num d = 0;
    for (final r in await engine.list('GL Entry', userRoles: systemRoles)) {
      d += asNum(r.payload['debit']) - asNum(r.payload['credit']);
    }
    return round2(d);
  }

  Future<int> rowCount(String docType, [Map<String, dynamic>? filters]) async =>
      (await engine.list(docType, filters: filters, userRoles: systemRoles))
          .length;

  Future<Document?> bin(String item, String warehouse) =>
      engine.fetch('Bin', 'BIN-$item-$warehouse');

  Future<num> stockValue() async {
    num v = 0;
    for (final b in await engine.list('Bin', userRoles: systemRoles)) {
      v += asNum(b.payload['stock_value']);
    }
    return round2(v);
  }

  Future<Document> save(Document doc) => engine.save(doc, systemRoles);
  Future<Document> submit(Document doc) =>
      engine.submit(doc, systemRoles);
  Future<Document> saveAndSubmit(Document doc) async =>
      engine.submit(await engine.save(doc, systemRoles), systemRoles);
}

ChildRow itemLine(String parentType, Map<String, dynamic> payload,
        [int index = 0, String table = 'items']) =>
    ChildRow(
      id: '',
      parentId: '',
      parentDocType: parentType,
      tableName: table,
      rowIndex: index,
      payload: payload,
    );

String isoToday() => DateTime.now().toIso8601String().split('T').first;
