import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_hub_app/field_service/equipment_service.dart';
import 'package:mercantis_hub_app/field_service/job_service.dart';
import 'package:mercantis_hub_app/ledger/ledger_values.dart' hide isTrue;
import 'package:mercantis_hub_app/manifest/hub_manifest.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// V4 repair/garage: customer equipment is a register whose value is the
/// service history that accumulates through the ordinary V1 spine — the
/// equipment link rides Service Request → Job, and the desk can read the
/// last meter back or book the unit straight in.
void main() {
  setUpAll(sqfliteFfiInit);

  late MercantisDatabase db;
  late DocumentEngine engine;
  late EquipmentService equipment;
  late JobService jobs;
  const roles = {'System Manager'};

  setUp(() async {
    db = await MercantisDatabase.open(
        factory: databaseFactoryFfi, path: inMemoryDatabasePath);
    final registry = MetadataRegistry(db.db);
    final sync = SyncEngine(database: db.db, registry: registry);
    await AppInstaller(database: db.db, registry: registry, syncEngine: sync)
        .install(HubManifest.build());
    engine = DocumentEngine(
      database: db.db,
      registry: registry,
      metaComposer: MetaComposer(registry, db.db),
      permissionEngine: const PermissionEngine(),
      workflowEngine: WorkflowEngine(db.db),
      expressionEvaluator: ExpressionEvaluator(),
      namingService: NamingService(),
      syncEngine: sync,
      emitter: EventEmitter(),
      deviceId: 'desk',
      userId: 'reception',
      interceptors: const [],
    );
    equipment = EquipmentService(engine);
    jobs = JobService(engine);

    await engine.save(
        Document(id: 'CUST-1', docType: 'Customer', payload: {
          'customer_name': 'Borg', 'customer_type': 'Individual',
        }),
        roles);
    await engine.save(
        Document(id: 'CAR-1', docType: 'Customer Equipment',
            company: 'CO-2', payload: {
          'equipment_name': 'Toyota Yaris',
          'customer': 'CUST-1',
          'equipment_type': 'Vehicle',
          'registration_no': 'ABC-123',
          'meter_unit': 'km',
        }),
        roles);
  });

  tearDown(() async => db.close());

  test('the equipment link rides request → job with the meter reading',
      () async {
    final request = await equipment.requestService(
      'CAR-1',
      subject: 'Annual service',
      meterReading: 78200,
    );
    expect(request.id, startsWith('SRQ-'));
    expect(request.payload['customer'], 'CUST-1'); // owner prefilled
    expect(request.payload['equipment'], 'CAR-1');
    expect(request.company, 'CO-2'); // company sweep: unit → request
    expect(asNum(request.payload['meter_reading']), 78200);

    final job = await jobs.jobFromRequest(request.id);
    expect(job.payload['equipment'], 'CAR-1');
    expect(job.company, 'CO-2'); // …→ job
    expect(asNum(job.payload['meter_reading']), 78200);

    // Unknown units refuse loudly.
    await expectLater(
      equipment.requestService('CAR-9', subject: 'Ghost'),
      throwsA(isA<StateError>()),
    );
  });

  test('history is newest first and skips cancelled work; meter is the '
      'highest on record', () async {
    Future<Document> visit(String subject, String startsAt, num meter,
        {String status = 'Completed'}) async {
      return engine.save(
          Document(id: '', docType: 'Job', payload: {
            'subject': subject,
            'customer': 'CUST-1',
            'equipment': 'CAR-1',
            'status': status,
            'starts_at': startsAt,
            'meter_reading': meter,
          }),
          roles);
    }

    await visit('First service', '2025-06-01T09:00:00', 41000);
    await visit('Brakes', '2026-02-10T09:00:00', 69500);
    await visit('Never happened', '2026-03-01T09:00:00', 99999,
        status: 'Cancelled');

    final history = await equipment.history('CAR-1');
    expect(history, hasLength(2));
    expect(history.first.payload['subject'], 'Brakes'); // newest first
    expect(history.last.payload['subject'], 'First service');

    // The cancelled job's reading never counts.
    expect(await equipment.lastMeterReading('CAR-1'), 69500);

    // A fresh unit has no reading at all.
    await engine.save(
        Document(id: 'CAR-2', docType: 'Customer Equipment', payload: {
          'equipment_name': 'Fiat Panda', 'customer': 'CUST-1',
        }),
        roles);
    expect(await equipment.lastMeterReading('CAR-2'), isNull);
  });
}
