import 'package:mercantis_core/mercantis_core.dart';

import '../ledger/ledger_values.dart';

const _systemRoles = {'System Manager'};

/// V4: everything the desk asks about a unit — its service history, the
/// last meter reading we saw, and "book it in" (a new Service Request
/// prefilled from the register, landing in the ordinary dispatch queue).
class EquipmentService {
  EquipmentService(this._engine, {Set<String> roles = _systemRoles})
      : _roles = roles;

  final DocumentEngine _engine;
  final Set<String> _roles;

  /// The unit's service history: every non-cancelled Job linked to it,
  /// newest first (scheduled start, falling back to creation).
  Future<List<Document>> history(String equipmentId) async {
    final jobs = await _engine.list('Job',
        filters: {'equipment': equipmentId}, userRoles: _roles);
    final rows = [
      for (final j in jobs)
        if ('${j.payload['status']}' != 'Cancelled') j,
    ];
    String sortKey(Document j) =>
        asNonEmpty(j.payload['starts_at']) ??
        j.createdAt.toIso8601String();
    rows.sort((a, b) => sortKey(b).compareTo(sortKey(a)));
    return rows;
  }

  /// The highest meter reading on record for the unit — garages read
  /// this back to the customer ("it was on 78,200 last time").
  Future<num?> lastMeterReading(String equipmentId) async {
    num? best;
    for (final j in await history(equipmentId)) {
      final reading = asNum(j.payload['meter_reading']);
      if (reading <= 0) continue;
      if (best == null || reading > best) best = reading;
    }
    return best;
  }

  /// Book the unit in: an Open Service Request prefilled with the
  /// equipment and its owner, dropping into the dispatch queue like any
  /// phone call would.
  Future<Document> requestService(
    String equipmentId, {
    required String subject,
    String? description,
    String priority = 'Medium',
    num? meterReading,
  }) async {
    final equipment =
        await _engine.fetch('Customer Equipment', equipmentId);
    if (equipment == null) {
      throw StateError('Equipment $equipmentId not found.');
    }
    return _engine.save(
        Document(id: '', docType: 'Service Request', payload: {
          'subject': subject,
          'customer': equipment.payload['customer'],
          'equipment': equipment.id,
          'priority': priority,
          'status': 'Open',
          if (description != null && description.isNotEmpty)
            'description': description,
          if (meterReading != null && meterReading > 0)
            'meter_reading': meterReading,
        }),
        _roles);
  }
}
