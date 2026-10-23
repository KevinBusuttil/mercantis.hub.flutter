import 'package:mercantis_core/mercantis_core.dart';

/// The id of the stock balance row (Bin) for an item in a warehouse.
///
/// The format is `BIN-<item>-<warehouse>` and is shared with Atlas Team's
/// backend, which writes the same rows, so it cannot change without a
/// coordinated Team migration. Because `-` is also allowed inside codes, two
/// different positions can produce the same id: item `A-B` in warehouse `C`
/// and item `A` in warehouse `B-C` are both `BIN-A-B-C`, and one balance
/// would overwrite the other (stock valuation, the stock/GL check and the
/// negative-stock guard would then read the wrong row).
///
/// Ids Atlas generates itself (UUIDs) cannot collide that way. Codes chosen
/// by people (opening-data import, setup packs, typed ids) can, so
/// [BinIdentityGuardInterceptor] refuses a new item or warehouse code that
/// would collide with an existing position.
String binId(String item, String warehouse) => 'BIN-$item-$warehouse';

const _roles = {'System Manager'};

/// One ambiguous pair of stock positions.
typedef BinCollision = ({
  String binId,
  (String item, String warehouse) first,
  (String item, String warehouse) second,
});

/// Every pair of (item, warehouse) positions that share a Bin id, among the
/// given ids. Pure, so it can run over a whole catalogue in diagnostics.
List<BinCollision> findBinCollisions(
    Iterable<String> itemIds, Iterable<String> warehouseIds) {
  final items = itemIds.toSet();
  final warehouses = warehouseIds.toSet();
  // A collision needs a `-` in some item id AND in some warehouse id.
  if (!items.any((i) => i.contains('-')) ||
      !warehouses.any((w) => w.contains('-'))) {
    return const [];
  }
  final seen = <String, (String, String)>{};
  final out = <BinCollision>[];
  for (final i in items) {
    for (final w in warehouses) {
      final id = binId(i, w);
      final prior = seen[id];
      if (prior == null) {
        seen[id] = (i, w);
      } else {
        out.add((binId: id, first: prior, second: (i, w)));
      }
    }
  }
  return out;
}

/// A message naming the existing position that [itemId] (in any existing
/// warehouse) would share a Bin id with, or null when it is unambiguous.
Future<String?> binCollisionForItem(
    DocumentEngine engine, String itemId) async {
  final warehouses = [
    for (final w in await engine.list('Warehouse', userRoles: _roles)) w.id,
  ];
  for (final w in warehouses) {
    // Longer item `itemId-P` paired with warehouse W' where w == `P-W'`.
    for (var k = w.indexOf('-'); k >= 0; k = w.indexOf('-', k + 1)) {
      final other = '$itemId-${w.substring(0, k)}';
      final otherWh = w.substring(k + 1);
      if (warehouses.contains(otherWh) &&
          await engine.fetch('Item', other) != null) {
        return _message(itemId, w, other, otherWh);
      }
    }
    // Shorter item I where itemId == `I-P`, paired with warehouse `P-w`.
    for (var k = itemId.indexOf('-'); k >= 0; k = itemId.indexOf('-', k + 1)) {
      final other = itemId.substring(0, k);
      final otherWh = '${itemId.substring(k + 1)}-$w';
      if (warehouses.contains(otherWh) &&
          await engine.fetch('Item', other) != null) {
        return _message(itemId, w, other, otherWh);
      }
    }
  }
  return null;
}

/// As [binCollisionForItem], for a new warehouse code.
Future<String?> binCollisionForWarehouse(
    DocumentEngine engine, String warehouseId) async {
  final items = [
    for (final i in await engine.list('Item', userRoles: _roles)) i.id,
  ];
  final warehouses = [
    for (final w in await engine.list('Warehouse', userRoles: _roles))
      if (w.id != warehouseId) w.id,
    warehouseId,
  ];
  for (final c in findBinCollisions(items, warehouses)) {
    final (aItem, aWh) = c.first;
    final (bItem, bWh) = c.second;
    if (aWh == warehouseId) return _message(aItem, aWh, bItem, bWh);
    if (bWh == warehouseId) return _message(bItem, bWh, aItem, aWh);
  }
  return null;
}

String _message(String item, String wh, String otherItem, String otherWh) =>
    'Item "$item" in warehouse "$wh" would share a stock record with item '
    '"$otherItem" in warehouse "$otherWh" (both are ${binId(item, wh)}), '
    'and their stock balances would overwrite each other. Use a code '
    'without "-" here, or a different code.';

/// Refuses a NEW Item or Warehouse whose code would make two stock positions
/// share one Bin (see [binId]). Existing records are never touched; an
/// existing collision is reported in Settings › Help & diagnostics.
class BinIdentityGuardInterceptor extends DocumentInterceptor {
  const BinIdentityGuardInterceptor();

  @override
  Future<void> beforeSave(
      DocumentEngine engine, Document doc, DocType docType,
      {required bool isNew}) async {
    if (docType.id != 'Item' && docType.id != 'Warehouse') return;
    // An id Atlas assigns (a UUID, after this hook) is fixed-length and
    // never collides; only a caller-chosen id can. A hyphen-free code can
    // still be the shorter half of a collision, so it is checked too.
    if (doc.id.isEmpty) return;
    if (await engine.fetch(docType.id, doc.id) != null) return;
    final problem = docType.id == 'Item'
        ? await binCollisionForItem(engine, doc.id)
        : await binCollisionForWarehouse(engine, doc.id);
    if (problem == null) return;
    throw DocumentEngineError.validationFailed([
      ValidationError(
        stage: 'bin_identity',
        fieldKey: docType.id == 'Item' ? 'item_code' : 'warehouse_name',
        message: problem,
      ),
    ]);
  }
}
