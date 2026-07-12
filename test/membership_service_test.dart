import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_hub_app/ledger/hub_interceptors.dart';
import 'package:mercantis_hub_app/ledger/ledger_values.dart' hide isTrue;
import 'package:mercantis_hub_app/manifest/hub_manifest.dart';
import 'package:mercantis_hub_app/membership/membership_service.dart';
import 'package:mercantis_hub_app/modules/selling/recurring_invoice_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// V7 memberships: the fee is a Recurring Invoice steered by the
/// membership's status — and a paused gap is a gift, never a debt.
void main() {
  setUpAll(sqfliteFfiInit);

  late MercantisDatabase db;
  late DocumentEngine engine;
  late MembershipService members;
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
      deviceId: 'front-desk',
      userId: 'gym',
      interceptors: const [
        LineItemTotalsInterceptor(),
        TaxCalculationInterceptor(),
      ],
    );
    members = MembershipService(engine);
    recurring = RecurringInvoiceService(engine: engine);

    await engine.save(
        Document(id: 'MBR-1', docType: 'Customer', payload: {
          'customer_name': 'Camilleri', 'customer_type': 'Individual',
        }),
        roles);
    await engine.save(
        Document(id: 'FEE', docType: 'Item', payload: {
          'item_code': 'FEE', 'item_name': 'Membership Fee',
          'item_type': 'Service', 'stock_uom': 'Nos',
        }),
        roles);
    await engine.save(
        Document(id: 'GOLD', docType: 'Membership Plan', payload: {
          'plan_name': 'Gold', 'fee': 50, 'frequency': 'Monthly',
          'membership_item': 'FEE',
        }),
        roles);
  });

  tearDown(() async => db.close());

  Future<Document> signUp({String joined = '2026-01-10'}) => engine.save(
      Document(id: '', docType: 'Membership', payload: {
        'member': 'MBR-1',
        'plan': 'GOLD',
        'status': 'Draft',
        'joined_on': joined,
      }),
      roles);

  test('activation writes the fee template from the plan', () async {
    final membership = await members.activate((await signUp()).id);
    expect(membership.payload['status'], 'Active');

    final template = await engine.fetch('Recurring Invoice',
        '${membership.payload['recurring_invoice']}');
    expect(template!.payload['customer'], 'MBR-1');
    expect(template.payload['next_invoice_date'], '2026-01-10');
    expect(asNum(template.children['items']!.single.payload['rate']), 50);

    // Only Drafts activate; a disabled plan refuses.
    await expectLater(
        members.activate(membership.id), throwsA(isA<StateError>()));
    await engine.save(
        Document(id: 'OLD', docType: 'Membership Plan', payload: {
          'plan_name': 'Legacy', 'fee': 10, 'membership_item': 'FEE',
          'enabled': 0,
        }),
        roles);
    final legacy = await engine.save(
        Document(id: '', docType: 'Membership', payload: {
          'member': 'MBR-1', 'plan': 'OLD',
          'status': 'Draft', 'joined_on': '2026-01-01',
        }),
        roles);
    await expectLater(
        members.activate(legacy.id), throwsA(isA<StateError>()));
  });

  test('pause stops billing; resume never back-bills the gap', () async {
    final membership = await members.activate((await signUp()).id);

    // Two months bill (Jan 10, Feb 10)…
    expect((await recurring.generateDue(asOf: '2026-02-15')).generated,
        hasLength(2));

    // …then the member pauses. March and April pass: nothing bills.
    await members.pause(membership.id);
    expect((await recurring.generateDue(asOf: '2026-04-30')).generated,
        isEmpty);

    // Resume: the stale March date moves to today — the paused months
    // are a gift, not a debt.
    final resumed = await members.resume(membership.id);
    expect(resumed.payload['status'], 'Active');
    final template = await engine.fetch('Recurring Invoice',
        '${membership.payload['recurring_invoice']}');
    final today = DateTime.now().toIso8601String().split('T').first;
    expect(template!.payload['next_invoice_date'], today);
    expect(
        (await recurring.generateDue(asOf: today)).generated, hasLength(1));

    // States guard themselves: no pause when paused, no resume when
    // active.
    await expectLater(
        members.resume(membership.id), throwsA(isA<StateError>()));
  });

  test('cancel ends billing for good; the roll shows arrears worst first',
      () async {
    final membership = await members.activate((await signUp()).id);
    await recurring.generateDue(asOf: '2026-02-15'); // 2 × 50 unpaid

    final roll = await members.memberRoll();
    expect(roll.single.member, 'MBR-1');
    expect(roll.single.planName, 'Gold');
    expect(roll.single.arrears, 100);
    expect(roll.single.nextInvoiceDate, '2026-03-10');

    await members.cancel(membership.id);
    final cancelled = await engine.fetch('Membership', membership.id);
    expect(cancelled!.payload['status'], 'Cancelled');
    // Months later: nothing new, the two invoices stand, the roll is
    // clear of them.
    expect((await recurring.generateDue(asOf: '2026-12-01')).generated,
        isEmpty);
    expect(await engine.list('Sales Invoice', userRoles: roles),
        hasLength(2));
    expect(await members.memberRoll(), isEmpty);
    await expectLater(
        members.cancel(membership.id), throwsA(isA<StateError>()));
  });
}
