import 'package:mercantis_core/mercantis_core.dart';

/// Phase 4: the appointments composition pack. Not a vertical — a thin
/// layer that composes what already exists (S1 scheduling, S4 deposits,
/// S8 pricing) for salons, tutors, studios and clinics-without-records.
/// The only NEW doctype it needs is the commission rule (S9); everything
/// else is orchestration in BookingService.
abstract final class BookingModule {
  static const _module = 'Booking';

  static List<DocType> docTypes() => [_commissionRule()];

  /// S9: who earns what percentage on the services they deliver. The
  /// commission base is the invoiced net (ex VAT) of appointments the
  /// resource completed. An item-specific rule beats the resource's
  /// general rule, so "Anna earns 10%, but 20% on colour treatments"
  /// needs two rows, not code.
  static DocType _commissionRule() => const DocType(
        id: 'Commission Rule',
        name: 'Commission Rule',
        module: _module,
        fields: [
          FieldDefinition(key: 'resource', label: 'Resource / Staff', type: FieldType.link, linkDocType: 'Schedulable Resource', options: 'Schedulable Resource', required: true),
          FieldDefinition(key: 'percent', label: 'Commission %', type: FieldType.float, required: true),
          FieldDefinition(key: 'service_item', label: 'Only for Service', type: FieldType.link, linkDocType: 'Item', options: 'Item'),
          FieldDefinition(key: 'enabled', label: 'Enabled', type: FieldType.check, defaultValue: '1'),
          FieldDefinition(key: 'notes', label: 'Notes', type: FieldType.smallText),
        ],
      );
}
