import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

import '../ledger/ledger_values.dart';
import '../modules/capture/capture_module.dart';
import 'capture_service.dart';
import 'capture_settings_providers.dart';
import 'llm_receipt_extractor.dart';
import 'receipt_text_recognizer.dart';

/// The capture orchestration service, wired to the live engine, attachment
/// manager, on-device recogniser, and the signed-in operator.
final captureServiceProvider = FutureProvider<CaptureService>((ref) async {
  final engine = await ref.watch(documentEngineProvider.future);
  final attachments = await ref.watch(attachmentManagerProvider.future);
  final recognizer = ref.watch(receiptTextRecognizerProvider);
  final user = ref.watch(currentUserProvider);

  // Build the opt-in AI fallback only when enabled and a key is present.
  final ai = await ref.watch(captureAiSettingsProvider.future);
  final apiKey = await ref.watch(captureAiApiKeyProvider.future);
  LlmReceiptExtractor? extractor;
  Future<bool> Function()? quota;
  if (ai.enabled && apiKey != null && apiKey.isNotEmpty) {
    extractor = LlmReceiptExtractor(
      provider: ai.provider,
      endpoint: ai.endpoint,
      model: ai.model,
      apiKey: apiKey,
    );
    quota = () => consumeMonthlyCaptureQuota(ai.monthlyLimit);
  }

  return CaptureService(
    engine: engine,
    attachments: attachments,
    recognizer: recognizer,
    roles: user.roles,
    userId: user.id,
    llmExtractor: extractor,
    llmThreshold: ai.threshold,
    llmQuota: quota,
  );
});

/// A capture summarised for the review queue.
class CaptureRow {
  const CaptureRow({
    required this.id,
    required this.merchant,
    required this.date,
    required this.amount,
    required this.status,
    required this.confidence,
    required this.intendedRole,
    required this.linkedVoucher,
  });

  final String id;
  final String merchant;
  final String date;
  final String amount;
  final String status;
  final int confidence;
  final String intendedRole;
  final String? linkedVoucher;

  bool get isOpen => CaptureModule.openStatuses.contains(status);
}

/// Captures visible to the current operator, newest first. Role-filtered:
/// a capture tagged for another role is replicated but hidden from this queue.
final capturesProvider = FutureProvider<List<CaptureRow>>((ref) async {
  final engine = await ref.watch(documentEngineProvider.future);
  final roles = ref.watch(currentUserProvider).roles;
  final docs = await engine.list('Captured Document');
  final rows = <CaptureRow>[
    for (final d in docs)
      if (CaptureModule.visibleToRole(
          asNonEmpty(d.payload['intended_role']), roles))
        CaptureRow(
          id: d.id,
          merchant: asNonEmpty(d.payload['merchant_name']) ?? '—',
          date: asNonEmpty(d.payload['document_date']) ?? '',
          amount: d.payload['grand_total'] == null
              ? ''
              : '€${asNum(d.payload['grand_total']).toStringAsFixed(2)}',
          status: asNonEmpty(d.payload['status']) ??
              CaptureModule.statusReceived,
          confidence: asNum(d.payload['extraction_confidence']).round(),
          intendedRole:
              asNonEmpty(d.payload['intended_role']) ?? CaptureModule.roleAnyone,
          linkedVoucher: asNonEmpty(d.payload['linked_voucher']),
        ),
  ];
  rows.sort((a, b) => b.id.compareTo(a.id));
  return rows;
});

/// One capture document by id (null when missing).
final captureProvider =
    FutureProvider.family<Document?, String>((ref, id) async {
  final engine = await ref.watch(documentEngineProvider.future);
  return engine.fetch('Captured Document', id);
});

/// The receipt image bytes attached to a capture (null when none).
final captureImageProvider =
    FutureProvider.family<Uint8List?, String>((ref, captureId) async {
  final manager = await ref.watch(attachmentManagerProvider.future);
  final files = await manager.attachmentsForField(
      CaptureModule.documentFileFieldKey, captureId);
  if (files.isEmpty) return null;
  return manager.read(files.first);
});

/// Suppliers for the review screen's picker (id → display name).
final suppliersForPickerProvider =
    FutureProvider<List<({String id, String name})>>((ref) async {
  final engine = await ref.watch(documentEngineProvider.future);
  final suppliers = await engine.list('Supplier');
  final rows = [
    for (final s in suppliers)
      (id: s.id, name: asNonEmpty(s.payload['supplier_name']) ?? s.id),
  ];
  rows.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return rows;
});
