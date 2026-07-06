import 'package:mercantis_core/mercantis_core.dart';

import '../../ledger/ledger_values.dart';

/// One line of a parked cart, in till terms.
class ParkedLine {
  const ParkedLine({
    required this.item,
    required this.name,
    required this.qty,
    required this.rate,
    this.taxCode,
  });

  final String item;
  final String name;
  final num qty;
  final num rate;
  final String? taxCode;
}

/// A resumed parked sale — everything the till needs to refill its cart.
class ParkedSale {
  const ParkedSale({
    required this.id,
    required this.lines,
    this.customer,
    this.warehouse,
    this.note,
  });

  final String id;
  final String? customer;
  final String? warehouse;
  final String? note;
  final List<ParkedLine> lines;
}

/// Suspend / resume for the till (Phase 6 POS polish): a parked sale is a
/// `POS Suspended Sale` staging record — it survives app restarts, never
/// posts anything, and is deleted the moment it's resumed (so a cart can't
/// be rung up twice from the same parking slip).
class PosParkingService {
  PosParkingService({required this.engine, this.roles = const {'System Manager'}});

  final DocumentEngine engine;
  final Set<String> roles;

  Future<Document> park({
    required List<ParkedLine> lines,
    String? profileId,
    String? customer,
    String? warehouse,
    String? note,
  }) async {
    if (lines.isEmpty) throw StateError('Nothing in the cart to park.');
    final doc = Document(id: '', docType: 'POS Suspended Sale', payload: {
      if (profileId != null) 'pos_profile': profileId,
      if (customer != null) 'customer': customer,
      if (warehouse != null) 'warehouse': warehouse,
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      'parked_at': DateTime.now().toIso8601String(),
    });
    doc.children['items'] = [
      for (var i = 0; i < lines.length; i++)
        ChildRow(
          id: '', parentId: '', parentDocType: 'POS Suspended Sale',
          tableName: 'items', rowIndex: i,
          payload: {
            'item': lines[i].item,
            'description': lines[i].name,
            'qty': lines[i].qty,
            'rate': lines[i].rate,
            if (lines[i].taxCode != null) 'tax_code': lines[i].taxCode,
          },
        ),
    ];
    return engine.save(doc, roles);
  }

  /// Parked sales for [profileId] (all when null), oldest first.
  Future<List<Document>> listParked({String? profileId}) async {
    final parked = await engine.list('POS Suspended Sale',
        filters: profileId == null ? null : {'pos_profile': profileId},
        userRoles: roles);
    parked.sort((l, r) =>
        '${l.payload['parked_at']}'.compareTo('${r.payload['parked_at']}'));
    return parked;
  }

  /// Loads the parked sale back into till terms and deletes the record —
  /// resume is one-shot. Null when it no longer exists (already resumed on
  /// another device).
  Future<ParkedSale?> resume(String id) async {
    final doc = await engine.fetch('POS Suspended Sale', id);
    if (doc == null) return null;
    final sale = ParkedSale(
      id: doc.id,
      customer: asNonEmpty(doc.payload['customer']),
      warehouse: asNonEmpty(doc.payload['warehouse']),
      note: asNonEmpty(doc.payload['note']),
      lines: [
        for (final row in doc.children['items'] ?? const <ChildRow>[])
          ParkedLine(
            item: '${row.payload['item']}',
            name: asNonEmpty(row.payload['description']) ??
                '${row.payload['item']}',
            qty: asNum(row.payload['qty']),
            rate: asNum(row.payload['rate']),
            taxCode: asNonEmpty(row.payload['tax_code']),
          ),
      ],
    );
    await engine.delete('POS Suspended Sale', id, roles);
    return sale;
  }
}
