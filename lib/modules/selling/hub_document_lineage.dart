import 'package:mercantis_core/mercantis_core.dart';

import '../../ledger/ledger_values.dart';

/// One related document surfaced by the lineage inspector (HU4).
class LineageRef {
  const LineageRef(
      {required this.docType, required this.id, required this.relation});
  final String docType;
  final String id;

  /// Human label for how it relates (e.g. "From Sales Order", "Returned by").
  final String relation;
}

/// Conversion lineage (HU4) — the cross-DocType "Related" graph the Swift Hub's
/// lineage card walks. Encodes the document-to-document back-links the H3
/// conversion builders write (a child carries `field` pointing at its parent),
/// so a document's upstream sources and downstream results can be resolved.
abstract final class HubDocumentLineage {
  /// `child.field → parent` back-links written by the conversion builders.
  static const links = <({String child, String field, String parent})>[
    (child: 'Sales Order', field: 'quotation', parent: 'Quotation'),
    (child: 'Delivery Note', field: 'sales_order', parent: 'Sales Order'),
    (child: 'Sales Invoice', field: 'sales_order', parent: 'Sales Order'),
    (child: 'Sales Invoice', field: 'delivery_note', parent: 'Delivery Note'),
    (child: 'Purchase Receipt', field: 'purchase_order', parent: 'Purchase Order'),
    (child: 'Purchase Invoice', field: 'purchase_order', parent: 'Purchase Order'),
    (child: 'Purchase Invoice', field: 'purchase_receipt', parent: 'Purchase Receipt'),
  ];

  /// DocTypes whose returns link to a same-type original via `return_against`.
  static const returnTypes = {
    'Sales Invoice',
    'Purchase Invoice',
    'Delivery Note',
    'Purchase Receipt',
    'POS Invoice',
  };

  /// Whether [docType] takes part in any lineage relationship.
  static bool participates(String docType) =>
      returnTypes.contains(docType) ||
      links.any((l) => l.child == docType || l.parent == docType);

  /// Upstream sources of [doc] (what it was created from) — read straight from
  /// its own back-link fields. Pure.
  static List<LineageRef> upstream(Document doc, String docType) {
    final out = <LineageRef>[];
    for (final l in links) {
      if (l.child != docType) continue;
      final v = asNonEmpty(doc.payload[l.field]);
      if (v != null) {
        out.add(LineageRef(docType: l.parent, id: v, relation: 'From ${l.parent}'));
      }
    }
    if (returnTypes.contains(docType)) {
      final v = asNonEmpty(doc.payload['return_against']);
      if (v != null) {
        out.add(LineageRef(docType: docType, id: v, relation: 'Return against'));
      }
    }
    return out;
  }

  /// Downstream results of [doc] (what was created from it) — the documents that
  /// link back to its id. Queries the store.
  static Future<List<LineageRef>> downstream(
    DocumentEngine engine,
    Document doc,
    String docType, {
    Set<String> roles = const {'System Manager'},
  }) async {
    final out = <LineageRef>[];
    for (final l in links) {
      if (l.parent != docType) continue;
      final rows = await engine.list(l.child,
          filters: {l.field: doc.id}, userRoles: roles);
      for (final r in rows) {
        out.add(LineageRef(docType: l.child, id: r.id, relation: 'To ${l.child}'));
      }
    }
    if (returnTypes.contains(docType)) {
      final rows = await engine.list(docType,
          filters: {'return_against': doc.id}, userRoles: roles);
      for (final r in rows) {
        out.add(LineageRef(docType: docType, id: r.id, relation: 'Returned by'));
      }
    }
    return out;
  }
}
