import 'package:mercantis_core/mercantis_core.dart';

/// Document Capture (ADR-049). A lightweight intake record for a photographed
/// or uploaded receipt/bill. The receipt image rides as a synced attachment
/// (ADR-048) bound to the capture via the `document_file` field key — not a
/// payload field — so this DocType holds only the *extracted* metadata a
/// reviewer confirms before a draft voucher is created.
///
/// Deliberately simple for self-employed users: not submittable, no workflow,
/// no regex rules. A plain `status` select drives the review queue; routing to
/// a draft Purchase Invoice happens from the review screen, never automatically.
abstract final class CaptureModule {
  static const _module = 'Document Capture';

  /// Status values for a capture's lifecycle. Plain strings on the `status`
  /// field — no submittable workflow.
  static const statusReceived = 'Received';
  static const statusReady = 'Ready';
  static const statusNeedsReview = 'Needs Review';
  static const statusDraftCreated = 'Draft Created';
  static const statusDuplicate = 'Duplicate';

  static const _statusOptions =
      '$statusReceived\n$statusReady\n$statusNeedsReview\n'
      '$statusDraftCreated\n$statusDuplicate';

  /// Field key under which the receipt image is attached (via AttachmentManager).
  static const documentFileFieldKey = 'document_file';

  /// "Anyone" means the capture shows in every operator's review queue; other
  /// values scope it to operators whose role matches (see CaptureRoleFilter).
  static const roleAnyone = 'Anyone';
  static const _roleOptions = '$roleAnyone\nBookkeeping\nManagement\nField';

  static List<DocType> docTypes() => [_capturedDocument(), _captureRule()];

  /// Normalised merchant key used to remember a merchant→supplier mapping.
  /// Lower-cased, with digits and punctuation stripped and whitespace
  /// collapsed — so "BP Service Station #4471" and "BP SERVICE STATION" share
  /// a memory even when a store/receipt number is appended to the name.
  static String merchantKey(String merchant) => merchant
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z ]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  /// Internal learning rule (ADR-049): a remembered merchant→supplier mapping,
  /// keyed by [merchantKey]. Written silently when a draft is created and read
  /// back to prefill future captures. Not user-facing — no regex, no setup.
  static DocType _captureRule() => const DocType(
        id: 'Capture Rule',
        name: 'Capture Rule',
        module: _module,
        isSubmittable: false,
        fields: [
          FieldDefinition(
              key: 'merchant_name', label: 'Merchant', type: FieldType.data),
          FieldDefinition(
            key: 'supplier',
            label: 'Supplier',
            type: FieldType.link,
            linkDocType: 'Supplier',
            options: 'Supplier',
          ),
          FieldDefinition(
              key: 'times_seen', label: 'Times Seen', type: FieldType.integer),
        ],
      );

  /// Lifecycle values that still want a human's eyes in the review queue.
  static const openStatuses = {
    statusReceived,
    statusReady,
    statusNeedsReview,
  };

  /// View-only role scoping (ADR-049): every company member receives every
  /// capture (sync is not partitioned), but a capture tagged for a specific
  /// role only surfaces in that role's review queue. "Anyone"/empty shows to
  /// all; a System Manager sees everything.
  static bool visibleToRole(String? intendedRole, Set<String> userRoles) {
    if (intendedRole == null ||
        intendedRole.isEmpty ||
        intendedRole == roleAnyone) {
      return true;
    }
    if (userRoles.contains('System Manager')) return true;
    final wanted = intendedRole.toLowerCase();
    return userRoles.any((r) => r.toLowerCase() == wanted);
  }

  static DocType _capturedDocument() => const DocType(
        id: 'Captured Document',
        name: 'Captured Document',
        module: _module,
        isSubmittable: false,
        namingRule: 'CAP-.YYYY.-.####',
        fields: [
          FieldDefinition(
            key: 'status',
            label: 'Status',
            type: FieldType.select,
            options: _statusOptions,
            defaultValue: statusReceived,
          ),
          FieldDefinition(
            key: 'source_type',
            label: 'Source',
            type: FieldType.select,
            options: 'Camera\nUpload',
            defaultValue: 'Camera',
          ),
          // — Extracted / confirmed metadata —
          FieldDefinition(
              key: 'merchant_name', label: 'Merchant', type: FieldType.data),
          FieldDefinition(
            key: 'supplier',
            label: 'Supplier',
            type: FieldType.link,
            linkDocType: 'Supplier',
            options: 'Supplier',
          ),
          FieldDefinition(
              key: 'document_date', label: 'Document Date', type: FieldType.date),
          FieldDefinition(
              key: 'invoice_no', label: 'Invoice / Receipt No', type: FieldType.data),
          FieldDefinition(
              key: 'net_total', label: 'Net Total', type: FieldType.currency),
          FieldDefinition(
              key: 'vat_total', label: 'VAT Total', type: FieldType.currency),
          FieldDefinition(
              key: 'grand_total', label: 'Grand Total', type: FieldType.currency),
          FieldDefinition(
            key: 'currency',
            label: 'Currency',
            type: FieldType.link,
            linkDocType: 'Currency',
            options: 'Currency',
          ),
          // — Review routing —
          FieldDefinition(
            key: 'intended_role',
            label: 'For',
            type: FieldType.select,
            options: _roleOptions,
            defaultValue: roleAnyone,
          ),
          FieldDefinition(
            key: 'extraction_confidence',
            label: 'Extraction Confidence',
            type: FieldType.percent,
            readOnly: true,
          ),
          FieldDefinition(
            key: 'voucher_type',
            label: 'Created Voucher Type',
            type: FieldType.data,
            readOnly: true,
          ),
          FieldDefinition(
            key: 'linked_voucher',
            label: 'Created Voucher',
            type: FieldType.data,
            readOnly: true,
          ),
          FieldDefinition(
              key: 'notes', label: 'Notes', type: FieldType.smallText),
        ],
      );
}
