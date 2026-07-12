import 'package:mercantis_core/mercantis_core.dart';

/// V3 Rental (Phase 5): hire out OUR units — tools, vans, rooms, kit.
/// Pure composition:
///  * availability is S1 — every Rental Unit is backed by a Schedulable
///    Resource, and a hire holds a conflict-checked Appointment on it, so
///    double-hiring is impossible by construction and the fleet shares
///    the Schedule board with everything else;
///  * the booking deposit is S4 (held as a liability, auto-applied at
///    return);
///  * the money is an ordinary Sales Invoice (days × rate through the
///    S8 resolver when the rate is blank);
///  * the unit itself can link to an S10 Asset — the thing depreciating
///    on our books is the thing out on hire.
abstract final class RentalModule {
  static const _module = 'Rental';

  static List<DocType> docTypes() => [_rentalUnit(), _rentalAgreement()];

  static DocType _rentalUnit() => const DocType(
        id: 'Rental Unit',
        name: 'Rental Unit',
        module: _module,
        namingRule: 'RU-.####',
        fields: [
          FieldDefinition(key: 'unit_name', label: 'Unit', type: FieldType.data, required: true),
          // The S1 identity: hires book appointments on this resource.
          FieldDefinition(key: 'resource', label: 'Calendar Resource', type: FieldType.link, linkDocType: 'Schedulable Resource', options: 'Schedulable Resource', required: true),
          // What the invoice line bills (qty = chargeable days).
          FieldDefinition(key: 'rental_item', label: 'Rental Item', type: FieldType.link, linkDocType: 'Item', options: 'Item', required: true),
          FieldDefinition(key: 'daily_rate', label: 'Daily Rate', type: FieldType.currency),
          // The S10 tie: the depreciating asset behind the unit.
          FieldDefinition(key: 'asset', label: 'Fixed Asset', type: FieldType.link, linkDocType: 'Asset', options: 'Asset'),
          FieldDefinition(key: 'serial_no', label: 'Serial No', type: FieldType.data),
          FieldDefinition(key: 'notes', label: 'Notes', type: FieldType.smallText),
          FieldDefinition(key: 'enabled', label: 'Enabled', type: FieldType.check, defaultValue: '1'),
        ],
      );

  /// One hire. Status walks Draft (booked) → Out (handed over) →
  /// Returned (back + invoiced); Cancelled frees the hold.
  static DocType _rentalAgreement() => const DocType(
        id: 'Rental Agreement',
        name: 'Rental Agreement',
        module: _module,
        namingRule: 'RENT-.YYYY.-.####',
        fields: [
          FieldDefinition(key: 'customer', label: 'Customer', type: FieldType.link, linkDocType: 'Customer', options: 'Customer', required: true),
          FieldDefinition(key: 'unit', label: 'Unit', type: FieldType.link, linkDocType: 'Rental Unit', options: 'Rental Unit', required: true),
          FieldDefinition(
            key: 'status',
            label: 'Status',
            type: FieldType.select,
            options: 'Draft\nOut\nReturned\nCancelled',
            defaultValue: 'Draft',
          ),
          FieldDefinition(key: 'starts_at', label: 'From', type: FieldType.dateTime, required: true),
          FieldDefinition(key: 'ends_at', label: 'To', type: FieldType.dateTime, required: true),
          FieldDefinition(key: 'daily_rate', label: 'Daily Rate', type: FieldType.currency),
          // The S1 hold keeping the unit unavailable for the window.
          FieldDefinition(key: 'appointment', label: 'Availability Hold', type: FieldType.link, linkDocType: 'Appointment', options: 'Appointment', readOnly: true),
          // The S4 booking deposit, auto-applied at return.
          FieldDefinition(key: 'deposit', label: 'Deposit', type: FieldType.link, linkDocType: 'Customer Deposit', options: 'Customer Deposit', readOnly: true),
          // Handover trail.
          FieldDefinition(key: 'out_at', label: 'Handed Over', type: FieldType.data, readOnly: true),
          FieldDefinition(key: 'out_condition', label: 'Condition Out', type: FieldType.smallText),
          FieldDefinition(key: 'returned_at', label: 'Returned', type: FieldType.data, readOnly: true),
          FieldDefinition(key: 'return_condition', label: 'Condition Back', type: FieldType.smallText),
          FieldDefinition(key: 'sales_invoice', label: 'Invoiced As', type: FieldType.link, linkDocType: 'Sales Invoice', options: 'Sales Invoice', readOnly: true),
          FieldDefinition(key: 'notes', label: 'Notes', type: FieldType.smallText),
        ],
      );
}
