import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_hub_app/manifest/hub_manifest.dart';
import 'package:mercantis_hub_app/modules/selling/hub_quotation_actions.dart';
import 'package:mercantis_hub_app/modules/selling/quotation_status.dart';
import 'package:mercantis_hub_app/onboarding/hub_seeder.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The derived quotation lifecycle: Draft/Open/Sent/Accepted/Rejected/
/// Expired/Converted/Cancelled, with expiry needing no scheduler.
void main() {
  group('QuotationStatus.compute (pure)', () {
    test('precedence and expiry', () {
      String at(String asOf,
              {int docStatus = 1,
              String? workflowState,
              String? sentOn,
              String? acceptedOn,
              String? rejectedOn,
              String? validTill,
              bool hasDownstream = false}) =>
          QuotationStatus.compute(
            docStatus: docStatus,
            workflowState: workflowState,
            sentOn: sentOn,
            acceptedOn: acceptedOn,
            rejectedOn: rejectedOn,
            validTill: validTill,
            asOf: asOf,
            hasDownstream: hasDownstream,
          );

      expect(at('2026-07-06', docStatus: 0), QuotationStatus.draft);
      expect(at('2026-07-06', docStatus: 2), QuotationStatus.cancelled);
      expect(at('2026-07-06'), QuotationStatus.open);
      expect(at('2026-07-06', sentOn: '2026-07-01'), QuotationStatus.sent);
      // Past valid_till → Expired, even if it was sent…
      expect(at('2026-07-06', sentOn: '2026-06-01', validTill: '2026-06-30'),
          QuotationStatus.expired);
      // …but acceptance, rejection and conversion all outrank expiry.
      expect(
          at('2026-07-06', acceptedOn: '2026-06-20', validTill: '2026-06-30'),
          QuotationStatus.accepted);
      expect(
          at('2026-07-06', rejectedOn: '2026-06-20', validTill: '2026-06-30'),
          QuotationStatus.rejected);
      expect(
          at('2026-07-06', hasDownstream: true, validTill: '2026-06-30'),
          QuotationStatus.converted);
      // The legacy internal workflow folds in.
      expect(at('2026-07-06', workflowState: 'Ordered'), QuotationStatus.converted);
      expect(at('2026-07-06', workflowState: 'Lost'), QuotationStatus.rejected);
      // Valid until today inclusive.
      expect(at('2026-06-30', sentOn: '2026-06-01', validTill: '2026-06-30'),
          QuotationStatus.sent);
    });
  });

  group('actions', () {
    DocType quotationType() => HubManifest.build()
        .docTypes
        .firstWhere((d) => d.id == 'Quotation');

    Document quote(Map<String, dynamic> payload, {int docStatus = 1}) =>
        Document(id: 'QTN-1', docType: 'Quotation', docStatus: docStatus, payload: payload);

    test('an open quote offers send/accept/reject; sent drops send', () {
      final open = hubQuotationActionsFor(quote({}), quotationType());
      expect(open.map((a) => a.id), [
        'quotation-mark-sent',
        'quotation-mark-accepted',
        'quotation-mark-rejected',
      ]);

      final sent = hubQuotationActionsFor(
          quote({'sent_on': '2026-07-01'}), quotationType());
      expect(sent.map((a) => a.id),
          ['quotation-mark-accepted', 'quotation-mark-rejected']);
    });

    test('settled quotes (accepted/converted) and drafts offer nothing', () {
      expect(
          hubQuotationActionsFor(
              quote({'accepted_on': '2026-07-01'}), quotationType()),
          isEmpty);
      expect(
          hubQuotationActionsFor(
              quote({'workflow_state': 'Ordered'}), quotationType()),
          isEmpty);
      expect(hubQuotationActionsFor(quote({}, docStatus: 0), quotationType()),
          isEmpty);
    });
  });

  group('QuotationStatusService (engine)', () {
    setUpAll(sqfliteFfiInit);

    test('lineage makes a quote Converted; expired() lists follow-ups',
        () async {
      final db = await MercantisDatabase.open(
          factory: databaseFactoryFfi, path: inMemoryDatabasePath);
      addTearDown(db.close);
      const roles = {'System Manager'};
      final registry = MetadataRegistry(db.db);
      final sync = SyncEngine(database: db.db, registry: registry);
      await AppInstaller(database: db.db, registry: registry, syncEngine: sync)
          .install(HubManifest.build());
      final engine = DocumentEngine(
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
      );
      await HubSeeder(engine, roles: roles).seed(
          businessName: 'Acme',
          currencyCode: 'EUR',
          year: DateTime.now().year);
      await engine.save(
          Document(id: 'CUST-1', docType: 'Customer', payload: {
            'customer_name': 'Acme Buyer',
            'customer_type': 'Company',
          }),
          roles);

      final service = QuotationStatusService(engine: engine);

      // An expired quote (validity passed, never accepted).
      final stale = await engine.submit(
          await engine.save(
              Document(id: '', docType: 'Quotation', payload: {
                'customer': 'CUST-1',
                'transaction_date': '2026-01-01',
                'valid_till': '2026-01-31',
              }),
              roles),
          roles);
      expect(await service.statusOf(stale.id, asOf: '2026-07-06'),
          QuotationStatus.expired);
      final followUps = await service.expired(asOf: '2026-07-06');
      expect(followUps.map((d) => d.id), contains(stale.id));

      // A quote with a submitted Sales Order back-link is Converted.
      final quote = await engine.submit(
          await engine.save(
              Document(id: '', docType: 'Quotation', payload: {
                'customer': 'CUST-1',
                'transaction_date': '2026-07-01',
              }),
              roles),
          roles);
      await engine.submit(
          await engine.save(
              Document(id: '', docType: 'Sales Order', payload: {
                'customer': 'CUST-1',
                'transaction_date': '2026-07-02',
                'quotation': quote.id,
              }),
              roles),
          roles);
      expect(await service.statusOf(quote.id, asOf: '2026-07-06'),
          QuotationStatus.converted);
    });
  });
}
