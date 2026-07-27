import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_hub_app/booking/booking_service.dart';
import 'package:mercantis_hub_app/crm/customer_anonymise_service.dart';
import 'package:mercantis_hub_app/ledger/deposit_service.dart';
import 'package:mercantis_hub_app/ledger/hub_interceptors.dart';
import 'package:mercantis_hub_app/ledger/ledger_derivation_service.dart';
import 'package:mercantis_hub_app/pricing/price_resolver.dart';
import 'package:mercantis_hub_app/scheduling/scheduling_service.dart';
import 'package:mercantis_hub_app/ledger/ledger_values.dart' hide isTrue;
import 'package:mercantis_hub_app/manifest/hub_manifest.dart';
import 'package:mercantis_hub_app/modules/accounting/tax_return_builder.dart';
import 'package:mercantis_hub_app/onboarding/hub_seeder.dart';
import 'package:mercantis_hub_app/scheduling/appointment_reminder.dart';
import 'package:mercantis_hub_app/setup_library/builtin_packs.dart';
import 'package:mercantis_hub_app/setup_library/setup_pack_applier.dart';
import 'package:mercantis_hub_app/einvoicing/ubl_invoice.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The Clinic Pack demo, end to end on a FRESH book, through the full
/// production interceptor stack — the exact story to walk a GP prospect
/// through:
///
///   onboard → apply the clinic pack → register a patient → book with a
///   deposit → send the visit reminder → complete to a settled exempt
///   invoice → export the compliant e-invoice → see the VAT return →
///   and, one day, honour an erasure request without touching the books.
void main() {
  setUpAll(sqfliteFfiInit);

  test('a GP practice, from empty database to erasure request', () async {
    final db = await MercantisDatabase.open(
        factory: databaseFactoryFfi, path: inMemoryDatabasePath);
    addTearDown(() => db.close());
    final registry = MetadataRegistry(db.db);
    final sync = SyncEngine(database: db.db, registry: registry);
    await AppInstaller(database: db.db, registry: registry, syncEngine: sync)
        .install(HubManifest.build());
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
      deviceId: 'front-desk',
      userId: 'reception',
      // The app's full production interceptor stack.
      interceptors: const [
        BusinessProfileDefaultsInterceptor(),
        ItemNameDefaultInterceptor(),
        PriceResolutionInterceptor(),
        DiscountInterceptor(),
        LineItemTotalsInterceptor(),
        TaxCalculationInterceptor(),
        BomRollupInterceptor(),
        FiscalYearGuardInterceptor(),
        BooksLockGuardInterceptor(),
        NegativeStockGuardInterceptor(),
        GroupAccountPostingGuardInterceptor(),
        JournalBalanceGuardInterceptor(),
        DuplicateSupplierBillGuardInterceptor(),
        ExpenseDefaultsInterceptor(),
        DepositApplicationInterceptor(),
        AppointmentConflictInterceptor(),
      ],
    );
    final ledger = LedgerDerivationService(engine: engine, emitter: emitter);
    ledger.start();
    addTearDown(ledger.dispose);
    const roles = {'System Manager'};

    // ── 1. Onboarding: a fresh Maltese practice.
    await HubSeeder(engine).seed(
      businessName: 'Valletta Family Practice',
      currencyCode: 'EUR',
      year: DateTime.now().year,
    );
    final company = (await engine.list('Company', userRoles: roles)).single;
    expect(company.payload['country'], 'Malta');
    company.payload['tax_id'] = 'MT12345678'; // the practice's VAT number
    await engine.save(company, roles);

    // ── 2. One tap: the clinic pack (on its appointments dependency).
    final applier = SetupPackApplier(engine: engine);
    await applier.apply(appointmentsPack);
    final packResult = await applier.apply(clinicPack);
    expect(packResult.moduleToggles['appointments'], isTrue);

    // The practice sets its consultation fee.
    final consult = (await engine.fetch('Item', 'CONSULT'))!;
    consult.payload['standard_rate'] = 35;
    await engine.save(consult, roles);

    // ── 3. Register a patient — billing identity only.
    await engine.save(
        Document(id: '', docType: 'Customer', payload: {
          'customer_name': 'Maria Borg',
          'customer_type': 'Individual',
          'email': 'maria@example.com',
        }),
        roles);
    final patient =
        (await engine.list('Customer', userRoles: roles)).single;

    // ── 4. Book tomorrow 09:00 with a €10 deposit.
    final booking = BookingService(engine);
    final tomorrow9 = DateTime.now().add(const Duration(days: 1));
    final startsAt = DateTime(
        tomorrow9.year, tomorrow9.month, tomorrow9.day, 9, 0);
    final apt = await booking.book(
      resource: 'Doctor',
      customer: patient.id,
      serviceItem: 'CONSULT',
      subject: 'Consultation',
      startsAt: startsAt,
      endsAt: startsAt.add(const Duration(minutes: 30)),
      depositAmount: 10,
    );
    expect(asNonEmpty(apt.payload['deposit']), isNotNull);

    // ── 5. The visit reminder: due now, neutral text, sent once.
    final reminders = AppointmentReminderService(engine);
    final due = await reminders.dueReminders(DateTime.now());
    expect(due.map((a) => a.id), [apt.id]);
    final text = buildAppointmentReminder(
      customerName: '${patient.payload['customer_name']}',
      subject: '${apt.payload['subject']}',
      startsAt: startsAt,
      companyName: '${company.payload['company_name']}',
    );
    expect(text, contains('Maria Borg'));
    expect(text, contains('Consultation on'));
    expect(text, contains('Valletta Family Practice'));
    await reminders.markSent(apt.id);
    expect(await reminders.dueReminders(DateTime.now()), isEmpty);

    // ── 6. The visit happens: complete → a submitted, exempt invoice
    // with the deposit auto-applied.
    final invoice = await booking.completeBooking(apt.id);
    expect(invoice.docStatus, 1);
    expect(asNum(invoice.payload['total']), 35);
    expect(asNum(invoice.payload['tax_total']), 0); // exempt medical care
    expect(asNum(invoice.payload['grand_total']), 35);
    final settled = (await engine.fetch('Sales Invoice', invoice.id))!;
    expect(asNum(settled.payload['outstanding_amount']), 25); // 35 − 10

    // ── 7. The e-invoice: category E with the Article 132(1) reason.
    final xml = await UblExportService(engine).buildFor(invoice.id);
    expect(xml, contains('<cbc:ID>E</cbc:ID>'));
    expect(xml, contains('Article 132(1) of the VAT Directive'));
    expect(xml, isNot(contains('<cbc:ID>Z</cbc:ID>')));
    expect(xml, contains('<cbc:PayableAmount currencyID="EUR">35.00'));

    // ── 8. The VAT return: exempt supplies in their own Malta box.
    final today = DateTime.now().toIso8601String().split('T').first;
    final filing = await engine.save(
        Document(id: '', docType: 'Tax Filing', payload: {
          'title': 'Demo period',
          'tax_type': 'VAT',
          'jurisdiction': 'Malta',
          'from_date': '2000-01-01',
          'to_date': today,
        }),
        roles);
    final prepared =
        await TaxReturnService(engine: engine).prepare(filing.id);
    final boxes = {
      for (final b in prepared.children['boxes'] ?? const <ChildRow>[])
        '${b.payload['box_number']}': asNum(b.payload['amount']),
    };
    expect(boxes['M4a'], 35); // exempt supplies — value
    expect(boxes['M5'], 0); // no output VAT anywhere

    // ── 9. An erasure request arrives. The open balance blocks it —
    // then reception takes the €25 and it proceeds.
    final privacy = CustomerAnonymiseService(engine);
    await expectLater(
        privacy.anonymise(patient.id),
        throwsA(isA<StateError>().having(
            (e) => e.message, 'message', contains('outstanding'))));
    await engine.applyOnSubmitUpdate(
        settled..payload['outstanding_amount'] = 0, roles);

    final erased = await privacy.anonymise(patient.id);
    final after = (await engine.fetch('Customer', patient.id))!;
    expect(after.payload['customer_name'], erased.pseudonym);
    expect('${after.payload['customer_name']}', isNot(contains('Maria')));
    // The books survive, referencing only the pseudonym.
    final keptInvoice = (await engine.fetch('Sales Invoice', invoice.id))!;
    expect(keptInvoice.docStatus, 1);
    expect(keptInvoice.payload['customer'], patient.id);
    // The appointment kept its slot, lost its text.
    final keptApt = (await engine.fetch('Appointment', apt.id))!;
    expect(keptApt.payload['subject'], 'Appointment');
  });
}
