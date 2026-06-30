import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

import 'derived_doc.dart';
import 'ledger_derivation.dart';
import 'ledger_values.dart';
import 'stock_balance.dart';
import 'stock_costing.dart';

/// Subscribes to document submit/cancel events and persists the rows produced
/// by [LedgerDerivation], then recomputes affected `Bin` balances. This is the
/// runtime half of the ledger spine; all the accounting logic lives in the
/// pure [LedgerDerivation]/[StockBalance] classes so it can be tested without a
/// database.
///
/// Saves run with a System Manager role so the engine's permission gate is
/// satisfied. Errors are isolated per event (a bad voucher must not crash the
/// app or block later postings).
class LedgerDerivationService {
  final DocumentEngine engine;
  final EventEmitter emitter;
  final Set<String> systemRoles;
  final void Function(Object error, StackTrace stack)? onError;

  final List<SubscriptionToken> _tokens = [];

  LedgerDerivationService({
    required this.engine,
    required this.emitter,
    this.systemRoles = const {'System Manager'},
    this.onError,
  });

  void start() {
    _tokens.add(emitter.subscribe<DocumentSubmittedEvent>(
        (e) => _handle(e.document, reversal: false)));
    _tokens.add(emitter.subscribe<DocumentCancelledEvent>(
        (e) => _handle(e.document, reversal: true)));
  }

  void dispose() {
    for (final t in _tokens) {
      t.cancel();
    }
    _tokens.clear();
  }

  Future<void> _handle(Document doc, {required bool reversal}) async {
    try {
      // Re-fetch for authoritative payload + child rows; the event document may
      // be a lighter copy.
      final source = await engine.fetch(doc.docType, doc.id) ?? doc;
      await _resolveAccounts(source);
      var derived = LedgerDerivation.derive(source, reversal: reversal);
      derived = await _dropNonStockMovements(derived);
      if (derived.isEmpty) return;
      await _costStockMovements(derived, reversal: reversal);

      for (final row in derived) {
        await engine.save(
          Document(
            id: row.id,
            docType: row.docType,
            company: source.company,
            payload: Map<String, dynamic>.from(row.payload),
          ),
          systemRoles,
        );
      }

      if (LedgerDerivation.stockSources.contains(source.docType)) {
        await _recomputeBins(derived, source.company);
      }
      await _maintainOutstanding(source, derived, reversal);
    } catch (e, s) {
      onError?.call(e, s);
    }
  }

  /// Drops Stock Ledger Entry rows for non-stock (service) items so they never
  /// reach the ledger or a Bin recompute. The pure [LedgerDerivation] emits an
  /// SLE for every item line — it can't fetch the Item to know its type — so the
  /// service, which can, filters them here. Without this a service line on a
  /// Delivery Note / POS Invoice / Stock Entry would pass the guard yet still
  /// spawn a phantom `SLE-*` and a negative `BIN-<service item>-<warehouse>`.
  /// Non-stock rows (GL, subledgers, tax, settlement) always pass through; Item
  /// lookups are cached so repeated lines cost a single fetch.
  Future<List<DerivedDoc>> _dropNonStockMovements(
      List<DerivedDoc> derived) async {
    final stockStatus = <String, bool>{};
    final kept = <DerivedDoc>[];
    for (final row in derived) {
      if (row.docType != LedgerDerivation.stockLedger) {
        kept.add(row);
        continue;
      }
      final item = asNonEmpty(row.payload['item']);
      if (item == null) {
        kept.add(row);
        continue;
      }
      final isStock = stockStatus[item] ??= isStockItem(
          (await engine.fetch('Item', item))?.payload ??
              const <String, dynamic>{});
      if (isStock) kept.add(row);
    }
    return kept;
  }

  /// Costs the voucher's outgoing Stock Ledger Entry rows before they are saved,
  /// so an issue removes inventory at the item's valuation-method *cost* rather
  /// than the selling rate the pure derivation defaults to. Receipts keep their
  /// supplied rate; a Transfer's incoming leg inherits its outgoing leg's cost
  /// so stock value is preserved across the move. On a cancel every row instead
  /// reuses the original SLE's saved rate, so the reversal backs out exactly
  /// what was posted (re-costing against current on-hand would leak value).
  Future<void> _costStockMovements(List<DerivedDoc> derived,
      {required bool reversal}) async {
    final sleRows = [
      for (final d in derived)
        if (d.docType == LedgerDerivation.stockLedger) d,
    ];
    if (sleRows.isEmpty) return;

    if (reversal) {
      const suffix = '-reversal';
      for (final row in sleRows) {
        final originalId = row.id.endsWith(suffix)
            ? row.id.substring(0, row.id.length - suffix.length)
            : row.id;
        final original =
            await engine.fetch(LedgerDerivation.stockLedger, originalId);
        if (original != null) {
          row.payload['valuation_rate'] =
              asNum(original.payload['valuation_rate']);
        }
      }
      return;
    }

    // Per-(item, warehouse) ledger: the saved prior rows plus the rows costed
    // earlier in this same voucher, so sequential issues consume in order.
    final ledgers = <(String, String), List<Map<String, dynamic>>>{};
    final methods = <String, String?>{};
    // A Transfer line's source-leg cost, so its target leg can match it.
    final outCostByItem = <String, num>{};

    Future<List<Map<String, dynamic>>> priorFor(String item, String wh) async {
      final key = (item, wh);
      final cached = ledgers[key];
      if (cached != null) return cached;
      final docs = await engine.list(LedgerDerivation.stockLedger,
          filters: {'item': item, 'warehouse': wh}, userRoles: systemRoles);
      // FIFO replay is order-sensitive and engine.list order isn't guaranteed,
      // so order the prior ledger oldest-first. posting_date is only day-level,
      // so break same-day ties by creation order (the true save sequence) and
      // finally by id, giving a fully deterministic replay.
      docs.sort(_byPostingThenCreation);
      final rows = [for (final d in docs) d.payload];
      ledgers[key] = rows;
      return rows;
    }

    Future<String?> methodFor(String item) async {
      if (methods.containsKey(item)) return methods[item];
      final m = asNonEmpty(
          (await engine.fetch('Item', item))?.payload['valuation_method']);
      methods[item] = m;
      return m;
    }

    for (final row in sleRows) {
      final item = asNonEmpty(row.payload['item']);
      final wh = asNonEmpty(row.payload['warehouse']);
      if (item == null || wh == null) continue;
      final qtyChange = asNum(row.payload['qty_change']);
      final prior = await priorFor(item, wh);

      if (qtyChange < 0) {
        final rate =
            StockCosting.issueRate(prior, -qtyChange, await methodFor(item));
        row.payload['valuation_rate'] = rate;
        outCostByItem[item] = rate;
      } else if (qtyChange > 0 && row.payload['trans_type'] == 'Transfer') {
        final rate = outCostByItem[item];
        if (rate != null) row.payload['valuation_rate'] = rate;
      }

      // Reflect this row in the simulated ledger for later lines of the pair.
      prior.add({
        'qty_change': qtyChange,
        'valuation_rate': asNum(row.payload['valuation_rate']),
      });
    }
  }

  /// Fills any blank posting account on the source from its Company defaults
  /// (see [LedgerDerivation.accountFallbacks]) so a minimal voucher still posts
  /// to balanced GL accounts. Explicit values on the document always win; the
  /// Company is fetched only when something is actually missing. Mutates the
  /// in-memory [source] payload — safe, as the source row itself is never saved.
  Future<void> _resolveAccounts(Document source) async {
    final fallbacks = LedgerDerivation.accountFallbacks(
      source.docType,
      paymentType: source.payload['payment_type'],
    );
    final missing = {
      for (final entry in fallbacks.entries)
        if (asNonEmpty(source.payload[entry.key]) == null) entry.key: entry.value,
    };
    if (missing.isEmpty) return;

    final company = source.company;
    if (company == null) return;
    final defaults = await engine.fetch('Company', company);
    if (defaults == null) return;

    for (final entry in missing.entries) {
      final value = asNonEmpty(defaults.payload[entry.value]);
      if (value != null) source.payload[entry.key] = value;
    }
  }

  /// Keeps invoice `outstanding_amount` current (the "Mark as Paid" guard reads
  /// it). Recomputed from the Settlement subledger rather than incremented, so
  /// it is idempotent across re-fires and reversals.
  Future<void> _maintainOutstanding(
      Document source, List<DerivedDoc> derived, bool reversal) async {
    if (source.docType == 'Sales Invoice' || source.docType == 'Purchase Invoice') {
      // On submit, initialise from grand_total (no settlements yet). On cancel
      // the invoice is no longer docStatus==1, so leave it untouched.
      if (!reversal) {
        await recomputeOutstanding(source.docType, source.id);
      }
      return;
    }
    if (source.docType == 'Payment Entry') {
      final refs = <String, List<String>>{};
      for (final d in derived) {
        if (d.docType != LedgerDerivation.settlement) continue;
        final type = d.payload['invoice_voucher_type'];
        final no = d.payload['invoice_voucher_no'];
        if (type is String && no is String) refs['$type $no'] = [type, no];
      }
      for (final ref in refs.values) {
        await recomputeOutstanding(ref[0], ref[1]);
      }
    }
  }

  Future<void> recomputeOutstanding(String invoiceDocType, String invoiceId) async {
    final invoice = await engine.fetch(invoiceDocType, invoiceId);
    // Only maintain submitted invoices; applyOnSubmitUpdate requires docStatus==1.
    if (invoice == null || invoice.docStatus != 1) return;

    final settlements = await engine.list(
      LedgerDerivation.settlement,
      filters: {
        'invoice_voucher_type': invoiceDocType,
        'invoice_voucher_no': invoiceId,
      },
      userRoles: systemRoles,
    );
    final outstanding = outstandingAmount(
      asNum(invoice.payload['grand_total']),
      [for (final s in settlements) asNum(s.payload['allocated_amount'])],
    );
    if (asNum(invoice.payload['outstanding_amount']) == outstanding) return;

    invoice.payload['outstanding_amount'] = outstanding;
    await engine.applyOnSubmitUpdate(invoice, systemRoles);
  }

  Future<void> _recomputeBins(List<DerivedDoc> derived, String? company) async {
    final pairs = <String, List<String>>{};
    for (final d in derived) {
      if (d.docType != LedgerDerivation.stockLedger) continue;
      final item = d.payload['item'];
      final warehouse = d.payload['warehouse'];
      if (item is String && warehouse is String) {
        pairs['$item $warehouse'] = [item, warehouse];
      }
    }
    for (final pair in pairs.values) {
      await recomputeBin(pair[0], pair[1], company: company);
    }
  }

  /// Rebuilds every derived balance from the authoritative subledgers: each
  /// `Bin` from its Stock Ledger Entries, and each submitted invoice's
  /// `outstanding_amount` from its Settlements. Idempotent, so it is safe to run
  /// after a sync pull — where peers' append-only ledger rows have merged in but
  /// the recomputed balances (which would otherwise conflict under last-write-
  /// wins) must be re-derived locally rather than trusted from the wire.
  Future<void> recomputeAllDerived() async {
    final sles = await engine.list(LedgerDerivation.stockLedger,
        userRoles: systemRoles);
    final pairs = <String, List<String?>>{};
    for (final s in sles) {
      final item = s.payload['item'];
      final warehouse = s.payload['warehouse'];
      if (item is String && warehouse is String) {
        pairs['$item $warehouse'] = [item, warehouse, s.company];
      }
    }
    for (final pair in pairs.values) {
      await recomputeBin(pair[0]!, pair[1]!, company: pair[2]);
    }

    for (final docType in const ['Sales Invoice', 'Purchase Invoice']) {
      final invoices = await engine.list(docType, userRoles: systemRoles);
      for (final inv in invoices) {
        if (inv.docStatus == 1) await recomputeOutstanding(docType, inv.id);
      }
    }
  }

  /// Reads the full stock ledger for (item, warehouse), folds it into a balance,
  /// and upserts the deterministic `BIN-<item>-<warehouse>` row.
  Future<void> recomputeBin(String item, String warehouse,
      {String? company}) async {
    final rows = await engine.list(
      LedgerDerivation.stockLedger,
      filters: {'item': item, 'warehouse': warehouse},
      userRoles: systemRoles,
    );
    final snap = StockBalance.compute([for (final d in rows) d.payload]);

    // Skip the write when nothing changed. Beyond saving a redundant row, this
    // keeps sync from churning: an unconditional re-save would re-queue an
    // identical Bin mutation on every pull, which the peer would pull and
    // re-push forever. Recomputed-but-equal balances must not produce traffic.
    final id = 'BIN-$item-$warehouse';
    final existing = await engine.fetch(LedgerDerivation.bin, id);
    if (existing != null &&
        asNum(existing.payload['actual_qty']) == snap.actualQty &&
        asNum(existing.payload['valuation_rate']) == snap.valuationRate &&
        asNum(existing.payload['stock_value']) == snap.stockValue) {
      return;
    }

    await engine.save(
      Document(
        id: id,
        docType: LedgerDerivation.bin,
        company: company,
        payload: {
          'item': item,
          'warehouse': warehouse,
          'actual_qty': snap.actualQty,
          'valuation_rate': snap.valuationRate,
          'stock_value': snap.stockValue,
          if (snap.lastMovementDate != null)
            'last_movement_date': snap.lastMovementDate,
        },
      ),
      systemRoles,
    );
  }
}

/// Orders stock-ledger rows oldest-first for the FIFO replay: by posting date,
/// then — since posting_date is only day-level — by creation order (the true
/// save sequence), then by id as a final deterministic tiebreaker so two
/// same-day, same-instant rows never swap.
int _byPostingThenCreation(Document a, Document b) {
  final byDate = _postingMillis(a.payload).compareTo(_postingMillis(b.payload));
  if (byDate != 0) return byDate;
  final byCreated = a.createdAt.millisecondsSinceEpoch
      .compareTo(b.createdAt.millisecondsSinceEpoch);
  if (byCreated != 0) return byCreated;
  return a.id.compareTo(b.id);
}

/// A stock-ledger row's posting date as epoch milliseconds (epoch int or ISO
/// string, as stored), 0 when absent.
int _postingMillis(Map<String, dynamic> row) {
  final v = row['posting_date'];
  if (v is int) return v;
  if (v is String) return DateTime.tryParse(v)?.millisecondsSinceEpoch ?? 0;
  return 0;
}

/// Constructs and starts the ledger derivation service, kept alive for the app
/// lifetime. The boot sequence awaits this so postings are wired before the
/// user can submit anything.
final ledgerDerivationServiceProvider =
    FutureProvider<LedgerDerivationService>((ref) async {
  final engine = await ref.watch(documentEngineProvider.future);
  final emitter = ref.watch(eventEmitterProvider);
  final service = LedgerDerivationService(engine: engine, emitter: emitter);
  service.start();
  ref.onDispose(service.dispose);
  return service;
});
