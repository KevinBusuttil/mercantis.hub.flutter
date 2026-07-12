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
      await _costStockMovements(derived, source: source, reversal: reversal);
      // Perpetual inventory (Phase 1B): every costed stock movement posts its
      // GL counterpart (COGS / Inventory / GRNI / Adjustment)…
      derived.addAll(await _stockGlLegs(derived, source: source));
      // …and a Purchase Invoice's stock lines debit GRNI, not expense, so the
      // clearing account nets to zero once goods and bill are both in.
      if (source.docType == 'Purchase Invoice') {
        await _splitGrniFromExpense(derived, source, reversal: reversal);
      }

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

      if (LedgerDerivation.stockSources.contains(source.docType) ||
          isTrue(source.payload['update_stock'])) {
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
      {required Document source, required bool reversal}) async {
    final sleRows = [
      for (final d in derived)
        if (d.docType == LedgerDerivation.stockLedger) d,
    ];
    if (sleRows.isEmpty) return;

    if (reversal) {
      // Mirror the original row exactly — negated stock-unit qty and the same
      // cost — so a cancel backs out precisely what was posted, regardless of
      // any UOM conversion or costing applied on the original submit.
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
          row.payload['qty_change'] = -asNum(original.payload['qty_change']);
        }
      }
      return;
    }

    // Per-(item, warehouse) ledger: the saved prior rows plus the rows costed
    // earlier in this same voucher, so sequential issues consume in order.
    final ledgers = <(String, String), List<Map<String, dynamic>>>{};
    final items = <String, Document?>{};
    // A Transfer line's source-leg cost, so its target leg can match it.
    final outCostByItem = <String, num>{};
    // Total cost consumed by this voucher's outgoing legs. For a Manufacture
    // entry that is the raw-material cost, spread across the produced output.
    num consumedCost = 0;
    // Production (manufactured) output legs and their total qty, so the consumed
    // cost is allocated once across all output — not stamped in full per row.
    final productionLegs = <Map<String, dynamic>>[];
    num producedQty = 0;
    // On a return, stock coming back re-enters at the cost it left at, not at
    // the line's selling rate.
    final isReturn = isTrue(source.payload['is_return']);
    final returnAgainst = asNonEmpty(source.payload['return_against']);

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

    Future<Document?> itemFor(String item) async {
      if (items.containsKey(item)) return items[item];
      return items[item] = await engine.fetch('Item', item);
    }

    for (final row in sleRows) {
      final item = asNonEmpty(row.payload['item']);
      final wh = asNonEmpty(row.payload['warehouse']);
      if (item == null || wh == null) continue;
      final itemDoc = await itemFor(item);

      // Convert the line qty (in its transaction UOM) to stock units so the
      // Bin always tracks the stock UOM; receipts get their rate divided by the
      // same factor so total stock value is preserved across the conversion.
      final factor = uomFactor(itemDoc, asNonEmpty(row.payload['uom']));
      var qtyChange = asNum(row.payload['qty_change']);
      if (factor != 1) {
        qtyChange = qtyChange * factor;
        row.payload['qty_change'] = qtyChange;
      }

      final prior = await priorFor(item, wh);
      if (qtyChange < 0) {
        final method = asNonEmpty(itemDoc?.payload['valuation_method']);
        final rate = StockCosting.issueRate(prior, -qtyChange, method);
        row.payload['valuation_rate'] = rate;
        outCostByItem[item] = rate;
        consumedCost += -qtyChange * rate;
      } else if (qtyChange > 0) {
        final transType = row.payload['trans_type'];
        if (isReturn) {
          // Goods returning to stock re-enter at the cost they were sold at (the
          // original voucher's rate), falling back to the current average.
          row.payload['valuation_rate'] =
              await _returnCost(item, wh, returnAgainst, prior);
        } else if (transType == 'Transfer') {
          final rate = outCostByItem[item];
          if (rate != null) row.payload['valuation_rate'] = rate;
        } else if (transType == 'Production') {
          // Manufactured goods enter at production cost. Collect the output legs
          // and assign after the loop, so the consumed cost is allocated once
          // across the total qty made rather than in full to each output row.
          productionLegs.add(row.payload);
          producedQty += qtyChange;
        } else if (factor != 1) {
          row.payload['valuation_rate'] =
              asNum(row.payload['valuation_rate']) / factor;
        }
      }

      // Reflect this row in the simulated ledger for later lines of the pair.
      prior.add({
        'qty_change': qtyChange,
        'valuation_rate': asNum(row.payload['valuation_rate']),
      });
    }

    // Allocate the consumed raw cost across all produced output at one per-unit
    // rate, so total output value equals what was consumed (no value created
    // when an entry makes more than one product).
    if (productionLegs.isNotEmpty && producedQty > 0 && consumedCost > 0) {
      final rate = consumedCost / producedQty;
      for (final leg in productionLegs) {
        leg['valuation_rate'] = rate;
      }
    }
  }

  /// Perpetual inventory (Phase 1B): posts the GL counterpart of every costed
  /// Stock Ledger Entry, so the financial ledger finally tracks the stock
  /// subledger. Runs after [_costStockMovements] (issue rows carry their true
  /// valuation cost) and after [_dropNonStockMovements] (service items are
  /// gone), for both submit and cancel — a reversal SLE already carries the
  /// negated qty at the original cost, so its legs flip sides by sign alone.
  ///
  /// Mapping per movement value `v = qty_change × valuation_rate`:
  ///   sale vouchers (Delivery Note / POS Invoice / Sales Invoice):
  ///     v < 0  →  Dr COGS / Cr Inventory        (issue at cost)
  ///     v > 0  →  Dr Inventory / Cr COGS        (sales return)
  ///   purchase vouchers (Purchase Receipt / Purchase Invoice update_stock):
  ///     v > 0  →  Dr Inventory / Cr GRNI        (goods in, awaiting the bill)
  ///     v < 0  →  Dr GRNI / Cr Inventory        (purchase return)
  ///   Stock Entry issues / receipts / adjustments:
  ///     v > 0  →  Dr Inventory / Cr Stock Adjustment
  ///     v < 0  →  Dr Stock Adjustment / Cr Inventory
  ///   Transfers and Manufacture (Production) legs post no GL: with a single
  ///   company-level inventory account they are value-neutral by construction.
  ///
  /// Accounts resolve item → company default → seeded chart id. Costs are
  /// company/base currency by definition, so the legs carry conversion_rate 1.
  Future<List<DerivedDoc>> _stockGlLegs(List<DerivedDoc> derived,
      {required Document source}) async {
    final sleRows = [
      for (final d in derived)
        if (d.docType == LedgerDerivation.stockLedger) d,
    ];
    if (sleRows.isEmpty) return const [];

    const saleVouchers = {'Delivery Note', 'POS Invoice', 'Sales Invoice'};
    const purchaseVouchers = {'Purchase Receipt', 'Purchase Invoice'};
    final docType = source.docType;

    final company = source.company == null
        ? null
        : await engine.fetch('Company', source.company!);
    final items = <String, Document?>{};

    String resolve(Document? itemDoc, String itemField, String companyField,
            String seedId) =>
        asNonEmpty(itemDoc?.payload[itemField]) ??
        asNonEmpty(company?.payload[companyField]) ??
        seedId;

    final legs = <DerivedDoc>[];
    for (final row in sleRows) {
      final value = asNum(row.payload['qty_change']) *
          asNum(row.payload['valuation_rate']);
      if (value.abs() < 0.0000001) continue;
      final trans = '${row.payload['trans_type'] ?? ''}';
      if (trans == 'Transfer' || trans == 'Production') continue;

      final itemId = asNonEmpty(row.payload['item']);
      final itemDoc = itemId == null
          ? null
          : (items[itemId] ??= await engine.fetch('Item', itemId));

      final inventory = resolve(
          itemDoc, 'inventory_account', 'default_inventory_account', 'Stock');
      final String counter;
      if (saleVouchers.contains(docType)) {
        counter =
            resolve(itemDoc, 'cogs_account', 'default_cogs_account', 'COGS');
      } else if (purchaseVouchers.contains(docType)) {
        counter =
            asNonEmpty(company?.payload['default_grni_account']) ?? 'GRNI';
      } else {
        counter = resolve(itemDoc, 'stock_adjustment_account',
            'default_stock_adjustment_account', 'Stock Adjustment');
      }

      final amount = value.abs();
      final drAccount = value > 0 ? inventory : counter;
      final crAccount = value > 0 ? counter : inventory;
      final isReversal = isTrue(row.payload['is_reversal']);
      legs.add(_stockGl('${row.id}-gl-d', drAccount, amount, 0, row, isReversal));
      legs.add(_stockGl('${row.id}-gl-c', crAccount, 0, amount, row, isReversal));
    }
    return legs;
  }

  DerivedDoc _stockGl(String id, String account, num debit, num credit,
          DerivedDoc sle, bool reversal) =>
      DerivedDoc(LedgerDerivation.glEntry, id, {
        'posting_date': sle.payload['posting_date'],
        'account': account,
        'debit': debit,
        'credit': credit,
        'voucher_type': sle.payload['voucher_type'],
        'voucher_no': sle.payload['voucher_no'],
        'is_reversal': reversal,
        // Valuation cost is already company/base currency.
        'conversion_rate': 1,
        'base_debit': debit,
        'base_credit': credit,
      });

  /// Moves a Purchase Invoice's stock-line value off the expense leg and onto
  /// GRNI, so buying stock never lands in COGS at purchase time:
  ///   two-document flow: Receipt posts Dr Inventory / Cr GRNI, this bill
  ///     posts Dr GRNI / Cr AP — GRNI clears when both are in;
  ///   one-document flow (update_stock): the bill's own SLE legs post
  ///     Dr Inventory / Cr GRNI and this split posts Dr GRNI — GRNI nets to
  ///     zero inside the document.
  /// Service / non-stock lines keep today's expense treatment. Runs on both
  /// submit and cancel (the expense leg sits in the flipped column on a
  /// reversal). Amounts stay algebraically signed so debit-note returns
  /// (negative lines) flow through unchanged.
  Future<void> _splitGrniFromExpense(List<DerivedDoc> derived, Document source,
      {required bool reversal}) async {
    num stockNet = 0;
    final stockStatus = <String, bool>{};
    for (final row in source.children['items'] ?? const <ChildRow>[]) {
      final itemId = asNonEmpty(row.payload['item']);
      if (itemId == null) continue;
      final isStock = stockStatus[itemId] ??= isStockItem(
          (await engine.fetch('Item', itemId))?.payload ??
              const <String, dynamic>{});
      if (!isStock) continue;
      stockNet += row.payload.containsKey('amount')
          ? asNum(row.payload['amount'])
          : asNum(row.payload['qty']) * asNum(row.payload['rate']);
    }
    if (stockNet.abs() < 0.0000001) return;

    final sfx = reversalSuffix(reversal);
    final expenseId = 'GL-${source.id}-debit$sfx';
    DerivedDoc? expense;
    for (final d in derived) {
      if (d.docType == LedgerDerivation.glEntry && d.id == expenseId) {
        expense = d;
        break;
      }
    }
    if (expense == null) return;

    final rate = LedgerDerivation.conversionRate(source);
    final column = reversal ? 'credit' : 'debit';
    expense.payload[column] = asNum(expense.payload[column]) - stockNet;
    expense.payload['base_$column'] = asNum(expense.payload[column]) * rate;
    if (asNum(expense.payload['debit']).abs() < 0.0000001 &&
        asNum(expense.payload['credit']).abs() < 0.0000001) {
      derived.remove(expense);
    }

    final company = source.company == null
        ? null
        : await engine.fetch('Company', source.company!);
    final grni = asNonEmpty(company?.payload['default_grni_account']) ?? 'GRNI';
    derived.add(DerivedDoc(LedgerDerivation.glEntry, 'GL-${source.id}-grni$sfx', {
      'posting_date': source.payload['posting_date'],
      'account': grni,
      'debit': reversal ? 0 : stockNet,
      'credit': reversal ? stockNet : 0,
      'voucher_type': source.docType,
      'voucher_no': source.id,
      'is_reversal': reversal,
      'conversion_rate': rate,
      'base_debit': (reversal ? 0 : stockNet) * rate,
      'base_credit': (reversal ? stockNet : 0) * rate,
      if (asNonEmpty(source.payload['currency']) != null)
        'currency': source.payload['currency'],
    }));
  }

  /// The cost to re-enter returned stock for [item] in [wh]: the rate the
  /// original voucher ([returnAgainst]) moved this item at, or — only when no
  /// original row carries a usable rate — the current moving-average rate from
  /// [prior]. Never the line's selling rate.
  ///
  /// Prefers the original row in the *same* warehouse [wh] (so a multi-warehouse
  /// shipment restocks each warehouse at its own cost), but still falls back to
  /// any original row's rate when the goods are received into a different
  /// warehouse (e.g. a returns/quarantine bin) — that's the original issue cost,
  /// which beats the destination's average. Only an actually-numeric rate counts
  /// (a real 0 from a negative-stock sale is honoured; a blank/garbage rate is
  /// treated as missing).
  Future<num> _returnCost(String item, String wh, String? returnAgainst,
      List<Map<String, dynamic>> prior) async {
    if (returnAgainst != null) {
      final originals = await engine.list(LedgerDerivation.stockLedger,
          filters: {'voucher_no': returnAgainst, 'item': item},
          userRoles: systemRoles);
      num? anyRate;
      for (final o in originals) {
        final rate = _numOrNull(o.payload['valuation_rate']);
        if (rate == null) continue;
        if (asNonEmpty(o.payload['warehouse']) == wh) return rate; // exact match
        anyRate ??= rate; // else remember the original cost from any warehouse
      }
      if (anyRate != null) return anyRate;
    }
    return StockBalance.compute(prior).valuationRate;
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
    // An official_number marks a document posted by the Team backend, which
    // maintains outstanding_amount itself and replicates it here. Writing a
    // locally computed value would only enqueue a mutation the sync plane
    // must 409 (posted documents are immutable on it) — a permanently
    // quarantined failure manufactured out of thin air. Hands off.
    final official = invoice.payload['official_number'];
    if (official is String && official.isNotEmpty) return;

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

/// A value as a number when it actually is one (num, or a numeric string),
/// else null — so a present-but-blank/garbage field reads as missing rather
/// than coercing to 0. A real numeric 0 is returned as 0.
num? _numOrNull(dynamic v) {
  if (v is num) return v;
  if (v is String) return num.tryParse(v.trim());
  return null;
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
