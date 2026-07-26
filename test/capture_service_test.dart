import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_hub_app/capture/capture_service.dart';
import 'package:mercantis_hub_app/capture/llm_receipt_extractor.dart';
import 'package:mercantis_hub_app/capture/receipt_parser.dart';
import 'package:mercantis_hub_app/capture/receipt_text_recognizer.dart';
import 'package:mercantis_hub_app/manifest/hub_manifest.dart';
import 'package:mercantis_hub_app/modules/capture/capture_module.dart';
import 'package:mercantis_hub_app/onboarding/hub_seeder.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// ADR-049: the capture orchestration. Drives intake → prefill → draft Purchase
/// Invoice against a real in-memory engine with the full Hub manifest installed
/// and seeded, using the off-device (no-OCR) recogniser.
void main() {
  setUpAll(sqfliteFfiInit);

  late MercantisDatabase db;
  late Directory storeDir;
  late DocumentEngine engine;
  late AttachmentManager attachments;
  late CaptureService service;
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
      interceptors: const [],
    );
    await HubSeeder(engine, roles: roles).seed(
        businessName: 'Acme', currencyCode: 'EUR', year: DateTime.now().year);
    storeDir = await Directory.systemTemp.createTemp('cap-store-');
    attachments = AttachmentManager(db.db, AttachmentStore(storeDir.path),
        syncEngine: sync, deviceId: 'devA');
    service = CaptureService(
      engine: engine,
      attachments: attachments,
      recognizer: const UnavailableTextRecognizer(),
      roles: roles,
      userId: 'u',
    );
  });

  tearDown(() async {
    await db.close();
    if (await storeDir.exists()) await storeDir.delete(recursive: true);
  });

  File imageFile(String name, int seed) =>
      File('${storeDir.path}/$name')..writeAsBytesSync(List.filled(64, seed));

  test('captureFromImage persists, attaches, and (no OCR) needs review', () async {
    final capture = await service.captureFromImage(
        imagePath: imageFile('r.jpg', 1).path, sourceType: 'Upload');

    expect(capture.docType, 'Captured Document');
    expect(capture.id, startsWith('CAP-'));
    expect(capture.payload['source_type'], 'Upload');
    // No on-device OCR ⇒ nothing extracted ⇒ routed to manual review.
    expect(capture.payload['status'], CaptureModule.statusNeedsReview);

    final files =
        await attachments.attachmentsForField('document_file', capture.id);
    expect(files, hasLength(1));
  });

  test('applyExtraction prefills fields and marks a confident read Ready',
      () async {
    final created = await engine.save(
        Document(id: '', docType: 'Captured Document', payload: {
          'status': CaptureModule.statusReceived,
        }),
        roles);
    final capture = await service.applyExtraction(
      created,
      const ParsedReceipt(
        merchantName: 'BP Service Station',
        documentDate: '2026-03-14',
        invoiceNo: '4471',
        netTotal: 38.39,
        vatTotal: 6.91,
        grandTotal: 45.30,
        currencyCode: 'EUR',
        confidence: 0.9,
      ),
    );

    expect(capture.payload['status'], CaptureModule.statusReady);
    expect(capture.payload['merchant_name'], 'BP Service Station');
    expect(capture.payload['grand_total'], 45.30);
    expect(capture.payload['extraction_confidence'], 90);
    // EUR is seeded, so the link is accepted.
    expect(capture.payload['currency'], 'EUR');
  });

  test('applyExtraction drops an unknown currency link', () async {
    final created = await engine.save(
        Document(id: '', docType: 'Captured Document', payload: {}), roles);
    final capture = await service.applyExtraction(
      created,
      const ParsedReceipt(grandTotal: 9.99, currencyCode: 'XXX', confidence: 0.7),
    );
    // 'XXX' isn't a seeded currency ⇒ not written (would fail link
    // validation otherwise). GBP no longer qualifies here — the seeder
    // now lays down all the majors.
    expect(capture.payload.containsKey('currency'), isFalse);
    expect(capture.payload['status'], CaptureModule.statusReady);
  });

  test('createDraftInvoice builds a draft PI, links back, copies the image',
      () async {
    final created = await engine.save(
        Document(id: '', docType: 'Captured Document', payload: {
          'status': CaptureModule.statusReady,
          'merchant_name': 'BP',
          'invoice_no': '4471',
          'grand_total': 45.30,
        }),
        roles);
    await attachments.attach(
      documentId: created.id,
      docType: 'Captured Document',
      fieldKey: 'document_file',
      fileName: 'r.jpg',
      mimeType: 'image/jpeg',
      data: imageFile('r2.jpg', 2).readAsBytesSync(),
      userId: 'u',
    );

    final pi = await service.createDraftInvoice(created);

    expect(pi.docType, 'Purchase Invoice');
    expect(pi.docStatus, 0); // DRAFT — never submitted
    expect(pi.payload['supplier'], CaptureService.unspecifiedSupplierId);
    expect(pi.payload['supplier_invoice_no'], '4471');
    expect(pi.children['items']!.single.payload['rate'], 45.30);

    // The placeholder supplier was created on demand.
    expect(await engine.fetch('Supplier', CaptureService.unspecifiedSupplierId),
        isNotNull);

    // The capture is linked and marked done.
    final reloaded = (await engine.fetch('Captured Document', created.id))!;
    expect(reloaded.payload['status'], CaptureModule.statusDraftCreated);
    expect(reloaded.payload['linked_voucher'], pi.id);
    expect(reloaded.payload['voucher_type'], 'Purchase Invoice');

    // The receipt image rode along to the invoice.
    final piFiles =
        await attachments.attachmentsForField('document_file', pi.id);
    expect(piFiles, hasLength(1));
  });

  test('AI fallback fills the fields when the on-device read is weak', () async {
    // No OCR ⇒ local confidence 0 ⇒ below threshold ⇒ the AI extractor runs.
    final aiClient = MockClient((_) async => http.Response(
          jsonEncode({
            'content': [
              {
                'type': 'text',
                'text': jsonEncode({
                  'merchant_name': 'Corner Cafe',
                  'grand_total': 5.20,
                  'document_date': '2026-02-07',
                }),
              },
            ],
          }),
          200,
        ));
    final aiService = CaptureService(
      engine: engine,
      attachments: attachments,
      recognizer: const UnavailableTextRecognizer(),
      roles: roles,
      userId: 'u',
      llmExtractor: LlmReceiptExtractor(
        provider: LlmProvider.anthropic,
        endpoint: LlmReceiptExtractor.anthropicBaseUrl,
        model: 'claude-opus-4-8',
        apiKey: 'k',
        client: aiClient,
      ),
    );

    final capture = await aiService.captureFromImage(
        imagePath: imageFile('ai.jpg', 9).path);

    expect(capture.payload['merchant_name'], 'Corner Cafe');
    expect(capture.payload['grand_total'], 5.20);
    // A confident AI read with a total lands Ready, not Needs Review.
    expect(capture.payload['status'], CaptureModule.statusReady);
  });

  test('AI fallback respects the monthly quota gate', () async {
    var called = false;
    final aiService = CaptureService(
      engine: engine,
      attachments: attachments,
      recognizer: const UnavailableTextRecognizer(),
      roles: roles,
      userId: 'u',
      llmExtractor: LlmReceiptExtractor(
        provider: LlmProvider.anthropic,
        endpoint: LlmReceiptExtractor.anthropicBaseUrl,
        model: 'claude-opus-4-8',
        apiKey: 'k',
        client: MockClient((_) async {
          called = true;
          return http.Response('{}', 200);
        }),
      ),
      llmQuota: () async => false, // cap reached
    );

    final capture = await aiService.captureFromImage(
        imagePath: imageFile('q.jpg', 3).path);

    expect(called, isFalse); // quota denied ⇒ no network call
    expect(capture.payload['status'], CaptureModule.statusNeedsReview);
  });

  test('merchant memory: learns a supplier and prefills the next capture',
      () async {
    await engine.save(
        Document(id: 'ACME-SUP', docType: 'Supplier', payload: {
          'supplier_name': 'Acme Supplies',
          'supplier_type': 'Company',
        }),
        roles);

    // First receipt from "Corner Cafe": user picks Acme as the supplier.
    final first = await engine.save(
        Document(id: '', docType: 'Captured Document', payload: {
          'merchant_name': 'Corner Cafe',
          'grand_total': 5.20,
        }),
        roles);
    await service.createDraftInvoice(first, supplierId: 'ACME-SUP');

    // The mapping was remembered.
    final rule = await engine.fetch('Capture Rule',
        CaptureModule.merchantKey('Corner Cafe'));
    expect(rule, isNotNull);
    expect(rule!.payload['supplier'], 'ACME-SUP');
    expect(rule.payload['times_seen'], 1);

    // A *new* capture from the same merchant auto-fills the supplier.
    final second = await engine.save(
        Document(id: '', docType: 'Captured Document', payload: {}), roles);
    final prefilled = await service.applyExtraction(
      second,
      const ParsedReceipt(
          merchantName: 'CORNER CAFE #12', grandTotal: 3.10, confidence: 0.7),
    );
    expect(prefilled.payload['supplier'], 'ACME-SUP');
  });

  test('createDraftInvoice honours an explicitly chosen supplier', () async {
    await engine.save(
        Document(id: 'ACME-SUP', docType: 'Supplier', payload: {
          'supplier_name': 'Acme Supplies',
          'supplier_type': 'Company',
        }),
        roles);
    final created = await engine.save(
        Document(id: '', docType: 'Captured Document', payload: {
          'grand_total': 12.50,
        }),
        roles);

    final pi = await service.createDraftInvoice(created, supplierId: 'ACME-SUP');
    expect(pi.payload['supplier'], 'ACME-SUP');
    final reloaded = (await engine.fetch('Captured Document', created.id))!;
    expect(reloaded.payload['supplier'], 'ACME-SUP');
  });
}
