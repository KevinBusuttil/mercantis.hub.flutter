import 'package:mercantis_core/mercantis_core.dart';

import '../../ledger/ledger_values.dart';

/// Resolves what a till operator scanned or typed to a catalogue Item
/// (Phase 6 POS polish): barcode first (what a scanner emits), then the
/// item code, then the id. Case-insensitive, whitespace-trimmed; null when
/// nothing matches — the till says so instead of guessing.
Document? resolvePosItem(List<Document> items, String rawCode) {
  final code = rawCode.trim().toLowerCase();
  if (code.isEmpty) return null;
  String norm(dynamic v) => (asNonEmpty(v) ?? '').trim().toLowerCase();
  for (final it in items) {
    if (norm(it.payload['barcode']) == code) return it;
  }
  for (final it in items) {
    if (norm(it.payload['item_code']) == code) return it;
  }
  for (final it in items) {
    if (it.id.trim().toLowerCase() == code) return it;
  }
  return null;
}
