import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_hub_app/crm/customer_anonymise_service.dart';
import 'package:mercantis_hub_app/ledger/hub_interceptors.dart';
import 'package:mercantis_hub_app/ledger/ledger_values.dart' hide isTrue;
import 'package:mercantis_hub_app/manifest/hub_manifest.dart';
import 'package:mercantis_hub_app/modules/crm/hub_privacy_actions.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// B-4 — GDPR erasure with ledger retention (spec §6.2): the Customer
/// master is pseudonymised, linked contact data is deleted, appointment
/// history loses its free text — while posted invoices survive untouched,
/// referencing the pseudonymised party. Live obligations block the run.
void main() {
  setUpAll(sqfliteFfiInit);

  late MercantisDatabase db;
  late DocumentEngine engine;
  late CustomerAnonymiseService service;
  const roles = {'System Manager'};
  final now = DateTime(2026, 8, 1, 12, 0);

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
      userId: 'kevin',
      interceptors: const [
        LineItemTotalsInterceptor(),
        TaxCalculationInterceptor(),
      ],
    );
    service = CustomerAnonymiseService(engine);

    await engine.save(
        Document(id: 'PAT-1', docType: 'Customer', payload: {
          'customer_name': 'Maria Borg',
          'customer_type': 'Individual',
          'email': 'maria@example.com',
          'tax_id': 'MT11111111',
        }),
        roles);
    await engine.save(
        Document(id: 'EUR', docType: 'Currency', payload: {
          'currency_name': 'Euro',
          'symbol': '€',
        }),
        roles);
    await engine.save(
        Document(id: 'DOC', docType: 'Schedulable Resource', payload: {
          'resource_name': 'Doctor',
          'resource_type': 'Person',
        }),
        roles);
    await engine.save(
        Document(id: 'WIDGET', docType: 'Item', payload: {
          'item_code': 'WIDGET',
          'item_name': 'Consultation',
          'item_type': 'Service',
          'stock_uom': 'Nos',
        }),
        roles);
  });

  tearDown(() async => db.close());

  Future<Document> pastAppointment(String id,
      {String status = 'Completed'}) {
    return engine.save(
        Document(id: id, docType: 'Appointment', payload: {
          'subject': 'Consultation',
          'resource': 'DOC',
          'customer': 'PAT-1',
          'starts_at': '2026-07-01T09:00:00',
          'ends_at': '2026-07-01T09:30:00',
          'status': status,
          'notes': 'prefers mornings',
          'location': 'Valletta Clinic',
        }),
        roles);
  }

  Future<Document> submittedInvoice(String id) async {
    final invoice = Document(id: id, docType: 'Sales Invoice', payload: {
      'customer': 'PAT-1',
      'posting_date': '2026-07-01',
      'currency': 'EUR',
    });
    invoice.children['items'] = [
      ChildRow(
        id: '', parentId: id, parentDocType: 'Sales Invoice',
        tableName: 'items', rowIndex: 0,
        payload: {'item': 'WIDGET', 'qty': 1, 'rate': 40, 'uom': 'Nos'},
      ),
    ];
    return engine.submit(await engine.save(invoice, roles), roles);
  }

  test('anonymise scrubs the identity, keeps the posted paper', () async {
    await pastAppointment('APT-1');
    final invoice = await submittedInvoice('SI-1');
    // Settled book: nothing outstanding.
    await engine.applyOnSubmitUpdate(
        invoice..payload['outstanding_amount'] = 0, roles);
    await engine.save(
        Document(id: 'CT-1', docType: 'Contact', payload: {
          'first_name': 'Maria',
          'email': 'maria@example.com',
        })
          ..children['links'] = [
            ChildRow(
              id: '', parentId: 'CT-1', parentDocType: 'Contact',
              tableName: 'links', rowIndex: 0,
              payload: {'link_doctype': 'Customer', 'link_name': 'PAT-1'},
            ),
          ],
        roles);

    final result = await service.anonymise('PAT-1', asOf: now);

    final customer = (await engine.fetch('Customer', 'PAT-1'))!;
    expect(customer.payload['customer_name'], result.pseudonym);
    expect('${customer.payload['customer_name']}',
        isNot(contains('Maria')));
    expect('${customer.payload['email'] ?? ''}', isEmpty);
    expect('${customer.payload['tax_id'] ?? ''}', isEmpty);
    expect(asNonEmpty(customer.payload['anonymised_at']), isNotNull);

    // Contact data: gone entirely.
    expect(await engine.fetch('Contact', 'CT-1'), isNull);
    expect(result.contactsDeleted, 1);

    // Appointment history: slot kept, text scrubbed.
    final apt = (await engine.fetch('Appointment', 'APT-1'))!;
    expect(apt.payload['subject'], 'Appointment');
    expect('${apt.payload['notes'] ?? ''}', isEmpty);
    expect('${apt.payload['location'] ?? ''}', isEmpty);

    // The posted invoice is untouched and still references the party id.
    final inv = (await engine.fetch('Sales Invoice', 'SI-1'))!;
    expect(inv.docStatus, 1);
    expect(inv.payload['customer'], 'PAT-1');
  });

  test('an outstanding invoice blocks erasure', () async {
    await submittedInvoice('SI-OWED'); // no outstanding_amount → owes in full
    expect(
        () => service.anonymise('PAT-1', asOf: now),
        throwsA(isA<StateError>().having(
            (e) => e.message, 'message', contains('outstanding'))));
    // Nothing was half-scrubbed.
    expect((await engine.fetch('Customer', 'PAT-1'))!.payload['customer_name'],
        'Maria Borg');
  });

  test('an open upcoming appointment blocks erasure', () async {
    await engine.save(
        Document(id: 'APT-NEXT', docType: 'Appointment', payload: {
          'subject': 'Consultation',
          'resource': 'DOC',
          'customer': 'PAT-1',
          'starts_at': '2026-08-15T09:00:00',
          'ends_at': '2026-08-15T09:30:00',
          'status': 'Scheduled',
        }),
        roles);
    expect(
        () => service.anonymise('PAT-1', asOf: now),
        throwsA(isA<StateError>().having(
            (e) => e.message, 'message', contains('still booked'))));
  });

  test('running twice refuses — erasure is not a loop', () async {
    await service.anonymise('PAT-1', asOf: now);
    expect(
        () => service.anonymise('PAT-1', asOf: now),
        throwsA(isA<StateError>().having(
            (e) => e.message, 'message', contains('already anonymised'))));
  });

  test('the action offers only on customers not yet anonymised', () async {
    final registry = MetadataRegistry(db.db);
    final docType = (await registry.get('Customer'))!;
    final plain = Document(id: 'C', docType: 'Customer', payload: {
      'customer_name': 'X',
    });
    final done = Document(id: 'C', docType: 'Customer', payload: {
      'customer_name': 'Anonymised customer ABC',
      'anonymised_at': '2026-08-01T12:00:00',
    });
    expect(hubPrivacyActionsFor(plain, docType).map((a) => a.id),
        ['customer-anonymise']);
    expect(hubPrivacyActionsFor(done, docType), isEmpty);
    // Never offered off-doctype.
    final item = Document(id: 'I', docType: 'Item', payload: {});
    expect(hubPrivacyActionsFor(item, (await registry.get('Item'))!),
        isEmpty);
  });
}
