import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_hub_app/ledger/hub_interceptors.dart';
import 'package:mercantis_hub_app/ledger/ledger_values.dart' hide isTrue;
import 'package:mercantis_hub_app/manifest/hub_manifest.dart';
import 'package:mercantis_hub_app/pricing/price_resolver.dart';
import 'package:mercantis_hub_app/scheduling/scheduling_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// S1 scheduling core: resources, appointments, double-booking prevention
/// (half-open intervals — back-to-back is fine), and the booking→invoice
/// hook that prices through S8.
void main() {
  setUpAll(sqfliteFfiInit);

  late MercantisDatabase db;
  late DocumentEngine engine;
  late SchedulingService scheduling;
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
      userId: 'u',
      interceptors: const [
        PriceResolutionInterceptor(),
        LineItemTotalsInterceptor(),
        TaxCalculationInterceptor(),
        AppointmentConflictInterceptor(),
      ],
    );
    scheduling = SchedulingService(engine);

    await engine.save(
        Document(id: 'CHAIR-1', docType: 'Schedulable Resource', payload: {
          'resource_name': 'Chair 1',
          'resource_type': 'Room',
        }),
        roles);
    await engine.save(
        Document(id: 'CUST-1', docType: 'Customer', payload: {
          'customer_name': 'C',
          'customer_type': 'Individual',
        }),
        roles);
    await engine.save(
        Document(id: 'CUT', docType: 'Item', payload: {
          'item_code': 'CUT', 'item_name': 'Haircut',
          'item_type': 'Service', 'stock_uom': 'Nos',
          'standard_rate': 25,
        }),
        roles);
  });

  tearDown(() async => db.close());

  Future<Document> book(String subject, String start, String end,
          {String status = 'Scheduled',
          bool overlap = false,
          String? customer,
          String? item}) async =>
      engine.save(
          Document(id: '', docType: 'Appointment', payload: {
            'subject': subject,
            'resource': 'CHAIR-1',
            'starts_at': start,
            'ends_at': end,
            'status': status,
            if (overlap) 'allow_overlap': 1,
            if (customer != null) 'customer': customer,
            if (item != null) 'service_item': item,
          }),
          roles);

  test('overlapping bookings on one resource are blocked; back-to-back ok',
      () async {
    await book('Anna', '2026-07-13T09:00:00', '2026-07-13T10:00:00');

    // Inside the window → blocked.
    await expectLater(
      book('Bert', '2026-07-13T09:30:00', '2026-07-13T10:30:00'),
      throwsA(isA<StateError>()),
    );
    // Half-open interval: starting exactly when the other ends is fine.
    final next =
        await book('Carla', '2026-07-13T10:00:00', '2026-07-13T11:00:00');
    expect(next.id, startsWith('APT-'));
  });

  test('cancelled slots free the resource; allow_overlap shares it',
      () async {
    final anna =
        await book('Anna', '2026-07-13T09:00:00', '2026-07-13T10:00:00');
    anna.payload['status'] = 'Cancelled';
    await engine.save(anna, roles);

    // The slot is free again.
    await book('Bert', '2026-07-13T09:00:00', '2026-07-13T10:00:00');

    // A group slot opts into sharing.
    await book('Yoga class', '2026-07-13T09:00:00', '2026-07-13T10:00:00',
        overlap: true);
  });

  test('rescheduling an appointment does not clash with itself', () async {
    final anna =
        await book('Anna', '2026-07-13T09:00:00', '2026-07-13T10:00:00');
    anna.payload['ends_at'] = '2026-07-13T10:30:00';
    final moved = await engine.save(anna, roles);
    expect(moved.payload['ends_at'], '2026-07-13T10:30:00');
  });

  test('an appointment must end after it starts', () async {
    await expectLater(
      book('Backwards', '2026-07-13T10:00:00', '2026-07-13T09:00:00'),
      throwsA(isA<StateError>()),
    );
  });

  test('forDay returns the day\'s bookings in start order', () async {
    await book('Late', '2026-07-13T15:00:00', '2026-07-13T16:00:00');
    await book('Early', '2026-07-13T08:00:00', '2026-07-13T09:00:00');
    await book('Other day', '2026-07-14T08:00:00', '2026-07-14T09:00:00');

    final day = await scheduling.forDay(DateTime(2026, 7, 13));
    expect([for (final a in day) a.payload['subject']], ['Early', 'Late']);
  });

  test('invoiceFor drafts an S8-priced invoice and stamps the appointment',
      () async {
    final apt = await book(
        'Haircut Anna', '2026-07-13T09:00:00', '2026-07-13T10:00:00',
        customer: 'CUST-1', item: 'CUT');

    final draft = await scheduling.invoiceFor(apt.id);
    expect(draft.docStatus, 0); // a draft for review, not a posting
    final line = draft.children['items']!.single;
    expect(asNum(line.payload['rate']), 25); // S8 resolved the standard rate
    expect(asNum(draft.payload['grand_total']), 25);

    final stamped = await engine.fetch('Appointment', apt.id);
    expect(stamped!.payload['sales_invoice'], draft.id);
    expect(stamped.payload['status'], 'Completed');

    // No double billing.
    await expectLater(
        scheduling.invoiceFor(apt.id), throwsA(isA<StateError>()));
  });

  test('invoiceFor refuses appointments missing customer or item', () async {
    final noCustomer = await book(
        'Walk-in', '2026-07-13T11:00:00', '2026-07-13T12:00:00',
        item: 'CUT');
    await expectLater(
        scheduling.invoiceFor(noCustomer.id), throwsA(isA<StateError>()));

    final noItem = await book(
        'Chat', '2026-07-13T12:00:00', '2026-07-13T13:00:00',
        customer: 'CUST-1');
    await expectLater(
        scheduling.invoiceFor(noItem.id), throwsA(isA<StateError>()));
  });
}
