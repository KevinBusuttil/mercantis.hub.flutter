import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_hub_app/einvoicing/hub_einvoice_actions.dart';
import 'package:mercantis_hub_app/einvoicing/ubl_invoice.dart';
import 'package:mercantis_hub_app/modules/common/countries.dart';
import 'package:mercantis_hub_app/ledger/hub_interceptors.dart';
import 'package:mercantis_hub_app/ledger/ledger_values.dart' hide isTrue;
import 'package:mercantis_hub_app/manifest/hub_manifest.dart';
import 'package:mercantis_hub_app/setup_library/builtin_packs.dart';
import 'package:mercantis_hub_app/setup_library/setup_pack_applier.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// S13: a submitted Sales Invoice renders as EN 16931-compliant UBL 2.1
/// — PEPPOL BIS 3.0 customization, both parties with VAT ids and ISO
/// countries, the VAT breakdown by category, and totals that add up.
void main() {
  setUpAll(sqfliteFfiInit);

  late MercantisDatabase db;
  late DocumentEngine engine;
  late UblExportService ubl;
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
      userId: 'kevin',
      interceptors: const [
        LineItemTotalsInterceptor(),
        TaxCalculationInterceptor(),
      ],
    );
    ubl = UblExportService(engine);

    await engine.save(
        Document(id: 'BTL', docType: 'Company', payload: {
          'company_name': 'Busuttil Technologies Ltd',
          'abbr': 'BTL',
          'country': 'Malta',
          'tax_id': 'MT12345678',
        }),
        roles);
    await engine.save(
        Document(id: 'EUR', docType: 'Currency', payload: {
          'currency_name': 'Euro', 'symbol': '€',
        }),
        roles);
    await engine.save(
        Document(id: 'CUST-IT', docType: 'Customer', payload: {
          'customer_name': 'Rossi & Figli SRL',
          'customer_type': 'Company',
          'tax_id': 'IT99887766554',
          'country': 'Italy',
        }),
        roles);
    await engine.save(
        Document(id: 'VAT18', docType: 'Tax Code', payload: {
          'tax_code_name': 'VAT 18%', 'tax_type': 'VAT', 'rate': 18,
        }),
        roles);
    await engine.save(
        Document(id: 'WIDGET', docType: 'Item', payload: {
          'item_code': 'WIDGET', 'item_name': 'Widget',
          'item_type': 'Service', 'stock_uom': 'Nos',
        }),
        roles);
  });

  tearDown(() async => db.close());

  Future<Document> submittedInvoice() async {
    final invoice = Document(id: '', docType: 'Sales Invoice', payload: {
      'customer': 'CUST-IT',
      'posting_date': '2026-07-12',
      'due_date': '2026-08-11',
      'currency': 'EUR',
    });
    invoice.children['items'] = [
      ChildRow(
        id: '', parentId: '', parentDocType: 'Sales Invoice',
        tableName: 'items', rowIndex: 0,
        payload: {
          'item': 'WIDGET', 'qty': 2, 'rate': 100, 'uom': 'Nos',
          'tax_code': 'VAT18',
        },
      ),
      ChildRow(
        id: '', parentId: '', parentDocType: 'Sales Invoice',
        tableName: 'items', rowIndex: 1,
        payload: {
          'item': 'WIDGET', 'qty': 1, 'rate': 50, 'uom': 'Hour',
          'description': 'Fitting <on site>',
        },
      ),
    ];
    return engine.submit(await engine.save(invoice, roles), roles);
  }

  test('a submitted invoice renders compliant UBL with the VAT breakdown',
      () async {
    final invoice = await submittedInvoice();
    final xml = await ubl.buildFor(invoice.id);

    // Envelope and identity.
    expect(xml, contains(UblInvoiceBuilder.customizationId));
    expect(xml, contains('<cbc:ID>${invoice.id}</cbc:ID>'));
    expect(xml, contains('<cbc:IssueDate>2026-07-12</cbc:IssueDate>'));
    expect(xml, contains('<cbc:DueDate>2026-08-11</cbc:DueDate>'));
    expect(xml, contains('<cbc:InvoiceTypeCode>380</cbc:InvoiceTypeCode>'));
    expect(xml,
        contains('<cbc:DocumentCurrencyCode>EUR</cbc:DocumentCurrencyCode>'));

    // Parties: names escaped, VAT ids, ISO countries from free text.
    expect(xml, contains('Busuttil Technologies Ltd'));
    expect(xml, contains('<cbc:CompanyID>MT12345678</cbc:CompanyID>'));
    expect(xml,
        contains('<cbc:IdentificationCode>MT</cbc:IdentificationCode>'));
    expect(xml, contains('Rossi &amp; Figli SRL'));
    expect(xml, contains('<cbc:CompanyID>IT99887766554</cbc:CompanyID>'));
    expect(xml,
        contains('<cbc:IdentificationCode>IT</cbc:IdentificationCode>'));

    // VAT breakdown: 200 standard-rated at 18% (36.00) + 50 zero-rated.
    expect(xml, contains('<cbc:TaxableAmount currencyID="EUR">200.00'));
    expect(xml, contains('<cbc:TaxAmount currencyID="EUR">36.00'));
    expect(xml, contains('<cbc:TaxableAmount currencyID="EUR">50.00'));
    expect(xml, contains('<cbc:ID>S</cbc:ID>'));
    expect(xml, contains('<cbc:ID>Z</cbc:ID>'));

    // Totals add up: 250 net, 286 payable.
    expect(xml,
        contains('<cbc:TaxExclusiveAmount currencyID="EUR">250.00'));
    expect(xml,
        contains('<cbc:PayableAmount currencyID="EUR">286.00'));

    // Lines: unit codes mapped, description escaped, price present.
    expect(xml, contains('unitCode="C62"'));
    expect(xml, contains('unitCode="HUR"'));
    expect(xml, contains('Fitting &lt;on site&gt;'));
    expect(xml, contains('<cbc:PriceAmount currencyID="EUR">100.00'));
  });

  // B-1 (Clinic Pack): exempt is a LEGAL state, not a 0% rate. A GP's
  // consultation must export as category E with the exemption reason —
  // exporting it zero-rated (Z) misstates the supply.
  test('an exempt invoice exports category E with the exemption reason',
      () async {
    await engine.save(
        Document(id: 'EXEMPT', docType: 'Tax Code', payload: {
          'tax_code_name': 'Exempt',
          'tax_type': 'VAT',
          'rate': 0,
          'vat_category': 'Exempt',
          'exemption_reason':
              'Exempt from VAT — medical care (Article 132(1) of the '
                  'VAT Directive)',
        }),
        roles);
    final invoice = Document(id: '', docType: 'Sales Invoice', payload: {
      'customer': 'CUST-IT',
      'posting_date': '2026-07-12',
      'currency': 'EUR',
    });
    invoice.children['items'] = [
      ChildRow(
        id: '', parentId: '', parentDocType: 'Sales Invoice',
        tableName: 'items', rowIndex: 0,
        payload: {
          'item': 'WIDGET', 'qty': 1, 'rate': 40, 'uom': 'Nos',
          'description': 'Consultation',
          'tax_code': 'EXEMPT',
        },
      ),
    ];
    final submitted =
        await engine.submit(await engine.save(invoice, roles), roles);

    final xml = await ubl.buildFor(submitted.id);

    // Breakdown: one E subtotal carrying the reason — and no Z at all.
    expect(xml, contains('<cbc:ID>E</cbc:ID>'));
    expect(
        xml,
        contains('<cbc:TaxExemptionReason>Exempt from VAT — medical care '
            '(Article 132(1) of the VAT Directive)</cbc:TaxExemptionReason>'));
    expect(xml, isNot(contains('<cbc:ID>Z</cbc:ID>')));
    expect(xml, contains('<cbc:TaxableAmount currencyID="EUR">40.00'));
    expect(xml, contains('<cbc:TaxAmount currencyID="EUR">0.00'));
    // The whole invoice owes exactly its net.
    expect(xml, contains('<cbc:PayableAmount currencyID="EUR">40.00'));
  });

  // B-2 acceptance: pack-seeded masters carry everything the export
  // needs — apply the pack, invoice a consultation, get a compliant
  // exempt e-invoice, no manual tax setup in between.
  test('a clinic-pack consultation exports exempt with the medical reason',
      () async {
    await SetupPackApplier(engine: engine).apply(clinicPack);

    final invoice = Document(id: '', docType: 'Sales Invoice', payload: {
      'customer': 'CUST-IT',
      'posting_date': '2026-07-12',
      'currency': 'EUR',
    });
    invoice.children['items'] = [
      ChildRow(
        id: '', parentId: '', parentDocType: 'Sales Invoice',
        tableName: 'items', rowIndex: 0,
        payload: {'item': 'CONSULT', 'qty': 1, 'rate': 25, 'uom': 'Nos'},
      ),
    ];
    final submitted =
        await engine.submit(await engine.save(invoice, roles), roles);

    final xml = await ubl.buildFor(submitted.id);

    expect(xml, contains('<cbc:ID>E</cbc:ID>'));
    expect(xml, contains('Article 132(1) of the VAT Directive'));
    expect(xml, isNot(contains('<cbc:ID>Z</cbc:ID>')));
    expect(xml, contains('<cbc:PayableAmount currencyID="EUR">25.00'));
  });

  test('two 0% codes (Exempt vs Zero-Rated) never merge in the fallback',
      () {
    // No persisted taxes rows → the recompute fallback groups lines; the
    // two legally different 0% codes must yield SEPARATE subtotals.
    final invoice = Document(
        id: 'SI-F', docType: 'Sales Invoice', docStatus: 1, payload: {
      'customer': 'CUST-IT',
      'posting_date': '2026-07-12',
      'currency': 'EUR',
    });
    invoice.children['items'] = [
      ChildRow(
        id: '', parentId: 'SI-F', parentDocType: 'Sales Invoice',
        tableName: 'items', rowIndex: 0,
        payload: {'item': 'A', 'qty': 1, 'rate': 30, 'tax_code': 'EXEMPT'},
      ),
      ChildRow(
        id: '', parentId: 'SI-F', parentDocType: 'Sales Invoice',
        tableName: 'items', rowIndex: 1,
        payload: {'item': 'B', 'qty': 1, 'rate': 20, 'tax_code': 'ZR'},
      ),
    ];
    final xml = UblInvoiceBuilder.build(
      invoice: invoice,
      seller: Document(id: 'BTL', docType: 'Company', payload: {
        'company_name': 'Busuttil Technologies Ltd',
        'tax_id': 'MT12345678',
        'country': 'Malta',
      }),
      buyer: Document(id: 'CUST-IT', docType: 'Customer', payload: {
        'customer_name': 'Rossi & Figli SRL',
        'country': 'Italy',
      }),
      taxRateByCode: const {'EXEMPT': 0, 'ZR': 0},
      vatClassByCode: const {
        'EXEMPT': (category: 'Exempt', reason: 'Exempt from VAT'),
        'ZR': (category: 'Zero-Rated', reason: null),
      },
    );

    expect(xml, contains('<cbc:ID>E</cbc:ID>'));
    expect(xml, contains('<cbc:ID>Z</cbc:ID>'));
    expect(xml, contains('<cbc:TaxableAmount currencyID="EUR">30.00'));
    expect(xml, contains('<cbc:TaxableAmount currencyID="EUR">20.00'));
    expect(xml,
        contains('<cbc:TaxExemptionReason>Exempt from VAT</cbc:TaxExemptionReason>'));
  });

  // Codex P1 (PR #169): the export must mirror the POSTED tax calc.
  test('item-master and customer fallback rates reach the UBL breakdown',
      () async {
    await engine.save(
        Document(id: 'CONSULT', docType: 'Item', payload: {
          'item_code': 'CONSULT', 'item_name': 'Consulting',
          'item_type': 'Service', 'stock_uom': 'Nos',
          'tax_code': 'VAT18', // the ITEM carries the code
        }),
        roles);
    final invoice = Document(id: '', docType: 'Sales Invoice', payload: {
      'customer': 'CUST-IT',
      'posting_date': '2026-07-12',
      // No document tax_code, no line tax_code.
    });
    invoice.children['items'] = [
      ChildRow(
        id: '', parentId: '', parentDocType: 'Sales Invoice',
        tableName: 'items', rowIndex: 0,
        payload: {'item': 'CONSULT', 'qty': 1, 'rate': 100},
      ),
    ];
    final posted =
        await engine.submit(await engine.save(invoice, roles), roles);
    // The interceptor found VAT18 through the item: 118 posted.
    expect(asNum(posted.payload['grand_total']), 118);

    final xml = await ubl.buildFor(posted.id);
    // Previously this exported as zero-rated with a 100.00 payable —
    // diverging from the posted document. Now it mirrors it.
    expect(xml, contains('<cbc:TaxableAmount currencyID="EUR">100.00'));
    expect(xml, contains('<cbc:TaxAmount currencyID="EUR">18.00'));
    expect(xml, contains('<cbc:Percent>18.00</cbc:Percent>'));
    expect(xml, isNot(contains('<cbc:ID>Z</cbc:ID>')));
    expect(
        xml, contains('<cbc:PayableAmount currencyID="EUR">118.00'));
  });

  test('prices-include-tax invoices export extracted nets, not gross',
      () async {
    final invoice = Document(id: '', docType: 'Sales Invoice', payload: {
      'customer': 'CUST-IT',
      'posting_date': '2026-07-12',
      'prices_include_tax': 1,
    });
    invoice.children['items'] = [
      ChildRow(
        id: '', parentId: '', parentDocType: 'Sales Invoice',
        tableName: 'items', rowIndex: 0,
        payload: {
          'item': 'WIDGET', 'qty': 1, 'rate': 118, 'tax_code': 'VAT18',
        },
      ),
    ];
    final posted =
        await engine.submit(await engine.save(invoice, roles), roles);
    expect(asNum(posted.payload['grand_total']), 118); // entered gross

    final xml = await ubl.buildFor(posted.id);
    // The contained tax is extracted, exactly as it posted.
    expect(xml, contains('<cbc:TaxableAmount currencyID="EUR">100.00'));
    expect(xml, contains('<cbc:TaxAmount currencyID="EUR">18.00'));
    expect(xml,
        contains('<cbc:TaxExclusiveAmount currencyID="EUR">100.00'));
    expect(
        xml, contains('<cbc:PayableAmount currencyID="EUR">118.00'));
    expect(xml,
        contains('<cbc:LineExtensionAmount currencyID="EUR">100.00'));
  });

  test('drafts and incomplete masters are refused with every gap named',
      () async {
    // A draft is not a fiscal document.
    final draft = await engine.save(
        Document(id: '', docType: 'Sales Invoice', payload: {
          'customer': 'CUST-IT', 'posting_date': '2026-07-12',
        })
          ..children['items'] = [
            ChildRow(
              id: '', parentId: '', parentDocType: 'Sales Invoice',
              tableName: 'items', rowIndex: 0,
              payload: {'item': 'WIDGET', 'qty': 1, 'rate': 10},
            ),
          ],
        roles);
    await expectLater(
      ubl.buildFor(draft.id),
      throwsA(isA<StateError>()
          .having((e) => '$e', 'message', contains('submitted'))),
    );

    // A seller without a VAT id blocks with the field named.
    final company = await engine.fetch('Company', 'BTL');
    company!.payload['tax_id'] = '';
    company.payload['country'] = '';
    await engine.save(company, roles);
    final invoice = await submittedInvoice();
    await expectLater(
      ubl.buildFor(invoice.id),
      throwsA(isA<StateError>().having((e) => '$e', 'message',
          allOf(contains('BT-31'), contains('BT-40')))),
    );
  });

  test('the action offers only on submitted Sales Invoices', () async {
    final invoice = await submittedInvoice();
    const docType = DocType(
        id: 'Sales Invoice', name: 'Sales Invoice', module: 'Selling');
    expect(hubEInvoiceActionsFor(invoice, docType), hasLength(1));

    final draft = Document(id: 'X', docType: 'Sales Invoice');
    expect(hubEInvoiceActionsFor(draft, docType), isEmpty);
    const other =
        DocType(id: 'Quotation', name: 'Quotation', module: 'Selling');
    expect(hubEInvoiceActionsFor(invoice, other), isEmpty);
  });

  test('country codes resolve from text, 2-letter codes, or VAT prefixes',
      () {
    expect(UblInvoiceBuilder.countryCode('Malta'), 'MT');
    expect(UblInvoiceBuilder.countryCode('DE'), 'DE');
    expect(UblInvoiceBuilder.countryCode('', vatId: 'FR123456'), 'FR');
    expect(UblInvoiceBuilder.countryCode('Atlantis'), isNull);
  });

  test('every country pick-list entry resolves to an ISO code', () {
    // The select list and the UBL map must never drift apart: a country
    // a user can pick MUST export as a valid seller/buyer country.
    for (final name in kCountryOptions.split('\n')) {
      expect(UblInvoiceBuilder.countryCode(name), isNotNull,
          reason: '"$name" has no ISO mapping');
    }
  });
}
