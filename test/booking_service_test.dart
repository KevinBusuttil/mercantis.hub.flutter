import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_hub_app/booking/booking_service.dart';
import 'package:mercantis_hub_app/ledger/deposit_service.dart';
import 'package:mercantis_hub_app/ledger/hub_interceptors.dart';
import 'package:mercantis_hub_app/ledger/ledger_values.dart' hide isTrue;
import 'package:mercantis_hub_app/manifest/hub_manifest.dart';
import 'package:mercantis_hub_app/pricing/price_resolver.dart';
import 'package:mercantis_hub_app/scheduling/scheduling_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Phase 4 (P4-1): the appointments composition. Booking takes the slot
/// (S1) and the deposit (S4) in one move; completion drafts and submits
/// the invoice (S1+S8) and auto-applies the deposit; commission (S9) is
/// a percentage over the invoiced net.
void main() {
  setUpAll(sqfliteFfiInit);

  late MercantisDatabase db;
  late DocumentEngine engine;
  late BookingService booking;
  const roles = {'System Manager'};

  final day = DateTime(2026, 7, 20);
  DateTime at(int hour) => DateTime(day.year, day.month, day.day, hour);

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
      deviceId: 'front-desk',
      userId: 'reception',
      interceptors: const [
        PriceResolutionInterceptor(),
        LineItemTotalsInterceptor(),
        TaxCalculationInterceptor(),
        AppointmentConflictInterceptor(),
        DepositApplicationInterceptor(),
      ],
    );
    booking = BookingService(engine);

    await engine.save(
        Document(id: 'STY-ANNA', docType: 'Schedulable Resource', payload: {
          'resource_name': 'Anna', 'resource_type': 'Person',
        }),
        roles);
    await engine.save(
        Document(id: 'CUST-1', docType: 'Customer', payload: {
          'customer_name': 'Maria', 'customer_type': 'Individual',
        }),
        roles);
    await engine.save(
        Document(id: 'CUT', docType: 'Item', payload: {
          'item_code': 'CUT', 'item_name': 'Haircut',
          'item_type': 'Service', 'stock_uom': 'Nos',
          'standard_rate': 30,
        }),
        roles);
    await engine.save(
        Document(id: 'COLOUR', docType: 'Item', payload: {
          'item_code': 'COLOUR', 'item_name': 'Colour Treatment',
          'item_type': 'Service', 'stock_uom': 'Nos',
          'standard_rate': 80,
        }),
        roles);
    for (final account in ['Bank', 'Customer Deposits', 'Debtors']) {
      await engine.save(
          Document(id: account, docType: 'Account', payload: {
            'account_name': account,
            'root_type': account == 'Customer Deposits'
                ? 'Liability'
                : 'Asset',
          }),
          roles);
    }
  });

  tearDown(() async => db.close());

  Future<Document> bookCut({num depositAmount = 0}) => booking.book(
        resource: 'STY-ANNA',
        customer: 'CUST-1',
        serviceItem: 'CUT',
        startsAt: at(10),
        endsAt: at(11),
        depositAmount: depositAmount,
        cashAccount: 'Bank',
        depositAccount: 'Customer Deposits',
      );

  test('booking takes the slot and the deposit in one move', () async {
    final apt = await bookCut(depositAmount: 10);
    expect(apt.id, startsWith('APT-'));
    expect(apt.payload['status'], 'Scheduled');

    // The S4 deposit is real, submitted, and stamped on the booking.
    final depId = '${apt.payload['deposit']}';
    expect(depId, startsWith('DEP-'));
    final dep = await engine.fetch('Customer Deposit', depId);
    expect(dep!.docStatus, 1);
    expect(asNum(dep.payload['amount']), 10);
    expect(dep.payload['remarks'], contains(apt.id));

    // The slot is genuinely held: a clashing booking dies on the S1
    // interceptor and leaves no deposit behind.
    await expectLater(
      booking.book(
        resource: 'STY-ANNA',
        customer: 'CUST-1',
        serviceItem: 'COLOUR',
        startsAt: at(10),
        endsAt: at(12),
        depositAmount: 20,
      ),
      throwsA(isA<StateError>()),
    );
    final deposits =
        await engine.list('Customer Deposit', userRoles: roles);
    expect(deposits, hasLength(1)); // only the first booking's

    // No deposit requested → none created.
    final free = await booking.book(
      resource: 'STY-ANNA',
      customer: 'CUST-1',
      serviceItem: 'CUT',
      startsAt: at(14),
      endsAt: at(15),
    );
    expect(free.payload['deposit'], isNull);
  });

  test('completion invoices at the S8 rate and auto-applies the deposit',
      () async {
    final apt = await bookCut(depositAmount: 10);
    final invoice = await booking.completeBooking(apt.id);

    // Submitted invoice, priced from the item's standard rate.
    expect(invoice.docStatus, 1);
    expect(asNum(invoice.payload['grand_total']), 30);

    // The appointment closed its paper trail.
    final done = await engine.fetch('Appointment', apt.id);
    expect(done!.payload['status'], 'Completed');
    expect(done.payload['sales_invoice'], invoice.id);

    // The deposit application: a Receive Payment Entry pointed at the
    // liability account, for exactly the deposit's balance.
    final depId = '${apt.payload['deposit']}';
    expect(await DepositService(engine).applied(depId), 10);
    final applications = [
      for (final p in await engine.list('Payment Entry', userRoles: roles))
        if (asNonEmpty(p.payload['deposit']) == depId) p,
    ];
    expect(applications, hasLength(1));
    expect(applications.single.docStatus, 1);
    expect(applications.single.payload['paid_to'], 'Customer Deposits');
    expect(asNum(applications.single.payload['paid_amount']), 10);

    // Completing twice refuses (already invoiced).
    await expectLater(
        booking.completeBooking(apt.id), throwsA(isA<StateError>()));
  });

  test('a booking without a deposit completes to a plain invoice',
      () async {
    final apt = await bookCut();
    final invoice = await booking.completeBooking(apt.id);
    expect(invoice.docStatus, 1);
    expect(await engine.list('Payment Entry', userRoles: roles), isEmpty);
  });

  test('commissions: item-specific rule beats the general one', () async {
    await engine.save(
        Document(id: '', docType: 'Commission Rule', payload: {
          'resource': 'STY-ANNA', 'percent': 10,
        }),
        roles);
    await engine.save(
        Document(id: '', docType: 'Commission Rule', payload: {
          'resource': 'STY-ANNA', 'percent': 20, 'service_item': 'COLOUR',
        }),
        roles);

    final cut = await bookCut();
    await booking.completeBooking(cut.id);
    final colour = await booking.book(
      resource: 'STY-ANNA',
      customer: 'CUST-1',
      serviceItem: 'COLOUR',
      startsAt: at(12),
      endsAt: at(13),
    );
    await booking.completeBooking(colour.id);

    final lines = await booking.computeCommissions();
    expect(lines, hasLength(1));
    final anna = lines.single;
    expect(anna.resource, 'STY-ANNA');
    expect(anna.appointments, 2);
    expect(anna.base, 110); // 30 + 80 invoiced net
    // 10% of the cut (3.00) + 20% of the colour (16.00)
    expect(anna.commission, 19);

    // A resource with no enabled rule earns nothing and doesn't appear.
    await engine.save(
        Document(id: 'STY-BERT', docType: 'Schedulable Resource', payload: {
          'resource_name': 'Bert', 'resource_type': 'Person',
        }),
        roles);
    final bert = await booking.book(
      resource: 'STY-BERT',
      customer: 'CUST-1',
      serviceItem: 'CUT',
      startsAt: at(10),
      endsAt: at(11),
    );
    await booking.completeBooking(bert.id);
    final after = await booking.computeCommissions();
    expect(after, hasLength(1));

    // Date bounds: nothing invoiced tomorrow.
    final tomorrow = DateTime.now()
        .add(const Duration(days: 1))
        .toIso8601String()
        .split('T')
        .first;
    expect(await booking.computeCommissions(from: tomorrow), isEmpty);
  });
}
