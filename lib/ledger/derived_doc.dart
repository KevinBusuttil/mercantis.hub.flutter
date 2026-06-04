/// A ledger row the derivation wants persisted. Pure data — `docType` + a
/// deterministic `id` (so re-firing a submit upserts in place rather than
/// duplicating) + the field payload. The runner turns these into `Document`s
/// and saves them; keeping them as plain values makes the derivation logic
/// unit-testable with no database.
class DerivedDoc {
  final String docType;
  final String id;
  final Map<String, dynamic> payload;

  const DerivedDoc(this.docType, this.id, this.payload);

  @override
  String toString() => 'DerivedDoc($docType, $id, $payload)';
}
