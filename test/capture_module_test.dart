import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_hub_app/manifest/hub_manifest.dart';
import 'package:mercantis_hub_app/modules/capture/capture_module.dart';

/// ADR-049: the Captured Document intake DocType. Pure-data assertions on its
/// shape — no database — so it runs fast in CI alongside manifest_integrity.
void main() {
  final manifest = HubManifest.build();
  final byId = {for (final dt in manifest.docTypes) dt.id: dt};

  test('Captured Document is registered, not submittable, no workflow', () {
    final cap = byId['Captured Document'];
    expect(cap, isNotNull, reason: 'CaptureModule not wired into the manifest');
    expect(cap!.isSubmittable, isFalse);
    expect(cap.workflowId, isNull); // a plain status select, not a workflow
    expect(cap.namingRule, 'CAP-.YYYY.-.####');
  });

  test('carries the extracted-metadata fields a reviewer confirms', () {
    final cap = byId['Captured Document']!;
    final fields = {for (final f in cap.fields) f.key: f};
    for (final key in [
      'status',
      'source_type',
      'merchant_name',
      'supplier',
      'document_date',
      'invoice_no',
      'net_total',
      'vat_total',
      'grand_total',
      'currency',
      'intended_role',
      'extraction_confidence',
      'voucher_type',
      'linked_voucher',
      'notes',
    ]) {
      expect(fields.containsKey(key), isTrue, reason: 'missing field "$key"');
    }
    expect(fields['grand_total']!.type, FieldType.currency);
    expect(fields['supplier']!.type, FieldType.link);
    expect(fields['supplier']!.linkDocType, 'Supplier');
    expect(fields['status']!.type, FieldType.select);
    expect(fields['linked_voucher']!.readOnly, isTrue);
  });

  test('status select advertises the documented lifecycle values', () {
    final cap = byId['Captured Document']!;
    final status = cap.fields.firstWhere((f) => f.key == 'status');
    for (final v in [
      CaptureModule.statusReceived,
      CaptureModule.statusReady,
      CaptureModule.statusNeedsReview,
      CaptureModule.statusDraftCreated,
      CaptureModule.statusDuplicate,
    ]) {
      expect(status.options, contains(v));
    }
    expect(status.defaultValue, CaptureModule.statusReceived);
  });
}
