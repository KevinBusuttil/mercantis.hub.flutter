import 'package:mercantis_core/mercantis_core.dart';

/// S2 / V4 Repair & Garage (Phase 5): the register of the CUSTOMER's
/// things we service — vehicles in a garage, boilers for a heating firm,
/// machines for a repair shop. Not our fixed assets (that's S10); these
/// belong to customers, and their value is the service HISTORY that
/// accumulates against each unit through the ordinary V1 field-service
/// spine (Service Request → Job → Invoice), which now carries an
/// `equipment` link end to end.
abstract final class EquipmentModule {
  static const _module = 'Equipment';

  static List<DocType> docTypes() => [_customerEquipment()];

  static DocType _customerEquipment() => const DocType(
        id: 'Customer Equipment',
        name: 'Customer Equipment',
        module: _module,
        namingRule: 'EQP-.YYYY.-.####',
        fields: [
          FieldDefinition(key: 'equipment_name', label: 'Equipment', type: FieldType.data, required: true),
          FieldDefinition(key: 'customer', label: 'Owner', type: FieldType.link, linkDocType: 'Customer', options: 'Customer', required: true),
          FieldDefinition(
            key: 'equipment_type',
            label: 'Type',
            type: FieldType.select,
            options: 'Vehicle\nMachine\nAppliance\nBoiler\nOther',
            defaultValue: 'Other',
          ),
          FieldDefinition(key: 'make', label: 'Make', type: FieldType.data),
          FieldDefinition(key: 'model', label: 'Model', type: FieldType.data),
          FieldDefinition(key: 'serial_no', label: 'Serial / VIN', type: FieldType.data),
          // The garage case: the number plate is how the desk finds the car.
          FieldDefinition(key: 'registration_no', label: 'Registration / Plate', type: FieldType.data),
          FieldDefinition(key: 'year', label: 'Year', type: FieldType.integer),
          FieldDefinition(
            key: 'meter_unit',
            label: 'Meter Unit',
            type: FieldType.select,
            options: 'None\nkm\nmiles\nhours',
            defaultValue: 'None',
          ),
          FieldDefinition(key: 'notes', label: 'Notes', type: FieldType.smallText),
          FieldDefinition(key: 'enabled', label: 'Enabled', type: FieldType.check, defaultValue: '1'),
        ],
      );
}
