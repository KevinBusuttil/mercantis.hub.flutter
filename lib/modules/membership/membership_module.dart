import 'package:mercantis_core/mercantis_core.dart';

/// V7 Memberships (Phase 5): gyms, clubs, associations, co-workings.
/// The same composition as V5 property: the MEMBERSHIP FEE IS A
/// RECURRING INVOICE. A Plan defines what and how often; activating a
/// Membership writes the billing template; pause/resume/cancel steer
/// that template — resume deliberately never back-bills the paused gap.
abstract final class MembershipModule {
  static const _module = 'Membership';

  static List<DocType> docTypes() => [_plan(), _membership()];

  static DocType _plan() => const DocType(
        id: 'Membership Plan',
        name: 'Membership Plan',
        module: _module,
        fields: [
          FieldDefinition(key: 'plan_name', label: 'Plan', type: FieldType.data, required: true),
          FieldDefinition(key: 'fee', label: 'Fee / Period', type: FieldType.currency, required: true),
          FieldDefinition(
            key: 'frequency',
            label: 'Billing Frequency',
            type: FieldType.select,
            options: 'Monthly\nQuarterly\nYearly',
            defaultValue: 'Monthly',
          ),
          // What the fee invoice lines bill.
          FieldDefinition(key: 'membership_item', label: 'Fee Item', type: FieldType.link, linkDocType: 'Item', options: 'Item', required: true),
          FieldDefinition(key: 'description', label: 'Description', type: FieldType.smallText),
          FieldDefinition(key: 'enabled', label: 'Enabled', type: FieldType.check, defaultValue: '1'),
        ],
      );

  /// One member on one plan: Draft (signed up) → Active (billing) ⇄
  /// Paused (template off, no back-billing on resume) → Cancelled.
  static DocType _membership() => const DocType(
        id: 'Membership',
        name: 'Membership',
        module: _module,
        namingRule: 'MEM-.YYYY.-.####',
        fields: [
          FieldDefinition(key: 'member', label: 'Member', type: FieldType.link, linkDocType: 'Customer', options: 'Customer', required: true),
          FieldDefinition(key: 'plan', label: 'Plan', type: FieldType.link, linkDocType: 'Membership Plan', options: 'Membership Plan', required: true),
          FieldDefinition(
            key: 'status',
            label: 'Status',
            type: FieldType.select,
            options: 'Draft\nActive\nPaused\nCancelled',
            defaultValue: 'Draft',
          ),
          FieldDefinition(key: 'joined_on', label: 'Joined', type: FieldType.date, required: true),
          // Stamped by activation: the billing engine behind the fee.
          FieldDefinition(key: 'recurring_invoice', label: 'Fee Billing', type: FieldType.link, linkDocType: 'Recurring Invoice', options: 'Recurring Invoice', readOnly: true),
          FieldDefinition(key: 'paused_on', label: 'Paused', type: FieldType.date, readOnly: true),
          FieldDefinition(key: 'cancelled_on', label: 'Cancelled', type: FieldType.date, readOnly: true),
          FieldDefinition(key: 'notes', label: 'Notes', type: FieldType.smallText),
        ],
      );
}
