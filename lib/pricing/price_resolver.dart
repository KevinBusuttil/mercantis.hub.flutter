import 'package:mercantis_core/mercantis_core.dart';

import '../ledger/ledger_values.dart';

const _systemRoles = {'System Manager'};

/// Where a resolved rate came from — shown nowhere yet, but stamped onto the
/// document (`price_list`) so a price is always explainable.
class ResolvedPrice {
  const ResolvedPrice({required this.rate, this.priceList});

  final num rate;

  /// The Price List that supplied the rate; null when it fell back to the
  /// item's standard selling rate.
  final String? priceList;
}

/// S8 price resolution (Phase 1): the deterministic order every selling
/// document uses to price a line.
///
///   1. the document's explicit `price_list` (POS profile till list,
///      channel list, or hand-picked on the form);
///   2. the customer's `default_price_list`;
///   3. the company's `default_selling_price_list`;
///   4. the item's `standard_rate`.
///
/// Within a Price List, the best matching Item Price row wins: item matches,
/// the date falls inside `valid_from`/`valid_upto` (either open-ended), and
/// `min_qty` ≤ the line quantity. Among matches the HIGHEST `min_qty` wins
/// (the deepest quantity break earned), then the latest `valid_from` (the
/// most recent promotion). Disabled lists, buying-only lists, and lists in a
/// different currency than the document are skipped entirely.
class PriceResolver {
  PriceResolver(this._engine);

  final DocumentEngine _engine;

  Future<ResolvedPrice?> resolve({
    required String item,
    num qty = 1,
    String? customer,
    String? priceList,
    String? currency,
    String? onDate,
  }) async {
    final date = asNonEmpty(onDate) ?? _todayIso();
    for (final listId in await _candidateLists(
        explicit: priceList, customer: customer)) {
      final rate = await _rateFromList(
        listId: listId,
        item: item,
        qty: qty,
        currency: currency,
        date: date,
      );
      if (rate != null) return ResolvedPrice(rate: rate, priceList: listId);
    }
    final itemDoc = await _engine.fetch('Item', item);
    final standard = asNum(itemDoc?.payload['standard_rate']);
    return standard > 0 ? ResolvedPrice(rate: standard) : null;
  }

  /// All rates a Price List offers at quantity 1 on [onDate] — the POS
  /// till's product-button prices. Items absent from the list fall back to
  /// their standard rate at display time (the till handles that).
  Future<Map<String, num>> sellingRates({
    required String priceList,
    String? currency,
    String? onDate,
  }) async {
    final date = asNonEmpty(onDate) ?? _todayIso();
    final list = await _loadSellingList(priceList, currency);
    if (list == null) return const {};
    final rates = <String, num>{};
    final items = <String>{
      for (final row in list.children['items'] ?? const <ChildRow>[])
        if (asNonEmpty(row.payload['item']) != null)
          row.payload['item'] as String,
    };
    for (final item in items) {
      final rate = _bestRow(list, item: item, qty: 1, date: date);
      if (rate != null) rates[item] = rate;
    }
    return rates;
  }

  Future<List<String>> _candidateLists({
    String? explicit,
    String? customer,
  }) async {
    final candidates = <String>[];
    void add(dynamic id) {
      final v = asNonEmpty(id);
      if (v != null && !candidates.contains(v)) candidates.add(v);
    }

    add(explicit);
    if (asNonEmpty(customer) != null) {
      final c = await _engine.fetch('Customer', customer!);
      add(c?.payload['default_price_list']);
    }
    final companies = await _engine.list('Company', userRoles: _systemRoles);
    if (companies.isNotEmpty) {
      add(companies.first.payload['default_selling_price_list']);
    }
    return candidates;
  }

  Future<num?> _rateFromList({
    required String listId,
    required String item,
    required num qty,
    required String date,
    String? currency,
  }) async {
    final list = await _loadSellingList(listId, currency);
    if (list == null) return null;
    return _bestRow(list, item: item, qty: qty, date: date);
  }

  /// The list, hydrated with its Item Price rows — or null when it doesn't
  /// exist, is disabled, isn't a selling list, or is in another currency.
  Future<Document?> _loadSellingList(String listId, String? currency) async {
    final list = await _engine.fetch('Price List', listId);
    if (list == null) return null;
    if (!isTrue(list.payload['enabled'])) return null;
    if (!isTrue(list.payload['selling'])) return null;
    final listCurrency = asNonEmpty(list.payload['currency']);
    final docCurrency = asNonEmpty(currency);
    if (listCurrency != null &&
        docCurrency != null &&
        listCurrency != docCurrency) {
      return null;
    }
    return list;
  }

  num? _bestRow(
    Document list, {
    required String item,
    required num qty,
    required String date,
  }) {
    num? bestRate;
    num bestMinQty = -1;
    String bestFrom = '';
    for (final row in list.children['items'] ?? const <ChildRow>[]) {
      if (asNonEmpty(row.payload['item']) != item) continue;
      final rate = asNum(row.payload['rate']);
      if (rate <= 0) continue;
      final from = asNonEmpty(row.payload['valid_from']) ?? '';
      final upto = asNonEmpty(row.payload['valid_upto']);
      // ISO dates compare correctly as strings.
      if (from.isNotEmpty && from.compareTo(date) > 0) continue;
      if (upto != null && upto.compareTo(date) < 0) continue;
      final minQty = asNum(row.payload['min_qty']);
      if (minQty > qty) continue;
      final better = minQty > bestMinQty ||
          (minQty == bestMinQty && from.compareTo(bestFrom) > 0);
      if (better) {
        bestRate = rate;
        bestMinQty = minQty;
        bestFrom = from;
      }
    }
    return bestRate;
  }

  static String _todayIso() =>
      DateTime.now().toIso8601String().split('T').first;
}

/// Fills blank line rates on selling documents from [PriceResolver], before
/// [LineItemTotalsInterceptor] turns rates into amounts. A rate the user (or
/// a channel) already entered is never touched — resolution is a default,
/// not an override. The first list that actually priced a line is stamped
/// onto the document's `price_list` for provenance.
class PriceResolutionInterceptor extends DocumentInterceptor {
  const PriceResolutionInterceptor();

  static const _sellingDocTypes = {
    'Quotation',
    'Sales Order',
    'Sales Invoice',
    'POS Invoice',
  };

  @override
  Future<void> beforeSave(
      DocumentEngine engine, Document doc, DocType docType,
      {required bool isNew}) async {
    if (!_sellingDocTypes.contains(docType.id)) return;
    final rows = doc.children['items'];
    if (rows == null || rows.isEmpty) return;

    final resolver = PriceResolver(engine);
    final onDate = asNonEmpty(doc.payload['posting_date']) ??
        asNonEmpty(doc.payload['transaction_date']);
    String? usedList;
    for (final row in rows) {
      if (asNum(row.payload['rate']) != 0) continue; // user-entered — keep
      final item = asNonEmpty(row.payload['item']);
      if (item == null) continue;
      final resolved = await resolver.resolve(
        item: item,
        qty: asNum(row.payload['qty']) == 0 ? 1 : asNum(row.payload['qty']),
        customer: asNonEmpty(doc.payload['customer']),
        priceList: asNonEmpty(doc.payload['price_list']),
        currency: asNonEmpty(doc.payload['currency']),
        onDate: onDate,
      );
      if (resolved == null) continue;
      row.payload['rate'] = resolved.rate;
      usedList ??= resolved.priceList;
    }

    final keys = {for (final f in docType.fields) f.key};
    if (usedList != null &&
        keys.contains('price_list') &&
        asNonEmpty(doc.payload['price_list']) == null) {
      doc.payload['price_list'] = usedList;
    }
  }
}
