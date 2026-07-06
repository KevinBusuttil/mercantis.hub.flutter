import 'package:mercantis_core/mercantis_core.dart';

import 'derived_doc.dart';
import 'ledger_values.dart';

/// Pure, database-free derivation of ledger rows from a source document.
///
/// Ported from the Swift `LedgerDerivationService`. Given a submitted (or, with
/// `reversal: true`, a cancelled) document it returns the GL entries, customer/
/// supplier subledger rows, settlements, and stock-ledger entries that should
/// be persisted. Every row carries a deterministic id so saving is idempotent,
/// and reversal rows are the originals with amounts/qty flipped, an
/// `is_reversal` flag, and a `-reversal` id suffix.
///
/// Blank posting accounts are resolved from the source's Company defaults by
/// the runner (see [accountFallbacks]) before derivation, so a minimal voucher
/// still posts to balanced accounts.
///
/// Invoices split the income/expense side into net + VAT: when a `taxes` child
/// table is present (populated on save by `TaxCalculationInterceptor`) each tax
/// row posts a GL leg (output VAT credited on sales, input VAT debited on
/// purchases) plus a `Tax Transaction` subledger row. With no tax rows this
/// collapses to the original balanced 2-leg posting.
///
/// Deliberately NOT yet handled (flagged in PARITY.md):
///  * POSInvoice (POS module not ported).
abstract final class LedgerDerivation {
  // Derived DocType ids (match the Phase 2 manifest).
  static const glEntry = 'GL Entry';
  static const customerTxn = 'Customer Transaction';
  static const supplierTxn = 'Supplier Transaction';
  static const settlement = 'Settlement';
  static const taxTxn = 'Tax Transaction';
  static const stockLedger = 'Stock Ledger Entry';
  static const bin = 'Bin';

  /// Source DocTypes that move stock and therefore require a Bin recompute.
  static const stockSources = {'Stock Entry', 'Purchase Receipt', 'Delivery Note', 'POS Invoice'};

  /// Vouchers whose monetary ledger rows are denominated in the document's
  /// transaction `currency`, so base-currency amounts get stamped onto them
  /// (GL `base_debit`/`base_credit`, customer/supplier `base_amount`). Stock
  /// vouchers (POS / Delivery / Receipt / Stock Entry) carry their cost on
  /// Stock Ledger Entries at moving-average/FIFO cost — already in base
  /// currency — so they're excluded. NOTE: stock movements currently post to
  /// the stock subledger only; they do NOT yet emit GL COGS / Inventory Asset
  /// legs (see docs/STOCK_COGS_IMPLEMENTATION_PLAN.md, Track A).
  /// Mirrors the Swift `baseStampDocTypes`.
  static const _baseStampDocTypes = {
    'Sales Invoice',
    'Purchase Invoice',
    'Payment Entry',
    'Journal Entry',
  };

  /// Maps each posting-account field that a voucher may leave blank to the
  /// `Company` default field that should fill it. The runner uses this to
  /// resolve missing accounts from the company before derivation, so a minimal
  /// invoice/payment still posts to balanced GL accounts. An empty map means
  /// "no fallbacks" (unknown DocType, or a payment with no party direction).
  static Map<String, String> accountFallbacks(String docType, {Object? paymentType}) {
    switch (docType) {
      case 'Sales Invoice':
        return const {
          'debit_to': 'default_receivable_account',
          'income_account': 'default_income_account',
        };
      case 'Purchase Invoice':
        return const {
          'credit_to': 'default_payable_account',
          'expense_account': 'default_expense_account',
        };
      case 'POS Invoice':
        return const {
          'cash_account': 'default_cash_account',
          'income_account': 'default_income_account',
        };
      case 'Payment Entry':
        if (paymentType == 'Receive') {
          return const {
            'paid_from': 'default_receivable_account',
            'paid_to': 'default_cash_account',
          };
        }
        if (paymentType == 'Pay') {
          return const {
            'paid_from': 'default_cash_account',
            'paid_to': 'default_payable_account',
          };
        }
        return const {};
      default:
        return const {};
    }
  }

  /// Returns the ledger rows for [doc]. `reversal` is false on submit, true on
  /// cancel. Unknown DocTypes yield an empty list (no-op, prevents re-entrancy).
  static List<DerivedDoc> derive(Document doc, {required bool reversal}) {
    final rows = _deriveRows(doc, reversal: reversal);
    if (_baseStampDocTypes.contains(doc.docType)) {
      _stampBaseAmounts(rows, doc);
    }
    return rows;
  }

  static List<DerivedDoc> _deriveRows(Document doc, {required bool reversal}) {
    switch (doc.docType) {
      case 'Sales Invoice':
        return _salesInvoice(doc, reversal);
      case 'Purchase Invoice':
        return _purchaseInvoice(doc, reversal);
      case 'POS Invoice':
        return _posInvoice(doc, reversal);
      case 'Payment Entry':
        return _paymentEntry(doc, reversal);
      case 'Journal Entry':
        return _journalEntry(doc, reversal);
      case 'Stock Entry':
        return _stockEntry(doc, reversal);
      case 'Purchase Receipt':
        return _stockDocument(doc, reversal, incoming: true, transType: 'Receipt');
      case 'Delivery Note':
        return _stockDocument(doc, reversal, incoming: false, transType: 'Issue');
      default:
        return const [];
    }
  }

  // ---- sales / purchase invoices -----------------------------------------

  static List<DerivedDoc> _salesInvoice(Document doc, bool reversal) {
    final id = doc.id;
    final p = doc.payload;
    final grand = asNum(p['grand_total']);
    final taxRows = doc.children['taxes'] ?? const [];
    final net = grand - _totalTax(taxRows); // income net of VAT
    final customer = asNonEmpty(p['customer']);
    final sfx = reversalSuffix(reversal);
    return [
      // Dr Accounts Receivable (gross — customer owes net + VAT)
      _gl(
        id: 'GL-$id-debit$sfx',
        account: asNonEmpty(p['debit_to']),
        debit: reversal ? 0 : grand,
        credit: reversal ? grand : 0,
        partyType: 'Customer',
        party: customer,
        voucherType: doc.docType,
        voucherNo: id,
        postingDate: p['posting_date'],
        reversal: reversal,
      ),
      // Cr Income (net of tax)
      _gl(
        id: 'GL-$id-credit$sfx',
        account: asNonEmpty(p['income_account']),
        debit: reversal ? net : 0,
        credit: reversal ? 0 : net,
        voucherType: doc.docType,
        voucherNo: id,
        postingDate: p['posting_date'],
        reversal: reversal,
      ),
      // Customer subledger: positive = customer owes us.
      DerivedDoc(customerTxn, 'CT-$id$sfx', {
        'trans_type': reversal ? 'CreditNote' : 'Invoice',
        'customer': customer,
        'posting_date': p['posting_date'],
        'due_date': p['due_date'],
        'amount': negate(grand, reversal),
        'currency': p['currency'],
        'voucher_type': doc.docType,
        'voucher_no': id,
        'is_reversal': reversal,
      }),
      // Cr Output VAT — one GL leg + one Tax Transaction row per tax line.
      ..._taxLegs(doc, reversal,
          isOutput: true, partyType: 'Customer', party: customer),
    ];
  }

  static List<DerivedDoc> _purchaseInvoice(Document doc, bool reversal) {
    final id = doc.id;
    final p = doc.payload;
    final grand = asNum(p['grand_total']);
    final taxRows = doc.children['taxes'] ?? const [];
    final net = grand - _totalTax(taxRows); // expense net of VAT
    final supplier = asNonEmpty(p['supplier']);
    final sfx = reversalSuffix(reversal);
    return [
      // Cr Accounts Payable (gross — we owe net + VAT)
      _gl(
        id: 'GL-$id-credit$sfx',
        account: asNonEmpty(p['credit_to']),
        debit: reversal ? grand : 0,
        credit: reversal ? 0 : grand,
        partyType: 'Supplier',
        party: supplier,
        voucherType: doc.docType,
        voucherNo: id,
        postingDate: p['posting_date'],
        reversal: reversal,
      ),
      // Dr Expense (net of tax)
      _gl(
        id: 'GL-$id-debit$sfx',
        account: asNonEmpty(p['expense_account']),
        debit: reversal ? 0 : net,
        credit: reversal ? net : 0,
        voucherType: doc.docType,
        voucherNo: id,
        postingDate: p['posting_date'],
        reversal: reversal,
      ),
      // Supplier subledger: positive = we owe the supplier.
      DerivedDoc(supplierTxn, 'VT-$id$sfx', {
        'trans_type': reversal ? 'CreditNote' : 'Invoice',
        'supplier': supplier,
        'posting_date': p['posting_date'],
        'due_date': p['due_date'],
        'amount': negate(grand, reversal),
        'currency': p['currency'],
        'voucher_type': doc.docType,
        'voucher_no': id,
        'is_reversal': reversal,
      }),
      // Dr Input VAT — one GL leg + one Tax Transaction row per tax line.
      ..._taxLegs(doc, reversal,
          isOutput: false, partyType: 'Supplier', party: supplier),
    ];
  }

  // ---- POS invoice (cash sale) -------------------------------------------

  /// Cash sale: issue stock (like a delivery), then Dr Cash / Cr Income (net) +
  /// output VAT. No receivable and no party subledger — payment is inline.
  static List<DerivedDoc> _posInvoice(Document doc, bool reversal) {
    final id = doc.id;
    final p = doc.payload;
    final grand = asNum(p['grand_total']);
    final taxRows = doc.children['taxes'] ?? const [];
    final net = grand - _totalTax(taxRows);
    final customer = asNonEmpty(p['customer']);
    final sfx = reversalSuffix(reversal);
    return [
      // Stock issue per line (−qty on submit, flipped on reversal).
      ..._stockDocument(doc, reversal, incoming: false, transType: 'Issue'),
      // Dr Cash / Bank — gross received.
      _gl(
        id: 'GL-$id-cash$sfx',
        account: asNonEmpty(p['cash_account']),
        debit: reversal ? 0 : grand,
        credit: reversal ? grand : 0,
        voucherType: doc.docType,
        voucherNo: id,
        postingDate: p['posting_date'],
        reversal: reversal,
      ),
      // Cr Income — net of tax.
      _gl(
        id: 'GL-$id-income$sfx',
        account: asNonEmpty(p['income_account']),
        debit: reversal ? net : 0,
        credit: reversal ? 0 : net,
        voucherType: doc.docType,
        voucherNo: id,
        postingDate: p['posting_date'],
        reversal: reversal,
      ),
      // Cr Output VAT — one GL leg + one Tax Transaction row per tax line.
      ..._taxLegs(doc, reversal,
          isOutput: true, partyType: 'Customer', party: customer),
    ];
  }

  // ---- tax legs (VAT) -----------------------------------------------------

  /// Sum of `tax_amount` across an invoice's `taxes` child rows.
  static num _totalTax(List<ChildRow> rows) =>
      rows.fold<num>(0, (s, r) => s + asNum(r.payload['tax_amount']));

  /// For each invoice tax row, post the VAT GL leg (credit for output / sales,
  /// debit for input / purchases) to the row's `tax_account`, plus a signed
  /// `Tax Transaction` subledger row. A zero-amount row posts no GL leg but
  /// still records its taxable base in the subledger (needed for the VAT
  /// return). Reversal swaps the GL leg and negates the subledger amounts, so
  /// the VAT summary nets out on cancel.
  static List<DerivedDoc> _taxLegs(
    Document doc,
    bool reversal, {
    required bool isOutput,
    required String partyType,
    String? party,
  }) {
    final id = doc.id;
    final p = doc.payload;
    final rows = doc.children['taxes'] ?? const [];
    final sfx = reversalSuffix(reversal);
    final out = <DerivedDoc>[];
    for (var i = 0; i < rows.length; i++) {
      final rp = rows[i].payload;
      final taxAmount = asNum(rp['tax_amount']);
      final taxable = asNum(rp['taxable_amount']);
      final account = asNonEmpty(rp['tax_account']);
      if (taxAmount != 0 && account != null) {
        // Output VAT is a credit (we owe the tax authority); input VAT is a
        // debit (recoverable). Reversal flips each.
        out.add(_gl(
          id: 'GL-$id-tax-$i$sfx',
          account: account,
          debit: isOutput ? (reversal ? taxAmount : 0) : (reversal ? 0 : taxAmount),
          credit: isOutput ? (reversal ? 0 : taxAmount) : (reversal ? taxAmount : 0),
          voucherType: doc.docType,
          voucherNo: id,
          postingDate: p['posting_date'],
          reversal: reversal,
        ));
      }
      out.add(DerivedDoc(taxTxn, 'TT-$id-$i$sfx', {
        'tax_type': asNonEmpty(rp['tax_type']) ?? 'VAT',
        if (asNonEmpty(rp['tax_code']) != null) 'tax': asNonEmpty(rp['tax_code']),
        'posting_date': p['posting_date'],
        'base_amount': negate(taxable, reversal),
        'tax_amount': negate(taxAmount, reversal),
        'rate': asNum(rp['rate']),
        'party_type': partyType,
        if (party != null) 'party': party,
        'voucher_type': doc.docType,
        'voucher_no': id,
        'is_reversal': reversal,
      }));
    }
    return out;
  }

  // ---- payment entry ------------------------------------------------------

  static List<DerivedDoc> _paymentEntry(Document doc, bool reversal) {
    final id = doc.id;
    final p = doc.payload;
    final paid = asNum(p['paid_amount']);
    final type = asNonEmpty(p['payment_type']);
    final party = asNonEmpty(p['party']);
    final sfx = reversalSuffix(reversal);
    final rows = <DerivedDoc>[
      // Cr the source account (money leaves)
      _gl(
        id: 'GL-$id-from$sfx',
        account: asNonEmpty(p['paid_from']),
        debit: reversal ? paid : 0,
        credit: reversal ? 0 : paid,
        voucherType: doc.docType,
        voucherNo: id,
        postingDate: p['posting_date'],
        reversal: reversal,
      ),
      // Dr the destination account (money arrives)
      _gl(
        id: 'GL-$id-to$sfx',
        account: asNonEmpty(p['paid_to']),
        debit: reversal ? 0 : paid,
        credit: reversal ? paid : 0,
        voucherType: doc.docType,
        voucherNo: id,
        postingDate: p['posting_date'],
        reversal: reversal,
      ),
    ];

    // Party subledger payment row (reduces what is owed; negative on submit).
    if (party != null && (type == 'Receive' || type == 'Pay')) {
      final amount = negate(paid, !reversal);
      final transType = reversal ? 'Adjustment' : 'Payment';
      if (type == 'Receive') {
        rows.add(DerivedDoc(customerTxn, 'CT-$id$sfx', {
          'trans_type': transType,
          'customer': party,
          'posting_date': p['posting_date'],
          'amount': amount,
          'currency': p['currency'],
          'voucher_type': doc.docType,
          'voucher_no': id,
          'is_reversal': reversal,
        }));
      } else {
        rows.add(DerivedDoc(supplierTxn, 'VT-$id$sfx', {
          'trans_type': transType,
          'supplier': party,
          'posting_date': p['posting_date'],
          'amount': amount,
          'currency': p['currency'],
          'voucher_type': doc.docType,
          'voucher_no': id,
          'is_reversal': reversal,
        }));
      }
    }

    // Settlements — one per allocation reference.
    final refs = doc.children['references'] ?? const [];
    final partyType = type == 'Receive' ? 'Customer' : 'Supplier';
    for (var i = 0; i < refs.length; i++) {
      final rp = refs[i].payload;
      final refDt = asNonEmpty(rp['reference_doctype']);
      final refNo = asNonEmpty(rp['reference_name']);
      if (refDt == null || refNo == null) continue;
      rows.add(DerivedDoc(settlement, 'STL-$id-$i$sfx', {
        'payment_voucher_type': doc.docType,
        'payment_voucher_no': id,
        'invoice_voucher_type': refDt,
        'invoice_voucher_no': refNo,
        'party_type': partyType,
        'party': party,
        'allocated_amount': negate(asNum(rp['allocated_amount']), reversal),
        'posting_date': p['posting_date'],
        'is_reversal': reversal,
      }));
    }
    return rows;
  }

  // ---- journal entry ------------------------------------------------------

  static List<DerivedDoc> _journalEntry(Document doc, bool reversal) {
    final id = doc.id;
    final p = doc.payload;
    final sfx = reversalSuffix(reversal);
    final rows = <DerivedDoc>[];
    final accounts = doc.children['accounts'] ?? const [];
    for (var i = 0; i < accounts.length; i++) {
      final rp = accounts[i].payload;
      final account = asNonEmpty(rp['account']);
      if (account == null) continue;
      final rawDebit = asNum(rp['debit']);
      final rawCredit = asNum(rp['credit']);
      final debit = reversal ? rawCredit : rawDebit;
      final credit = reversal ? rawDebit : rawCredit;
      rows.add(_gl(
        id: 'GL-$id-$i$sfx',
        account: account,
        debit: debit,
        credit: credit,
        partyType: asNonEmpty(rp['party_type']),
        party: asNonEmpty(rp['party']),
        costCenter: asNonEmpty(rp['cost_center']),
        voucherType: doc.docType,
        voucherNo: id,
        postingDate: p['posting_date'],
        reversal: reversal,
      ));

      final pt = asNonEmpty(rp['party_type']);
      final party = asNonEmpty(rp['party']);
      if (party == null) continue;
      final net = debit - credit; // Dr increases debt, Cr decreases.
      if (pt == 'Customer') {
        rows.add(_partyAdjustment(customerTxn, 'CT-$id-$i$sfx',
            partyKey: 'customer', party: party, amount: net, doc: doc, reversal: reversal));
      } else if (pt == 'Supplier') {
        // Supplier convention is flipped: a credit to the payable = we owe more.
        rows.add(_partyAdjustment(supplierTxn, 'VT-$id-$i$sfx',
            partyKey: 'supplier', party: party, amount: -net, doc: doc, reversal: reversal));
      }
    }
    return rows;
  }

  // ---- stock movements ----------------------------------------------------

  static List<DerivedDoc> _stockEntry(Document doc, bool reversal) {
    final id = doc.id;
    final p = doc.payload;
    final transType = _stockEntryTransType(asNonEmpty(p['stock_entry_type']));
    final sfx = reversalSuffix(reversal);
    final rows = <DerivedDoc>[];
    final items = doc.children['items'] ?? const [];
    for (var i = 0; i < items.length; i++) {
      final rp = items[i].payload;
      final item = asNonEmpty(rp['item']);
      if (item == null) continue;
      final qty = asNum(rp['qty']);
      final source = asNonEmpty(rp['source_warehouse']);
      final target = asNonEmpty(rp['target_warehouse']);
      if (source != null) {
        rows.add(_sle(
          id: 'SLE-$id-$i-out$sfx',
          transType: transType,
          item: item,
          warehouse: source,
          qtyChange: negate(qty, !reversal), // leaves source on submit
          valuationRate: rp['valuation_rate'],
          uom: asNonEmpty(rp['uom']),
          doc: doc,
          reversal: reversal,
        ));
      }
      if (target != null) {
        rows.add(_sle(
          id: 'SLE-$id-$i-in$sfx',
          transType: transType,
          item: item,
          warehouse: target,
          qtyChange: negate(qty, reversal), // enters target on submit
          valuationRate: rp['valuation_rate'],
          uom: asNonEmpty(rp['uom']),
          doc: doc,
          reversal: reversal,
        ));
      }
    }
    return rows;
  }

  static List<DerivedDoc> _stockDocument(
    Document doc,
    bool reversal, {
    required bool incoming,
    required String transType,
  }) {
    final id = doc.id;
    final p = doc.payload;
    final setWarehouse = asNonEmpty(p['set_warehouse']);
    final sfx = reversalSuffix(reversal);
    final rows = <DerivedDoc>[];
    final items = doc.children['items'] ?? const [];
    for (var i = 0; i < items.length; i++) {
      final rp = items[i].payload;
      final item = asNonEmpty(rp['item']);
      final warehouse = asNonEmpty(rp['warehouse']) ?? setWarehouse;
      if (item == null || warehouse == null) continue;
      final qty = asNum(rp['qty']);
      // Receipt: +qty on submit. Delivery: -qty on submit. Flipped on reversal.
      final qtyChange = negate(qty, incoming ? reversal : !reversal);
      rows.add(_sle(
        id: 'SLE-$id-$i$sfx',
        transType: transType,
        item: item,
        warehouse: warehouse,
        qtyChange: qtyChange,
        valuationRate: rp['valuation_rate'] ?? rp['rate'],
        uom: asNonEmpty(rp['uom']),
        doc: doc,
        reversal: reversal,
      ));
    }
    return rows;
  }

  static String _stockEntryTransType(String? purpose) {
    switch (purpose) {
      case 'Material Receipt':
        return 'Receipt';
      case 'Material Transfer':
        return 'Transfer';
      case 'Repack':
        return 'Adjustment';
      case 'Manufacture':
      case 'Manufacturing':
        return 'Production';
      case 'Material Issue':
      default:
        return 'Issue';
    }
  }

  // ---- multi-currency (base-amount stamping) -----------------------------

  /// The document's exchange rate to the company/base currency
  /// (`conversion_rate`), defaulting to 1.0 when absent or non-positive — so a
  /// same-currency voucher posts base == transaction. Port of Swift's guard.
  static num conversionRate(Document doc) {
    final rate = asNum(doc.payload['conversion_rate']);
    return rate > 0 ? rate : 1;
  }

  /// Stamps base-currency amounts onto a base-stamped voucher's
  /// transaction-currency rows: GL entries get `conversion_rate` +
  /// `base_debit`/`base_credit` + `currency`; customer / supplier subledger
  /// rows get `conversion_rate` + `base_amount`. At rate 1.0 the base equals the
  /// transaction amount, so single-currency postings keep the same numbers.
  /// Tax / settlement / stock rows are deliberately left in transaction
  /// currency (matching the Swift coordinator).
  ///
  /// Base amounts are kept at full precision (NOT rounded per leg): the
  /// transaction ledger balances, so `Σ debitᵢ·rate == Σ creditⱼ·rate`, but
  /// rounding each leg independently can break that equality when a side is
  /// split across several legs at a fractional rate (e.g. one 0.06 debit vs
  /// three 0.02 credits at 3.333 → 0.20 vs 0.21). Leaving the products
  /// unrounded keeps the base ledger balanced, mirroring the Swift coordinator
  /// (which posts raw `Double` base amounts and relies on a balance tolerance).
  static void _stampBaseAmounts(List<DerivedDoc> rows, Document doc) {
    final rate = conversionRate(doc);
    final currency = asNonEmpty(doc.payload['currency']);
    for (final row in rows) {
      if (row.docType == glEntry) {
        row.payload['conversion_rate'] = rate;
        row.payload['base_debit'] = asNum(row.payload['debit']) * rate;
        row.payload['base_credit'] = asNum(row.payload['credit']) * rate;
        if (currency != null) row.payload['currency'] = currency;
      } else if (row.docType == customerTxn || row.docType == supplierTxn) {
        row.payload['conversion_rate'] = rate;
        row.payload['base_amount'] = asNum(row.payload['amount']) * rate;
        if (currency != null && asNonEmpty(row.payload['currency']) == null) {
          row.payload['currency'] = currency;
        }
      }
    }
  }

  // ---- builders -----------------------------------------------------------

  static DerivedDoc _gl({
    required String id,
    required String? account,
    required num debit,
    required num credit,
    String? partyType,
    String? party,
    String? costCenter,
    required String voucherType,
    required String voucherNo,
    required dynamic postingDate,
    required bool reversal,
  }) {
    return DerivedDoc(glEntry, id, {
      'posting_date': postingDate,
      'account': account,
      'debit': debit,
      'credit': credit,
      if (partyType != null) 'party_type': partyType,
      if (party != null) 'party': party,
      if (costCenter != null) 'cost_center': costCenter,
      'voucher_type': voucherType,
      'voucher_no': voucherNo,
      'is_reversal': reversal,
    });
  }

  static DerivedDoc _sle({
    required String id,
    required String transType,
    required String item,
    required String warehouse,
    required num qtyChange,
    required dynamic valuationRate,
    required Document doc,
    required bool reversal,
    String? uom,
  }) {
    return DerivedDoc(stockLedger, id, {
      'trans_type': transType,
      'item': item,
      'warehouse': warehouse,
      'posting_date': doc.payload['posting_date'],
      'voucher_type': doc.docType,
      'voucher_no': doc.id,
      'qty_change': qtyChange,
      if (valuationRate != null) 'valuation_rate': asNum(valuationRate),
      // Transaction UOM, so the runtime can convert qty/rate to the stock UOM
      // (value-preserving) before the row hits the Bin. Absent ⇒ stock UOM.
      if (uom != null) 'uom': uom,
      'is_reversal': reversal,
    });
  }

  static DerivedDoc _partyAdjustment(
    String docType,
    String id, {
    required String partyKey,
    required String party,
    required num amount,
    required Document doc,
    required bool reversal,
  }) {
    return DerivedDoc(docType, id, {
      'trans_type': 'Adjustment',
      partyKey: party,
      'posting_date': doc.payload['posting_date'],
      'amount': amount,
      'voucher_type': doc.docType,
      'voucher_no': doc.id,
      'is_reversal': reversal,
    });
  }
}
