import 'package:mercantis_core/mercantis_core.dart';

/// V5 Property / Landlords (Phase 5). Composition again: the Property is
/// a register (optionally tied to an S10 Asset — the building that
/// depreciates is the building that earns), the Lease is the tenancy's
/// working document, and RENT IS A RECURRING INVOICE — activating a
/// lease writes an ordinary Recurring Invoice template, so the existing
/// boot runner bills every period, failures surface on the template,
/// and arrears are just the generated invoices' outstanding balances.
/// The tenancy deposit is S4, held as a liability like every other
/// customer prepayment.
abstract final class PropertyModule {
  static const _module = 'Property';

  static List<DocType> docTypes() => [_property(), _lease()];

  static DocType _property() => const DocType(
        id: 'Property',
        name: 'Property',
        module: _module,
        namingRule: 'PROP-.####',
        fields: [
          FieldDefinition(key: 'property_name', label: 'Property', type: FieldType.data, required: true),
          FieldDefinition(key: 'address', label: 'Address', type: FieldType.smallText),
          FieldDefinition(
            key: 'property_type',
            label: 'Type',
            type: FieldType.select,
            options: 'Apartment\nHouse\nOffice\nShop\nGarage\nOther',
            defaultValue: 'Apartment',
          ),
          // The S10 tie: the depreciating asset behind the property.
          FieldDefinition(key: 'asset', label: 'Fixed Asset', type: FieldType.link, linkDocType: 'Asset', options: 'Asset'),
          FieldDefinition(key: 'notes', label: 'Notes', type: FieldType.smallText),
          FieldDefinition(key: 'enabled', label: 'Enabled', type: FieldType.check, defaultValue: '1'),
        ],
      );

  /// One tenancy: Draft (agreed) → Active (deposit taken, rent billing)
  /// → Ended (template deactivated; the paper trail stays).
  static DocType _lease() => const DocType(
        id: 'Lease',
        name: 'Lease',
        module: _module,
        namingRule: 'LSE-.YYYY.-.####',
        fields: [
          FieldDefinition(key: 'property', label: 'Property', type: FieldType.link, linkDocType: 'Property', options: 'Property', required: true),
          FieldDefinition(key: 'tenant', label: 'Tenant', type: FieldType.link, linkDocType: 'Customer', options: 'Customer', required: true),
          FieldDefinition(
            key: 'status',
            label: 'Status',
            type: FieldType.select,
            options: 'Draft\nActive\nEnded',
            defaultValue: 'Draft',
          ),
          FieldDefinition(key: 'starts_on', label: 'Starts', type: FieldType.date, required: true),
          FieldDefinition(key: 'ends_on', label: 'Ends', type: FieldType.date),
          FieldDefinition(key: 'monthly_rent', label: 'Rent / Period', type: FieldType.currency, required: true),
          // What the rent invoice lines bill.
          FieldDefinition(key: 'rent_item', label: 'Rent Item', type: FieldType.link, linkDocType: 'Item', options: 'Item', required: true),
          FieldDefinition(
            key: 'frequency',
            label: 'Billing Frequency',
            type: FieldType.select,
            options: 'Monthly\nQuarterly\nYearly',
            defaultValue: 'Monthly',
          ),
          // Stamped by activation: the S4 deposit and the billing engine.
          FieldDefinition(key: 'deposit', label: 'Tenancy Deposit', type: FieldType.link, linkDocType: 'Customer Deposit', options: 'Customer Deposit', readOnly: true),
          FieldDefinition(key: 'recurring_invoice', label: 'Rent Billing', type: FieldType.link, linkDocType: 'Recurring Invoice', options: 'Recurring Invoice', readOnly: true),
          FieldDefinition(key: 'notes', label: 'Notes', type: FieldType.smallText),
        ],
      );
}
