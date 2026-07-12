import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_hub_app/ledger/deposit_service.dart';
import 'package:mercantis_hub_app/ledger/hub_interceptors.dart';
import 'package:mercantis_hub_app/ledger/ledger_values.dart' hide isTrue;
import 'package:mercantis_hub_app/manifest/hub_manifest.dart';
import 'package:mercantis_hub_app/pricing/price_resolver.dart';
import 'package:mercantis_hub_app/rental/rental_service.dart';
import 'package:mercantis_hub_app/scheduling/scheduling_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// V3 rental: availability is the S1 calendar (double-hiring is a
/// conflict error by construction), the booking deposit is S4, and the
/// return bills chargeable days as an ordinary Sales Invoice with the
/// deposit auto-applied.
void main() {
  setUpAll(sqfliteFfiInit);

  late MercantisDatabase db;
  late DocumentEngine engine;
  late RentalService rental;
  const roles = {'System Manager'};

  DateTime day(int d, [int hour = 9]) => DateTime(2026, 8, d, hour);

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
      deviceId: 'yard',
      userId: 'desk',
      interceptors: const [
        PriceResolutionInterceptor(),
        LineItemTotalsInterceptor(),
        TaxCalculationInterceptor(),
        AppointmentConflictInterceptor(),
        DepositApplicationInterceptor(),
      ],
    );
    rental = RentalService(engine);

    await engine.save(
        Document(id: 'RES-DIGGER', docType: 'Schedulable Resource',
            payload: {
              'resource_name': 'Mini digger',
              'resource_type': 'Equipment',
            }),
        roles);
    await engine.save(
        Document(id: 'HIRE-DIGGER', docType: 'Item', payload: {
          'item_code': 'HIRE-DIGGER', 'item_name': 'Digger hire (day)',
          'item_type': 'Service', 'stock_uom': 'Nos',
          'standard_rate': 80,
        }),
        roles);
    await engine.save(
        Document(id: 'UNIT-1', docType: 'Rental Unit', payload: {
          'unit_name': 'Mini digger #1',
          'resource': 'RES-DIGGER',
          'rental_item': 'HIRE-DIGGER',
          'daily_rate': 75,
        }),
        roles);
    await engine.save(
        Document(id: 'CUST-1', docType: 'Customer', payload: {
          'customer_name': 'Vella Builders', 'customer_type': 'Company',
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

  test('chargeable days: ceil with a one-day floor', () {
    expect(RentalService.chargeableDays(day(1), day(1, 15)), 1); // same day
    expect(RentalService.chargeableDays(day(1), day(4)), 3); // exact 3
    expect(RentalService.chargeableDays(day(1), day(4, 10)), 4); // +1h → 4
    expect(RentalService.chargeableDays(day(1), day(1)), 1); // zero-length
  });

  test('booking holds the calendar and takes the deposit', () async {
    final hire = await rental.book(
      unitId: 'UNIT-1',
      customer: 'CUST-1',
      from: day(1),
      to: day(4),
      depositAmount: 100,
      cashAccount: 'Bank',
      depositAccount: 'Customer Deposits',
    );
    expect(hire.id, startsWith('RENT-'));
    expect(hire.payload['status'], 'Draft');
    expect(asNum(hire.payload['daily_rate']), 75); // from the unit
    expect('${hire.payload['deposit']}', startsWith('DEP-'));

    // The unit is genuinely held: an overlapping hire dies on S1.
    await expectLater(
      rental.book(
          unitId: 'UNIT-1', customer: 'CUST-1', from: day(3), to: day(5)),
      throwsA(isA<StateError>()
          .having((e) => '$e', 'message', contains('already booked'))),
    );
    // Availability says exactly what blocks.
    final clashes = await rental.availability('UNIT-1', day(2), day(3));
    expect(clashes, hasLength(1));
    // Back-to-back is fine (half-open interval).
    expect(await rental.availability('UNIT-1', day(4), day(6)), isEmpty);

    // Cancelling frees the window.
    await rental.cancelBooking(hire.id);
    expect(await rental.availability('UNIT-1', day(2), day(3)), isEmpty);
    // A cancelled hire can't check out.
    await expectLater(
        rental.checkOut(hire.id), throwsA(isA<StateError>()));
  });

  test('out → return bills the days and applies the deposit', () async {
    final hire = await rental.book(
      unitId: 'UNIT-1',
      customer: 'CUST-1',
      from: day(1),
      to: day(4), // 3 days planned
      depositAmount: 100,
      cashAccount: 'Bank',
      depositAccount: 'Customer Deposits',
    );

    // Return before checkout refuses; checkout records the handover.
    await expectLater(
        rental.returnUnit(hire.id), throwsA(isA<StateError>()));
    final out = await rental.checkOut(hire.id, condition: 'Full tank');
    expect(out.payload['status'], 'Out');
    expect(out.payload['out_condition'], 'Full tank');

    // Returned a day LATE: charged to the actual moment — 4 days × 75.
    final invoice = await rental.returnUnit(
      hire.id,
      condition: 'Muddy but fine',
      asOf: day(5), // exactly 4 × 24h after pickup
    );
    expect(invoice.docStatus, 1);
    expect(asNum(invoice.payload['grand_total']), 300); // 4 × 75
    final line = invoice.children['items']!.single;
    expect(asNum(line.payload['qty']), 4);
    expect(line.payload['description'], contains('Mini digger #1'));

    // The deposit's full 100 applied against it.
    final depId = '${hire.payload['deposit']}';
    expect(await DepositService(engine).applied(depId), 100);

    final done = await engine.fetch('Rental Agreement', hire.id);
    expect(done!.payload['status'], 'Returned');
    expect(done.payload['sales_invoice'], invoice.id);
    expect(done.payload['return_condition'], contains('Muddy'));

    // No double return.
    await expectLater(
        rental.returnUnit(hire.id), throwsA(isA<StateError>()));
  });

  test('a blank unit rate falls back to S8 pricing on the invoice',
      () async {
    await engine.save(
        Document(id: 'UNIT-2', docType: 'Rental Unit', payload: {
          'unit_name': 'Mini digger #2',
          'resource': 'RES-DIGGER',
          'rental_item': 'HIRE-DIGGER',
          // no daily_rate — S8 resolves the item's 80
        }),
        roles);
    final hire = await rental.book(
        unitId: 'UNIT-2', customer: 'CUST-1', from: day(10), to: day(12));
    await rental.checkOut(hire.id);
    final invoice = await rental.returnUnit(hire.id, asOf: day(12));
    expect(asNum(invoice.payload['grand_total']), 160); // 2 × 80
  });

  test('hires share the calendar with everything else', () async {
    await rental.book(
        unitId: 'UNIT-1', customer: 'CUST-1', from: day(20), to: day(22));
    final board = await SchedulingService(engine).forDay(day(21));
    expect(board, hasLength(1));
    expect('${board.single.payload['subject']}', startsWith('HIRE'));
  });
}
