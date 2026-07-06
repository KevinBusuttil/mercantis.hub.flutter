import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

import 'quotation_status.dart';

/// Quotation lifecycle actions (Phase 1A): Mark as Sent / Accepted /
/// Rejected on a submitted quotation. Each stamps its timestamp field
/// (`sent_on` / `accepted_on` / `rejected_on`); [QuotationStatus] derives the
/// visible status from those stamps, so no workflow surgery is needed and
/// Expired keeps working purely off `valid_till`.
void registerHubQuotationActions(WidgetRef ref) {
  ref.read(documentActionRegistryProvider).register(hubQuotationActionsFor);
}

/// Pure and synchronous — exposed for tests.
List<DocumentAction> hubQuotationActionsFor(Document doc, DocType docType) {
  if (docType.id != 'Quotation') return const [];
  if (doc.id.isEmpty || doc.docStatus != 1) return const [];

  final status = QuotationStatus.of(doc);
  const settled = {
    QuotationStatus.accepted,
    QuotationStatus.rejected,
    QuotationStatus.converted,
    QuotationStatus.cancelled,
  };
  if (settled.contains(status)) return const [];

  return [
    if (status == QuotationStatus.open)
      const DocumentAction(
        id: 'quotation-mark-sent',
        label: 'Mark as Sent',
        icon: Icons.send_outlined,
        invoke: _markSent,
      ),
    const DocumentAction(
      id: 'quotation-mark-accepted',
      label: 'Mark as Accepted',
      icon: Icons.thumb_up_alt_outlined,
      invoke: _markAccepted,
    ),
    const DocumentAction(
      id: 'quotation-mark-rejected',
      label: 'Mark as Rejected',
      icon: Icons.thumb_down_alt_outlined,
      invoke: _markRejected,
    ),
  ];
}

Future<void> _markSent(BuildContext context, WidgetRef ref, Document doc) =>
    _stamp(context, ref, doc, 'sent_on', 'Marked as sent');

Future<void> _markAccepted(BuildContext context, WidgetRef ref, Document doc) =>
    _stamp(context, ref, doc, 'accepted_on',
        'Accepted — convert it to an order or invoice when ready');

Future<void> _markRejected(BuildContext context, WidgetRef ref, Document doc) =>
    _stamp(context, ref, doc, 'rejected_on', 'Marked as rejected');

const _systemRoles = {'System Manager'};

Future<void> _stamp(BuildContext context, WidgetRef ref, Document doc,
    String field, String message) async {
  final engine = await ref.read(documentEngineProvider.future);
  final fresh = await engine.fetch('Quotation', doc.id) ?? doc;
  fresh.payload[field] = DateTime.now().toIso8601String().split('T').first;
  await engine.applyOnSubmitUpdate(fresh, _systemRoles);
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}
