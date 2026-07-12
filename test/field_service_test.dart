import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_hub_app/field_service/job_service.dart';
import 'package:mercantis_hub_app/ledger/hub_interceptors.dart';
import 'package:mercantis_hub_app/manifest/hub_manifest.dart';
import 'package:mercantis_hub_app/scheduling/scheduling_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// V1 Field Service increment 1: intake→job, and dispatch that books a
/// real S1 appointment on the technician — so double-booking a tech is
/// impossible by construction and jobs share the calendar.
void main() {
  setUpAll(sqfliteFfiInit);

  late MercantisDatabase db;
  late DocumentEngine engine;
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
      deviceId: 'devA',
      userId: 'dispatcher',
      interceptors: const [
        LineItemTotalsInterceptor(),
        AppointmentConflictInterceptor(),
      ],
    );
    jobs = JobService(engine);

    await engine.save(
        Document(id: 'CUST-1', docType: 'Customer', payload: {
          'customer_name': 'C', 'customer_type': 'Company',
        }),
        roles);
    await engine.save(
        Document(id: 'TECH-MARIA', docType: 'Schedulable Resource', payload: {
          'resource_name': 'Maria', 'resource_type': 'Person',
        }),
        roles);
  });

  tearDown(() async => db.close());

  Future<Document> openRequest() => engine.save(
      Document(id: '', docType: 'Service Request', payload: {
        'subject': 'Boiler dead',
        'customer': 'CUST-1',
        'priority': 'Urgent',
        'address': '1 Triq il-Kbira, Mosta',
        'description': 'No hot water since Friday.',
      }),
      roles);

  test('a request converts once, carrying intake details both ways',
      () async {
    final request = await openRequest();
    final job = await jobs.jobFromRequest(request.id);

    expect(job.id, startsWith('JOB-'));
    expect(job.payload['subject'], 'Boiler dead');
    expect(job.payload['customer'], 'CUST-1');
    expect(job.payload['priority'], 'Urgent');
    expect(job.payload['address'], contains('Mosta'));
    expect(job.payload['status'], 'Draft');

    final updated = await engine.fetch('Service Request', request.id);
    expect(updated!.payload['status'], 'Converted');
    expect(updated.payload['job'], job.id);

    // Converting again is refused — one job per request.
    await expectLater(
        jobs.jobFromRequest(request.id), throwsA(isA<StateError>()));
  });

  test('dispatch books a conflict-checked appointment on the technician',
      () async {
    final job =
        await jobs.jobFromRequest((await openRequest()).id);
    final scheduled = await jobs.scheduleJob(
      job.id,
      technician: 'TECH-MARIA',
      startsAt: DateTime(2026, 7, 14, 9),
      endsAt: DateTime(2026, 7, 14, 11),
    );
    expect(scheduled.payload['status'], 'Scheduled');
    final bookingId = scheduled.payload['appointment'] as String;
    final booking = await engine.fetch('Appointment', bookingId);
    expect(booking!.payload['resource'], 'TECH-MARIA');
    expect(booking.payload['subject'], contains(job.id));

    // A second job on the same tech in the same window is refused, and
    // stays untouched (the appointment is booked first).
    final other =
        await jobs.jobFromRequest((await openRequest()).id);
    await expectLater(
      jobs.scheduleJob(
        other.id,
        technician: 'TECH-MARIA',
        startsAt: DateTime(2026, 7, 14, 10),
        endsAt: DateTime(2026, 7, 14, 12),
      ),
      throwsA(isA<StateError>()),
    );
    final untouched = await engine.fetch('Job', other.id);
    expect(untouched!.payload['status'], 'Draft');
    expect(untouched.payload['appointment'], isNull);

    // Rescheduling the first job MOVES its booking instead of stacking a
    // second one.
    final moved = await jobs.scheduleJob(
      job.id,
      technician: 'TECH-MARIA',
      startsAt: DateTime(2026, 7, 14, 13),
      endsAt: DateTime(2026, 7, 14, 15),
    );
    expect(moved.payload['appointment'], bookingId); // same booking
    final all = await SchedulingService(engine)
        .forDay(DateTime(2026, 7, 14));
    expect(all, hasLength(1));

    // The freed morning is bookable now.
    await jobs.scheduleJob(
      other.id,
      technician: 'TECH-MARIA',
      startsAt: DateTime(2026, 7, 14, 9),
      endsAt: DateTime(2026, 7, 14, 11),
    );
  });

  test('cancelling a job frees the slot; starting confirms it', () async {
    final job =
        await jobs.jobFromRequest((await openRequest()).id);
    await jobs.scheduleJob(
      job.id,
      technician: 'TECH-MARIA',
      startsAt: DateTime(2026, 7, 14, 9),
      endsAt: DateTime(2026, 7, 14, 11),
    );

    await jobs.setJobStatus(job.id, 'In Progress');
    var booking = await engine.fetch('Appointment',
        (await engine.fetch('Job', job.id))!.payload['appointment']);
    expect(booking!.payload['status'], 'Confirmed');

    await jobs.setJobStatus(job.id, 'Cancelled');
    booking = await engine.fetch('Appointment', booking.id);
    expect(booking!.payload['status'], 'Cancelled');

    // The technician's slot is free again.
    final other =
        await jobs.jobFromRequest((await openRequest()).id);
    await jobs.scheduleJob(
      other.id,
      technician: 'TECH-MARIA',
      startsAt: DateTime(2026, 7, 14, 9),
      endsAt: DateTime(2026, 7, 14, 11),
    );
  });

  test('a job carries checklist, materials and labour lines', () async {
    await engine.save(
        Document(id: 'PIPE', docType: 'Item', payload: {
          'item_code': 'PIPE', 'item_name': 'Copper pipe',
          'item_type': 'Stock', 'stock_uom': 'Metre',
        }),
        roles);
    final job = Document(id: '', docType: 'Job', payload: {
      'subject': 'Repipe bathroom',
      'customer': 'CUST-1',
    });
    job.children['checklist'] = [
      ChildRow(
        id: '', parentId: '', parentDocType: 'Job',
        tableName: 'checklist', rowIndex: 0,
        payload: {'task': 'Isolate water main'},
      ),
    ];
    job.children['materials'] = [
      ChildRow(
        id: '', parentId: '', parentDocType: 'Job',
        tableName: 'materials', rowIndex: 0,
        payload: {'item': 'PIPE', 'qty': 3},
      ),
    ];
    job.children['labour'] = [
      ChildRow(
        id: '', parentId: '', parentDocType: 'Job',
        tableName: 'labour', rowIndex: 0,
        payload: {'description': 'Install', 'hours': 2, 'rate': 40},
      ),
    ];
    final saved = await engine.save(job, roles);
    final loaded = await engine.fetch('Job', saved.id);
    expect(loaded!.children['checklist'], hasLength(1));
    expect(loaded.children['materials']!.single.payload['item'], 'PIPE');
    expect(loaded.children['labour']!.single.payload['hours'], 2);
  });
}
