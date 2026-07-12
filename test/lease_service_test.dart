import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_hub_app/ledger/hub_interceptors.dart';
import 'package:mercantis_hub_app/ledger/ledger_values.dart' hide isTrue;
import 'package:mercantis_hub_app/manifest/hub_manifest.dart';
import 'package:mercantis_hub_app/modules/selling/recurring_invoice_service.dart';
import 'package:mercantis_hub_app/property/lease_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// V5 property: rent IS a Recurring Invoice — activating a lease writes
/// the template, the existing runner bills every period, and arrears are
/// the generated invoices' outstanding balances. The tenancy deposit is
/// S4 like every other prepayment.
void main() {
  setUpAll(sqfliteFfiInit);

  late MercantisDatabase db;
  late DocumentEngine engine;
  late LeaseService leases;
  late RecurringInvoiceService recurring;
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
      deviceId: 'office',
      userId: 'landlord',
      interceptors: const [
        LineItemTotalsInterceptor(),
        TaxCalculationInterceptor(),
      ],
    );
    leases = LeaseService(engine);
    recurring = RecurringInvoiceService(engine: engine);

    await engine.save(
        Document(id: 'TEN-1', docType: 'Customer', payload: {
          'customer_name': 'Grech', 'customer_type': 'Individual',
        }),
        roles);
    await engine.save(
        Document(id: 'RENT', docType: 'Item', payload: {
          'item_code': 'RENT', 'item_name': 'Rent',
          'item_type': 'Service', 'stock_uom': 'Nos',
        }),
        roles);
    await engine.save(
        Document(id: 'PROP-A', docType: 'Property', payload: {
          'property_name': 'Sliema Apt 4', 'property_type': 'Apartment',
        }),
        roles);
    for (final account in ['Bank', 'Customer Deposits']) {
      await engine.save(
          Document(id: account, docType: 'Account', payload: {
            'account_name': account,
            'root_type':
                account == 'Bank' ? 'Asset' : 'Liability',
          }),
          roles);
    }
  });

  tearDown(() async => db.close());

  Future<Document> draftLease({String starts = '2026-07-01'}) =>
      engine.save(
          Document(id: '', docType: 'Lease', company: 'CO-2', payload: {
            'property': 'PROP-A',
            'tenant': 'TEN-1',
            'status': 'Draft',
            'starts_on': starts,
            'monthly_rent': 800,
            'rent_item': 'RENT',
            'frequency': 'Monthly',
          }),
          roles);

  test('activation takes the deposit and writes the rent template',
      () async {
    final lease = await leases.activate(
      (await draftLease()).id,
      depositAmount: 1600,
      cashAccount: 'Bank',
      depositAccount: 'Customer Deposits',
    );
    expect(lease.payload['status'], 'Active');

    // The S4 deposit is real and submitted.
    final deposit = await engine.fetch(
        'Customer Deposit', '${lease.payload['deposit']}');
    expect(deposit!.docStatus, 1);
    expect(asNum(deposit.payload['amount']), 1600);
    expect(deposit.payload['remarks'], contains('Sliema'));
    expect(deposit.company, 'CO-2'); // Codex P2 (PR #169)

    // The template bills the tenant 800 monthly from the start date —
    // under the LEASE's company (Codex P2, PR #169: multi-company books
    // must not fall to the first company).
    final template = await engine.fetch(
        'Recurring Invoice', '${lease.payload['recurring_invoice']}');
    expect(template!.payload['customer'], 'TEN-1');
    expect(template.company, 'CO-2');
    expect(template.payload['next_invoice_date'], '2026-07-01');
    expect(asNum(template.children['items']!.single.payload['rate']), 800);

    // Only Drafts activate.
    await expectLater(
        leases.activate(lease.id), throwsA(isA<StateError>()));
  });

  test('rent bills itself through the existing runner; the roll shows '
      'arrears', () async {
    final lease = await leases.activate((await draftLease()).id);

    // Two periods have elapsed by Aug 15 → two submitted invoices.
    final run = await recurring.generateDue(asOf: '2026-08-15');
    expect(run.generated, hasLength(2));
    expect(run.failures, isEmpty);
    for (final id in run.generated) {
      final inv = await engine.fetch('Sales Invoice', id);
      expect(inv!.docStatus, 1); // auto_submit — rent is contractual
      expect(asNum(inv.payload['grand_total']), 800);
      expect(inv.payload['recurring_invoice'],
          lease.payload['recurring_invoice']);
    }

    // The landlord's list: 1600 owed, next period queued for September.
    final roll = await leases.rentRoll();
    final line = roll.single;
    expect(line.propertyName, 'Sliema Apt 4');
    expect(line.tenant, 'TEN-1');
    expect(line.rent, 800);
    expect(line.arrears, 1600);
    expect(line.nextInvoiceDate, '2026-09-01');

    // A re-run before September bills nothing more.
    expect((await recurring.generateDue(asOf: '2026-08-20')).generated,
        isEmpty);
  });

  test('ending a lease stops the billing but keeps what was raised',
      () async {
    final lease = await leases.activate((await draftLease()).id);
    await recurring.generateDue(asOf: '2026-07-01'); // first month billed

    await leases.end(lease.id, asOf: DateTime(2026, 7, 15));
    final ended = await engine.fetch('Lease', lease.id);
    expect(ended!.payload['status'], 'Ended');
    expect(ended.payload['ends_on'], '2026-07-15');

    // The template is off — months later, nothing new bills.
    final later = await recurring.generateDue(asOf: '2026-12-01');
    expect(later.generated, isEmpty);
    // The July invoice stands.
    final invoices =
        await engine.list('Sales Invoice', userRoles: roles);
    expect(invoices, hasLength(1));

    // Ended leases leave the roll, and can't end twice.
    expect(await leases.rentRoll(), isEmpty);
    await expectLater(leases.end(lease.id), throwsA(isA<StateError>()));
  });
}
