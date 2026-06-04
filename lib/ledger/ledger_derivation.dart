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
/// Deliberately NOT yet handled (Phase 3 follow-ups, flagged in PARITY.md):
///  * tax legs (no taxes child table until the Tax module lands) — invoices
///    therefore post a 2-leg GL (Dr/Cr grand_total), which still balances;
///  * mutating a submitted invoice's `outstanding_amount` (the core engine
///    forbids writes to docStatus==1 docs) — outstanding is derivable from the
///    customer/supplier subledger instead;
///  * POSInvoice (POS module not ported).
abstract final class LedgerDerivation {
  // Derived DocType ids (match the Phase 2 manifest).
  static const glEntry = 'GL Entry';
  static const customerTxn = 'Customer Transaction';
  static const supplierTxn = 'Supplier Transaction';
  static const settlement = 'Settlement';
  static const stockLedger = 'Stock Ledger Entry';
  static const bin = 'Bin';

  /// Source DocTypes that move stock and therefore require a Bin recompute.
  static const stockSources = {'Stock Entry', 'Purchase Receipt', 'Delivery Note'};

  /// Returns the ledger rows for [doc]. `reversal` is false on submit, true on
  /// cancel. Unknown DocTypes yield an empty list (no-op, prevents re-entrancy).
  static List<DerivedDoc> derive(Document doc, {required bool reversal}) {
    switch (doc.docType) {
      case 'Sales Invoice':
        return _salesInvoice(doc, reversal);
      case 'Purchase Invoice':
        return _purchaseInvoice(doc, reversal);
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
    final customer = asNonEmpty(p['customer']);
    final sfx = reversalSuffix(reversal);
    return [
      // Dr Accounts Receivable
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
      // Cr Income (net == grand until tax legs exist)
      _gl(
        id: 'GL-$id-credit$sfx',
        account: asNonEmpty(p['income_account']),
        debit: reversal ? grand : 0,
        credit: reversal ? 0 : grand,
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
    ];
  }

  static List<DerivedDoc> _purchaseInvoice(Document doc, bool reversal) {
    final id = doc.id;
    final p = doc.payload;
    final grand = asNum(p['grand_total']);
    final supplier = asNonEmpty(p['supplier']);
    final sfx = reversalSuffix(reversal);
    return [
      // Cr Accounts Payable
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
      // Dr Expense
      _gl(
        id: 'GL-$id-debit$sfx',
        account: asNonEmpty(p['expense_account']),
        debit: reversal ? 0 : grand,
        credit: reversal ? grand : 0,
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
    ];
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
