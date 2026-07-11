import 'package:mercantis_core/mercantis_core.dart';

import '../ledger/ledger_values.dart';

/// One cart line for a POS sale.
class PosCartLine {
  const PosCartLine({required this.item, required this.qty, required this.rate, this.taxCode, this.warehouse});
  final String item;
  final num qty;
  final num rate;
  final String? taxCode;
  final String? warehouse;
}

/// One payment tender on a POS sale.
class PosTender {
  const PosTender({required this.type, required this.amount, this.reference});
  final String type; // Cash / Card / Other
  final num amount;
  final String? reference;
}

/// Pure helpers behind the POS checkout (ported from the Swift
/// `POSCheckoutBuilder`). Builds the POS Invoice document; VAT, totals and
/// change are stamped by the interceptors on save, and submitting drives the
/// cash + output-VAT GL legs and the stock issue.
abstract final class PosCheckout {
  /// Total tendered, rounded to currency precision.
  static num tendered(Iterable<PosTender> tenders) =>
      round2(tenders.fold<num>(0, (s, t) => s + t.amount));

  /// Whether the tenders cover the grand total.
  static bool isFullyPaid(Iterable<PosTender> tenders, num grandTotal) =>
      tendered(tenders) >= round2(grandTotal);

  /// Change owed to the customer (never negative).
  static num change(Iterable<PosTender> tenders, num grandTotal) {
    final diff = round2(tendered(tenders) - grandTotal);
    return diff > 0 ? diff : 0;
  }

  /// Builds the draft POS Invoice from a cart + tenders. `paid_amount` is set
  /// here; `total`/`tax_total`/`grand_total`/`taxes`/`change_amount` are filled
  /// by the interceptors on save.
  static Document buildPosInvoice({
    required String postingDate,
    String? posProfile,
    String? posSession,
    String? customer,
    String? currency,
    String? warehouse,
    String? cashAccount,
    String? incomeAccount,
    String? taxCode,
    String? company,
    String? tillSeries,
    String? priceList,
    bool pricesIncludeTax = false,
    required List<PosCartLine> lines,
    required List<PosTender> tenders,
  }) {
    final doc = Document(
      id: '',
      docType: 'POS Invoice',
      company: company,
      payload: {
        'posting_date': postingDate,
        if (asNonEmpty(posProfile) != null) 'pos_profile': posProfile,
        if (pricesIncludeTax) 'prices_include_tax': 1,
        if (asNonEmpty(posSession) != null) 'pos_session': posSession,
        // Drives the per-till receipt series naming rule (offline-safe ids).
        if (asNonEmpty(tillSeries) != null) 'till_series': tillSeries,
        // Provenance: which price list the till's rates came from (S8).
        if (asNonEmpty(priceList) != null) 'price_list': priceList,
        if (asNonEmpty(customer) != null) 'customer': customer,
        if (asNonEmpty(currency) != null) 'currency': currency,
        if (asNonEmpty(warehouse) != null) 'set_warehouse': warehouse,
        if (asNonEmpty(taxCode) != null) 'tax_code': taxCode,
        if (asNonEmpty(cashAccount) != null) 'cash_account': cashAccount,
        if (asNonEmpty(incomeAccount) != null) 'income_account': incomeAccount,
        'paid_amount': tendered(tenders),
      },
    );
    doc.children['items'] = [
      for (var i = 0; i < lines.length; i++)
        ChildRow(
          id: '',
          parentId: '',
          parentDocType: 'POS Invoice',
          tableName: 'items',
          rowIndex: i,
          payload: {
            'item': lines[i].item,
            'qty': lines[i].qty,
            'rate': lines[i].rate,
            if (asNonEmpty(lines[i].taxCode) != null) 'tax_code': lines[i].taxCode,
            if (asNonEmpty(lines[i].warehouse) != null) 'warehouse': lines[i].warehouse,
          },
        ),
    ];
    doc.children['tenders'] = [
      for (var i = 0; i < tenders.length; i++)
        ChildRow(
          id: '',
          parentId: '',
          parentDocType: 'POS Invoice',
          tableName: 'tenders',
          rowIndex: i,
          payload: {
            'tender_type': tenders[i].type,
            'amount': tenders[i].amount,
            if (asNonEmpty(tenders[i].reference) != null) 'reference': tenders[i].reference,
          },
        ),
    ];
    return doc;
  }
}
