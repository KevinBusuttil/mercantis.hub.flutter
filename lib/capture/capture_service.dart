import 'dart:io';

import 'package:mercantis_core/mercantis_core.dart';

import '../ledger/ledger_values.dart';
import '../modules/capture/capture_module.dart';
import 'llm_receipt_extractor.dart';
import 'receipt_parser.dart';
import 'receipt_text_recognizer.dart';

/// Orchestrates Document Capture (ADR-049): intake → on-device OCR → prefill →
/// (on confirmation) a DRAFT Purchase Invoice. Pure logic over the engine,
/// attachment manager, and recogniser, so it's testable without any UI.
///
/// Conservative by construction: it only ever creates *draft* vouchers and
/// never submits. A weak OCR read becomes a "Needs Review" capture, not a
/// failure.
class CaptureService {
  CaptureService({
    required this.engine,
    required this.attachments,
    required this.recognizer,
    this.roles = const {'System Manager'},
    this.userId = 'local-user',
    this.llmExtractor,
    this.llmThreshold = 0.6,
    this.llmQuota,
  });

  final DocumentEngine engine;
  final AttachmentManager attachments;
  final ReceiptTextRecognizer recognizer;
  final Set<String> roles;
  final String userId;

  /// Opt-in AI fallback (ADR-049). Null when disabled / no key. Consulted only
  /// when the on-device read is weaker than [llmThreshold], and only if
  /// [llmQuota] (the monthly cost cap) permits the call.
  final LlmReceiptExtractor? llmExtractor;
  final double llmThreshold;
  final Future<bool> Function()? llmQuota;

  /// Confidence at/above which a parse is trusted enough to mark "Ready".
  static const readyThreshold = 0.6;

  /// Placeholder supplier used for a draft when no real supplier is chosen yet;
  /// the reviewer changes it on the draft. (We never auto-create a supplier
  /// from the extracted merchant name.)
  static const unspecifiedSupplierId = 'Unspecified Supplier';

  /// Placeholder item for the single expense line of a captured receipt — the
  /// scan isn't matched to a catalogue item, but the line table requires one.
  /// A non-stock service item so the draft carries no stock implication; the
  /// reviewer can re-itemise on the draft.
  static const unspecifiedItemId = 'Uncategorised';

  /// Full intake: persist the record, attach the image, OCR + parse, prefill.
  Future<Document> captureFromImage({
    required String imagePath,
    String sourceType = 'Camera',
    String intendedRole = CaptureModule.roleAnyone,
  }) async {
    // Create the intake record first so the attachment has a parent id.
    final created = await engine.save(
      Document(id: '', docType: 'Captured Document', payload: {
        'status': CaptureModule.statusReceived,
        'source_type': sourceType,
        'intended_role': intendedRole,
      }),
      roles,
    );

    final bytes = await File(imagePath).readAsBytes();
    await attachments.attach(
      documentId: created.id,
      docType: 'Captured Document',
      fieldKey: CaptureModule.documentFileFieldKey,
      fileName: _basename(imagePath),
      mimeType: _mimeFor(imagePath),
      data: bytes,
      userId: userId,
    );

    final text = await recognizer.recognise(imagePath);
    var parsed =
        text == null ? const ParsedReceipt() : ReceiptParser.parse(text);

    // AI fallback: only when the local read is weak, the user enabled it, and
    // the monthly cap allows. The LLM result wins where present; local fills
    // the gaps. Any failure leaves the local parse untouched.
    final extractor = llmExtractor;
    if (extractor != null && parsed.confidence < llmThreshold) {
      if (llmQuota == null || await llmQuota!()) {
        final ai = await extractor.extract(
            imageBytes: bytes, mimeType: _mimeFor(imagePath), ocrText: text);
        if (ai != null && !ai.isEmpty) parsed = _mergeReceipts(ai, parsed);
      }
    }

    return applyExtraction(created, parsed);
  }

  /// Combine two parses: [primary] wins per-field, [fallback] fills nulls.
  static ParsedReceipt _mergeReceipts(
          ParsedReceipt primary, ParsedReceipt fallback) =>
      ParsedReceipt(
        merchantName: primary.merchantName ?? fallback.merchantName,
        documentDate: primary.documentDate ?? fallback.documentDate,
        invoiceNo: primary.invoiceNo ?? fallback.invoiceNo,
        netTotal: primary.netTotal ?? fallback.netTotal,
        vatTotal: primary.vatTotal ?? fallback.vatTotal,
        grandTotal: primary.grandTotal ?? fallback.grandTotal,
        currencyCode: primary.currencyCode ?? fallback.currencyCode,
        confidence: primary.confidence > fallback.confidence
            ? primary.confidence
            : fallback.confidence,
      );

  /// Write parsed fields onto [capture] and set its review status. A confident
  /// read with a total lands in "Ready"; anything weaker is "Needs Review".
  Future<Document> applyExtraction(Document capture, ParsedReceipt parsed) async {
    final currencyOk = parsed.currencyCode != null &&
        await _exists('Currency', parsed.currencyCode!);
    // Merchant memory: if we've seen this merchant before, prefill the supplier
    // we learned — unless one is already set.
    final learnedSupplier =
        asNonEmpty(capture.payload['supplier']) == null && parsed.merchantName != null
            ? await _rememberedSupplier(parsed.merchantName!)
            : null;
    capture.payload.addAll({
      if (parsed.merchantName != null) 'merchant_name': parsed.merchantName,
      if (parsed.documentDate != null) 'document_date': parsed.documentDate,
      if (parsed.invoiceNo != null) 'invoice_no': parsed.invoiceNo,
      if (parsed.netTotal != null) 'net_total': parsed.netTotal,
      if (parsed.vatTotal != null) 'vat_total': parsed.vatTotal,
      if (parsed.grandTotal != null) 'grand_total': parsed.grandTotal,
      if (currencyOk) 'currency': parsed.currencyCode,
      if (learnedSupplier != null) 'supplier': learnedSupplier,
      'extraction_confidence': (parsed.confidence * 100).round(),
      'status': parsed.confidence >= readyThreshold && parsed.grandTotal != null
          ? CaptureModule.statusReady
          : CaptureModule.statusNeedsReview,
    });
    return engine.save(capture, roles);
  }

  /// The supplier learned for [merchant] from a prior draft, or null.
  Future<String?> _rememberedSupplier(String merchant) async {
    final key = CaptureModule.merchantKey(merchant);
    if (key.isEmpty) return null;
    final rule = await engine.fetch('Capture Rule', key);
    return rule == null ? null : asNonEmpty(rule.payload['supplier']);
  }

  /// Remember merchant→supplier so the next capture from this merchant prefills
  /// it. Skips the placeholder supplier — we only learn real choices.
  Future<void> _learnSupplier(Document capture, String supplierId) async {
    final merchant = asNonEmpty(capture.payload['merchant_name']);
    if (merchant == null || supplierId == unspecifiedSupplierId) return;
    final key = CaptureModule.merchantKey(merchant);
    if (key.isEmpty) return;
    final existing = await engine.fetch('Capture Rule', key);
    final seen =
        existing == null ? 1 : (asNum(existing.payload['times_seen']) + 1).toInt();
    await engine.save(
      Document(id: key, docType: 'Capture Rule', payload: {
        'merchant_name': merchant,
        'supplier': supplierId,
        'times_seen': seen,
      }),
      roles,
    );
  }

  /// Create a DRAFT Purchase Invoice from a confirmed [capture]. Copies the
  /// receipt image onto the invoice, links it back, and marks the capture
  /// "Draft Created". Never submits — the user completes & posts it later.
  Future<Document> createDraftInvoice(Document capture, {String? supplierId}) async {
    final supplier = supplierId ?? await _ensureUnspecifiedSupplier();
    final item = await _ensureUnspecifiedItem();
    final grand = asNum(capture.payload['grand_total']);
    final merchant = asNonEmpty(capture.payload['merchant_name']);

    final invoice = Document(
      id: '',
      docType: 'Purchase Invoice',
      company: await _companyId(),
      payload: {
        'supplier': supplier,
        'posting_date': _postingDate(capture),
        if (asNonEmpty(capture.payload['invoice_no']) != null)
          'supplier_invoice_no': capture.payload['invoice_no'],
        if (asNonEmpty(capture.payload['currency']) != null)
          'currency': capture.payload['currency'],
      },
    );
    invoice.children['items'] = [
      ChildRow(
        id: '',
        parentId: '',
        parentDocType: 'Purchase Invoice',
        tableName: 'items',
        rowIndex: 0,
        payload: {
          'item': item,
          'description':
              merchant == null ? 'Captured receipt' : '$merchant — receipt',
          'qty': 1,
          'rate': grand,
        },
      ),
    ];
    final saved = await engine.save(invoice, roles);

    await _copyImageToVoucher(capture, saved);

    capture.payload['linked_voucher'] = saved.id;
    capture.payload['voucher_type'] = 'Purchase Invoice';
    capture.payload['status'] = CaptureModule.statusDraftCreated;
    if (supplierId != null) capture.payload['supplier'] = supplierId;
    await engine.save(capture, roles);

    // Remember this merchant→supplier so the next capture prefills it.
    await _learnSupplier(capture, supplier);
    return saved;
  }

  // — internals —

  Future<String> _ensureUnspecifiedSupplier() async {
    if (await engine.fetch('Supplier', unspecifiedSupplierId) == null) {
      await engine.save(
        Document(id: unspecifiedSupplierId, docType: 'Supplier', payload: {
          'supplier_name': unspecifiedSupplierId,
          'supplier_type': 'Company',
        }),
        roles,
      );
    }
    return unspecifiedSupplierId;
  }

  Future<String> _ensureUnspecifiedItem() async {
    if (await engine.fetch('Item', unspecifiedItemId) == null) {
      await engine.save(
        Document(id: unspecifiedItemId, docType: 'Item', payload: {
          'item_code': unspecifiedItemId,
          'item_name': unspecifiedItemId,
          'is_stock_item': 0,
          'is_service_item': 1,
        }),
        roles,
      );
    }
    return unspecifiedItemId;
  }

  Future<String?> _companyId() async {
    final companies = await engine.list('Company', userRoles: roles);
    return companies.isEmpty ? null : companies.first.id;
  }

  Future<bool> _exists(String docType, String id) async =>
      await engine.fetch(docType, id) != null;

  /// Booking date for the draft: the receipt's date when it's in the current
  /// calendar year (so the fiscal-year guard accepts it), otherwise today.
  String _postingDate(Document capture) {
    final today = DateTime.now();
    final iso = asNonEmpty(capture.payload['document_date']);
    if (iso != null && iso.startsWith('${today.year}-')) return iso;
    return today.toIso8601String().split('T').first;
  }

  Future<void> _copyImageToVoucher(Document capture, Document voucher) async {
    final files = await attachments.attachmentsForField(
        CaptureModule.documentFileFieldKey, capture.id);
    if (files.isEmpty) return;
    final source = files.first;
    final bytes = await attachments.read(source);
    await attachments.attach(
      documentId: voucher.id,
      docType: voucher.docType,
      fieldKey: CaptureModule.documentFileFieldKey,
      fileName: source.fileName,
      mimeType: source.mimeType,
      data: bytes,
      userId: userId,
    );
  }

  static String _basename(String path) => path.split(RegExp(r'[\\/]')).last;

  static String _mimeFor(String path) {
    final name = _basename(path).toLowerCase();
    final dot = name.lastIndexOf('.');
    switch (dot < 0 ? '' : name.substring(dot)) {
      case '.png':
        return 'image/png';
      case '.heic':
        return 'image/heic';
      case '.pdf':
        return 'application/pdf';
      case '.jpg':
      case '.jpeg':
      default:
        return 'image/jpeg';
    }
  }
}
