import 'package:mercantis_core/mercantis_core.dart';

/// Delivery routes & fleet (ported from the Swift Hub `Deliveries` route
/// DocTypes). Pure operational/config data — nothing is submittable and there
/// are no workflows; route/stop status are manual selects. A `DeliveryRoute`
/// groups submitted Delivery Notes as ordered stops; the `DeliveryRouteService`
/// appends a `Delivery Status Event` per status change and mirrors the route +
/// stop status back onto each Delivery Note.
abstract final class DeliveriesModule {
  static const _module = 'Deliveries';

  static const _stopStatus =
      'Pending\nLoaded\nOut for Delivery\nDelivered\nFailed\nRescheduled';

  static List<DocType> docTypes() => [
        _driver(),
        _vehicle(),
        _deliveryRoute(),
        _deliveryRouteStop(),
        _deliveryStatusEvent(),
      ];

  static DocType _driver() => const DocType(
        id: 'Driver',
        name: 'Driver',
        module: _module,
        fields: [
          FieldDefinition(key: 'driver_name', label: 'Driver Name', type: FieldType.data, required: true),
          FieldDefinition(key: 'phone', label: 'Phone', type: FieldType.data),
          FieldDefinition(key: 'license_no', label: 'Licence No', type: FieldType.data),
          FieldDefinition(key: 'enabled', label: 'Enabled', type: FieldType.check, defaultValue: '1'),
        ],
      );

  static DocType _vehicle() => const DocType(
        id: 'Vehicle',
        name: 'Vehicle',
        module: _module,
        fields: [
          FieldDefinition(key: 'vehicle_name', label: 'Vehicle / Plate', type: FieldType.data, required: true),
          FieldDefinition(key: 'model', label: 'Model', type: FieldType.data),
          FieldDefinition(key: 'capacity', label: 'Capacity', type: FieldType.float),
          FieldDefinition(key: 'enabled', label: 'Enabled', type: FieldType.check, defaultValue: '1'),
        ],
      );

  static DocType _deliveryRoute() => const DocType(
        id: 'Delivery Route',
        name: 'Delivery Route',
        module: _module,
        namingRule: 'ROUTE-.YYYY.-.####',
        fields: [
          FieldDefinition(key: 'route_date', label: 'Route Date', type: FieldType.date, required: true),
          FieldDefinition(key: 'route_name', label: 'Route Name', type: FieldType.data),
          FieldDefinition(key: 'driver', label: 'Driver', type: FieldType.link, linkDocType: 'Driver', options: 'Driver'),
          FieldDefinition(key: 'vehicle', label: 'Vehicle', type: FieldType.link, linkDocType: 'Vehicle', options: 'Vehicle'),
          FieldDefinition(key: 'status', label: 'Status', type: FieldType.select, options: 'Draft\nDispatched\nCompleted\nCancelled', defaultValue: 'Draft'),
          FieldDefinition(key: 'stops', label: 'Stops', type: FieldType.table, tableDocType: 'Delivery Route Stop', options: 'Delivery Route Stop'),
          FieldDefinition(key: 'notes', label: 'Notes', type: FieldType.longText),
        ],
      );

  static DocType _deliveryRouteStop() => const DocType(
        id: 'Delivery Route Stop',
        name: 'Delivery Route Stop',
        module: _module,
        isChild: true,
        fields: [
          FieldDefinition(key: 'sequence', label: 'Sequence', type: FieldType.integer, defaultValue: '1'),
          FieldDefinition(key: 'sales_delivery', label: 'Delivery Note', type: FieldType.link, linkDocType: 'Delivery Note', options: 'Delivery Note', required: true),
          FieldDefinition(key: 'customer', label: 'Customer', type: FieldType.link, linkDocType: 'Customer', options: 'Customer'),
          FieldDefinition(key: 'address', label: 'Address', type: FieldType.smallText),
          FieldDefinition(key: 'status', label: 'Status', type: FieldType.select, options: _stopStatus, defaultValue: 'Pending'),
          FieldDefinition(key: 'pod_note', label: 'Proof-of-Delivery Note', type: FieldType.data),
          FieldDefinition(key: 'pod_image', label: 'Proof of Delivery', type: FieldType.attachImage),
          // S3 capture: the receiver's signature (normalised strokes JSON,
          // drawn on-device) and when the proof was taken.
          FieldDefinition(key: 'pod_signature', label: 'Receiver Signature', type: FieldType.signature),
          FieldDefinition(key: 'pod_time', label: 'Proof Taken At', type: FieldType.data, readOnly: true),
        ],
      );

  /// Append-only audit log of stop status changes. Written by the
  /// DeliveryRouteService; deterministic id `DSE-<route>-<seq>-<n>`.
  static DocType _deliveryStatusEvent() => const DocType(
        id: 'Delivery Status Event',
        name: 'Delivery Status Event',
        module: _module,
        fields: [
          FieldDefinition(key: 'delivery_route', label: 'Delivery Route', type: FieldType.link, linkDocType: 'Delivery Route', options: 'Delivery Route'),
          FieldDefinition(key: 'sales_delivery', label: 'Delivery Note', type: FieldType.link, linkDocType: 'Delivery Note', options: 'Delivery Note'),
          FieldDefinition(key: 'stop_sequence', label: 'Sequence', type: FieldType.integer),
          FieldDefinition(key: 'status', label: 'Status', type: FieldType.data, required: true),
          FieldDefinition(key: 'event_time', label: 'Time', type: FieldType.data),
          FieldDefinition(key: 'note', label: 'Note', type: FieldType.data),
        ],
      );
}
