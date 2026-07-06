import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

import 'hub_tax_engine.dart';
import 'ledger_derivation.dart';
import 'ledger_values.dart';

/// Riverpod override that registers the Hub's document lifecycle hooks. Added to
/// the app's [ProviderScope] so [documentEngineProvider] picks them up.
///
/// Order note: [LineItemTotalsInterceptor] sets `total`; on a tax-bearing doc it
/// leaves `grand_total` to [TaxCalculationInterceptor], which derives its own
/// net base from the lines — so the two are order-independent.
final hubInterceptorsOverride =
    documentInterceptorsProvider.overrideWithValue(const [
  BusinessProfileDefaultsInterceptor(),
  ItemNameDefaultInterceptor(),
  LineItemTotalsInterceptor(),
  TaxCalculationInterceptor(),
  BomRollupInterceptor(),
  FiscalYearGuardInterceptor(),
  BooksLockGuardInterceptor(),
  NegativeStockGuardInterceptor(),
  GroupAccountPostingGuardInterceptor(),
  JournalBalanceGuardInterceptor(),
  DuplicateSupplierBillGuardInterceptor(),
]);

const _systemRoles = {'System Manager'};

/// Keeps an [Item] named: when `item_name` is left blank it defaults to
/// `item_code` on save. `item_name` is optional (parity with the Swift app,
/// which falls back to the code for display), so a code-only entry saves — this
/// runs before validation so the stored name is always populated.
class ItemNameDefaultInterceptor extends DocumentInterceptor {
  const ItemNameDefaultInterceptor();

  @override
  Future<void> beforeSave(
      DocumentEngine engine, Document doc, DocType docType,
      {required bool isNew}) async {
    if (docType.id != 'Item') return;
    if (asNonEmpty(doc.payload['item_name']) != null) return;
    final code = asNonEmpty(doc.payload['item_code']);
    if (code != null) doc.payload['item_name'] = code;
  }
}

/// The line-item child table key shared by selling/buying transaction docs.
const _itemsTable = 'items';

/// Authoritatively computes line-item and document totals on save, so every
/// save path (UI, import, programmatic) posts correct amounts — the ledger
/// derives GL/stock from `grand_total` and the line rows. For each `items` row
/// it sets `amount = qty * rate`, then `total` = Σ amount. `grand_total` is set
/// to `total` here EXCEPT on docs that carry a `taxes` table (invoices), where
/// [TaxCalculationInterceptor] owns `grand_total = total + tax`. Docs without an
/// `items` table are left untouched.
class LineItemTotalsInterceptor extends DocumentInterceptor {
  const LineItemTotalsInterceptor();

  @override
  Future<void> beforeSave(
      DocumentEngine engine, Document doc, DocType docType,
      {required bool isNew}) async {
    final rows = doc.children[_itemsTable];
    if (rows == null) return; // not a line-item document

    num total = 0;
    for (final row in rows) {
      final amount = asNum(row.payload['qty']) * asNum(row.payload['rate']);
      row.payload['amount'] = amount;
      total += amount;
    }

    final keys = {for (final f in docType.fields) f.key};
    if (keys.contains('total')) doc.payload['total'] = total;
    // A tax-bearing doc's grand total is net + tax; the tax interceptor sets it.
    if (keys.contains('grand_total') && !keys.contains(_taxesTable)) {
      doc.payload['grand_total'] = total;
    }
  }
}

/// The tax child table key carried by tax-aware transaction docs (invoices).
const _taxesTable = 'taxes';

/// Computes VAT on save for any document that carries a `taxes` table (Sales
/// Invoice, Purchase Invoice). Ported from the Swift `HubTaxCalculationPolicy`:
/// for each line it resolves the effective tax code through the
/// line → item → document → party fallback chain, runs [HubTaxEngine], then
/// writes `total` (net), `tax_total`, `grand_total = net + tax`, and the `taxes`
/// child rows. Those rows become GL legs + `Tax Transaction` ledger rows on
/// submit (see [LedgerDerivation]). Zero-rated codes still emit a row (taxable
/// base captured for the VAT return); lines with no code are net-only.
class TaxCalculationInterceptor extends DocumentInterceptor {
  const TaxCalculationInterceptor();

  @override
  Future<void> beforeSave(
      DocumentEngine engine, Document doc, DocType docType,
      {required bool isNew}) async {
    final keys = {for (final f in docType.fields) f.key};
    if (!keys.contains(_taxesTable)) return; // not a tax-bearing document
    final rows = doc.children[_itemsTable];
    if (rows == null) return;

    // Default VAT account fallback from the active Company (business profile).
    final company = await _activeCompany(engine, doc.company);
    final defaultTaxAccount =
        company == null ? null : asNonEmpty(company.payload['default_vat_account']);

    // Tax Code master → rate info, applying the default-account fallback.
    final codeRecords = await engine.list('Tax Code', userRoles: _systemRoles);
    final rateByCode = <String, TaxRateInfo>{};
    for (final rec in codeRecords) {
      if (!_isEnabled(rec.payload['enabled'])) continue;
      rateByCode[rec.id] = _rateInfo(rec, defaultTaxAccount);
    }

    final documentTaxCode = asNonEmpty(doc.payload['tax_code']);
    final partyCode = await _partyTaxCode(engine, doc, docType);

    // Item-master tax-code lookup, cached across lines.
    final itemCache = <String, String?>{};
    Future<String?> itemTaxCode(String itemId) async {
      if (itemCache.containsKey(itemId)) return itemCache[itemId];
      final item = await engine.fetch('Item', itemId);
      final code = item == null ? null : asNonEmpty(item.payload['tax_code']);
      itemCache[itemId] = code;
      return code;
    }

    final lines = <TaxLine>[];
    for (final row in rows) {
      final net = asNum(row.payload['qty']) * asNum(row.payload['rate']);
      final lineCode = asNonEmpty(row.payload['tax_code']);
      final itemId = asNonEmpty(row.payload['item']);
      final itemCode =
          lineCode == null && itemId != null ? await itemTaxCode(itemId) : null;
      final effective = lineCode ?? itemCode ?? documentTaxCode ?? partyCode;
      lines.add(TaxLine(net, effective));
    }

    final comp = HubTaxEngine.compute(lines, rateByCode);

    if (keys.contains('total')) doc.payload['total'] = comp.netTotal;
    if (keys.contains('tax_total')) doc.payload['tax_total'] = comp.totalTax;
    if (keys.contains('grand_total')) doc.payload['grand_total'] = comp.grandTotal;
    doc.children[_taxesTable] = _taxChildRows(doc, comp.taxRows);
  }

  List<ChildRow> _taxChildRows(Document doc, List<ComputedTaxRow> rows) => [
        for (var i = 0; i < rows.length; i++)
          ChildRow(
            id: '',
            parentId: doc.id,
            parentDocType: doc.docType,
            tableName: _taxesTable,
            rowIndex: i,
            payload: {
              'tax_code': rows[i].taxCode,
              'tax_type': rows[i].taxType,
              'description': rows[i].description,
              'rate': rows[i].rate,
              if (rows[i].account != null) 'tax_account': rows[i].account,
              'taxable_amount': rows[i].taxableAmount,
              'tax_amount': rows[i].taxAmount,
            },
          ),
      ];

  TaxRateInfo _rateInfo(Document rec, String? defaultTaxAccount) {
    final name = asNonEmpty(rec.payload['tax_code_name']) ?? rec.id;
    final rate = asNum(rec.payload['rate']);
    final account = asNonEmpty(rec.payload['tax_account']) ?? defaultTaxAccount;
    final taxType = asNonEmpty(rec.payload['tax_type']) ?? 'VAT';
    final pct = rate == rate.roundToDouble()
        ? '${rate.toStringAsFixed(0)}%'
        : '${rate.toStringAsFixed(2)}%';
    return TaxRateInfo(
      codeId: rec.id,
      description: '$name ($pct)',
      rate: rate,
      account: account,
      taxType: taxType,
    );
  }

  /// Lowest-priority fallback: the party's default tax code (Customer for sales,
  /// Supplier for purchases).
  Future<String?> _partyTaxCode(
      DocumentEngine engine, Document doc, DocType docType) async {
    final fields = {for (final f in docType.fields) f.key};
    if (fields.contains('customer')) {
      final id = asNonEmpty(doc.payload['customer']);
      if (id == null) return null;
      final c = await engine.fetch('Customer', id);
      return c == null ? null : asNonEmpty(c.payload['tax_code']);
    }
    if (fields.contains('supplier')) {
      final id = asNonEmpty(doc.payload['supplier']);
      if (id == null) return null;
      final s = await engine.fetch('Supplier', id);
      return s == null ? null : asNonEmpty(s.payload['tax_code']);
    }
    return null;
  }

  Future<Document?> _activeCompany(DocumentEngine engine, String? id) async {
    if (id != null && id.isNotEmpty) return engine.fetch('Company', id);
    final all = await engine.list('Company', userRoles: _systemRoles);
    return all.isEmpty ? null : all.first;
  }

  /// A boolean-ish payload value (bool, or '1'/'true'); defaults to enabled when
  /// the field is absent, matching the Swift policy.
  bool _isEnabled(dynamic v) {
    if (v == null) return true;
    if (v is bool) return v;
    if (v is num) return v != 0;
    if (v is String) return v == '1' || v.toLowerCase() == 'true';
    return true;
  }
}

/// Rolls up BOM costs on save: each item row's `amount = qty * rate`, each
/// operation row's `cost = (time_minutes / 60) * hour_rate`, then the parent
/// `raw_material_cost` (Σ amount), `operating_cost` (Σ cost) and `total_cost`.
/// Only touches docs that carry a `raw_material_cost` field (the BOM).
class BomRollupInterceptor extends DocumentInterceptor {
  const BomRollupInterceptor();

  @override
  Future<void> beforeSave(
      DocumentEngine engine, Document doc, DocType docType,
      {required bool isNew}) async {
    final keys = {for (final f in docType.fields) f.key};
    if (!keys.contains('raw_material_cost')) return; // not a BOM

    num raw = 0;
    for (final r in doc.children['items'] ?? const []) {
      final amount = asNum(r.payload['qty']) * asNum(r.payload['rate']);
      r.payload['amount'] = amount;
      raw += amount;
    }
    num op = 0;
    for (final r in doc.children['operations'] ?? const []) {
      final cost = (asNum(r.payload['time_minutes']) / 60) * asNum(r.payload['hour_rate']);
      r.payload['cost'] = cost;
      op += cost;
    }
    doc.payload['raw_material_cost'] = raw;
    doc.payload['operating_cost'] = op;
    doc.payload['total_cost'] = raw + op;
  }
}

/// Pre-fills a new draft from the active Company ("business profile"): stamps
/// the company, default currency, default posting accounts (so they're visible
/// in the form, not just resolved at posting time), today's date (posting or
/// transaction), and a default quotation validity.
/// Only ever fills blanks — anything the user already entered wins.
class BusinessProfileDefaultsInterceptor extends DocumentInterceptor {
  const BusinessProfileDefaultsInterceptor();

  @override
  Future<void> beforeSave(
      DocumentEngine engine, Document doc, DocType docType,
      {required bool isNew}) async {
    if (!isNew) return;
    final fieldKeys = {for (final f in docType.fields) f.key};

    // Posting date → today (company-independent).
    if (fieldKeys.contains('posting_date') &&
        asNonEmpty(doc.payload['posting_date']) == null) {
      doc.payload['posting_date'] = _todayIso();
    }
    // Transaction date → today. Selling/buying documents (Quotation, Sales
    // Order, Purchase Order, …) date themselves with `transaction_date` rather
    // than `posting_date`; without this a new draft opened with a blank Date.
    if (fieldKeys.contains('transaction_date') &&
        asNonEmpty(doc.payload['transaction_date']) == null) {
      doc.payload['transaction_date'] = _todayIso();
    }
    // Quotation validity → 30 days out, so a fresh quote isn't born expired.
    // Only fills a blank; the user can shorten or extend it.
    if (fieldKeys.contains('valid_till') &&
        asNonEmpty(doc.payload['valid_till']) == null) {
      doc.payload['valid_till'] = _todayPlusIso(30);
    }

    final accounts = LedgerDerivation.accountFallbacks(
      doc.docType,
      paymentType: doc.payload['payment_type'],
    );
    final missingAccounts = {
      for (final e in accounts.entries)
        if (asNonEmpty(doc.payload[e.key]) == null) e.key: e.value,
    };
    final needsCurrency =
        fieldKeys.contains('currency') && asNonEmpty(doc.payload['currency']) == null;
    final needsCompany = asNonEmpty(doc.company) == null;
    if (!needsCurrency && !needsCompany && missingAccounts.isEmpty) return;

    final company = await _activeCompany(engine, doc.company);
    if (company == null) return;

    if (needsCompany) doc.company = company.id;
    if (needsCurrency) {
      final currency = asNonEmpty(company.payload['default_currency']);
      if (currency != null) doc.payload['currency'] = currency;
    }
    for (final e in missingAccounts.entries) {
      final value = asNonEmpty(company.payload[e.value]);
      if (value != null) doc.payload[e.key] = value;
    }
  }

  /// The Company named on the document, or the first one defined otherwise.
  Future<Document?> _activeCompany(DocumentEngine engine, String? id) async {
    if (id != null && id.isNotEmpty) return engine.fetch('Company', id);
    final all = await engine.list('Company', userRoles: _systemRoles);
    return all.isEmpty ? null : all.first;
  }

  String _todayIso() => DateTime.now().toIso8601String().split('T').first;

  String _todayPlusIso(int days) => DateTime.now()
      .add(Duration(days: days))
      .toIso8601String()
      .split('T')
      .first;
}

/// Blocks submitting a posting document whose `posting_date` falls outside every
/// defined Fiscal Year. If no Fiscal Years exist yet (fresh install) it stays
/// out of the way so the books can be bootstrapped.
class FiscalYearGuardInterceptor extends DocumentInterceptor {
  const FiscalYearGuardInterceptor();

  @override
  Future<void> beforeSubmit(
      DocumentEngine engine, Document doc, DocType docType) async {
    final posting = _asDate(doc.payload['posting_date']);
    if (posting == null) return; // not a dated posting document

    final years = await engine.list('Fiscal Year', userRoles: _systemRoles);
    if (years.isEmpty) return; // nothing configured — don't block bootstrapping

    for (final year in years) {
      final start = _asDate(year.payload['year_start_date']);
      final end = _asDate(year.payload['year_end_date']);
      if (start == null || end == null) continue;
      if (!posting.isBefore(start) && !posting.isAfter(end)) return; // in range
    }

    final d = posting;
    final iso =
        '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    throw DocumentEngineError.validationFailed([
      ValidationError(
        stage: 'fiscal_year',
        fieldKey: 'posting_date',
        message:
            'Posting date $iso is not within any defined Fiscal Year. Create '
            'or extend a Fiscal Year before submitting.',
      ),
    ]);
  }
}

/// Parses a stored date value (ISO string, epoch millis, or DateTime), reduced
/// to date precision so time-of-day never skews a fiscal-year boundary check.
DateTime? _asDate(dynamic v) {
  DateTime? d;
  if (v is DateTime) {
    d = v;
  } else if (v is int) {
    d = DateTime.fromMillisecondsSinceEpoch(v);
  } else if (v is String && v.isNotEmpty) {
    d = DateTime.tryParse(v);
  }
  return d == null ? null : DateTime(d.year, d.month, d.day);
}

/// Blocks submitting a posting document dated on or before the company's
/// `books_lock_date` (period close). Dormant when no lock date is set. Mirrors
/// the Swift `BooksLockPolicy` (start-of-day comparison, posting ≤ lock → blocked).
class BooksLockGuardInterceptor extends DocumentInterceptor {
  const BooksLockGuardInterceptor();

  @override
  Future<void> beforeSubmit(
      DocumentEngine engine, Document doc, DocType docType) async {
    final posting =
        _asDate(doc.payload['posting_date'] ?? doc.payload['transaction_date']);
    if (posting == null) return; // not a dated posting document
    final company = await _companyFor(engine, doc.company);
    final lock = _asDate(company?.payload['books_lock_date']);
    if (lock == null) return; // no period close configured
    if (!posting.isAfter(lock)) {
      throw DocumentEngineError.validationFailed([
        ValidationError(
          stage: 'books_lock',
          fieldKey: 'posting_date',
          message:
              'The books are locked through ${_isoDate(lock)}. That period has '
              'been finalised — change the lock date in the Business Profile '
              'before posting into it.',
        ),
      ]);
    }
  }
}

/// Rejects a stock issue (Delivery Note / POS Invoice / Stock Entry source leg)
/// that would drive a bin's on-hand quantity negative, unless the company has
/// `allow_negative_stock` set. Line quantities are converted to the item's
/// stock UOM first. Mirrors the Swift negative-stock guard.
class NegativeStockGuardInterceptor extends DocumentInterceptor {
  const NegativeStockGuardInterceptor();

  static const _issueDocTypes = {'Delivery Note', 'POS Invoice', 'Stock Entry'};

  @override
  Future<void> beforeSubmit(
      DocumentEngine engine, Document doc, DocType docType) async {
    // A Sales Invoice only issues stock when update_stock is set (Phase 1B).
    final issues = _issueDocTypes.contains(doc.docType) ||
        (doc.docType == 'Sales Invoice' && isTrue(doc.payload['update_stock']));
    if (!issues) return;
    if (isTrue(doc.payload['is_return'])) return; // a return adds stock back
    final company = await _companyFor(engine, doc.company);
    if (isTrue(company?.payload['allow_negative_stock'])) return;

    final isStockEntry = doc.docType == 'Stock Entry';
    final setWarehouse = asNonEmpty(doc.payload['set_warehouse']);
    // Aggregate the requested (stock-UOM) qty per (item, warehouse).
    final requested = <String, ({String item, String warehouse, num qty})>{};
    for (final row in doc.children['items'] ?? const <ChildRow>[]) {
      final rp = row.payload;
      final item = asNonEmpty(rp['item']);
      if (item == null) continue;
      final warehouse = isStockEntry
          ? asNonEmpty(rp['source_warehouse']) // only the outgoing leg issues
          : (asNonEmpty(rp['warehouse']) ?? setWarehouse);
      if (warehouse == null) continue;
      // Service / non-stock items don't consume inventory — skip them so a
      // delivery/POS line for a service isn't rejected for having no Bin.
      final itemDoc = await engine.fetch('Item', item);
      if (itemDoc != null && !isStockItem(itemDoc.payload)) continue;
      final qty = asNum(rp['qty']) * uomFactor(itemDoc, asNonEmpty(rp['uom']));
      if (qty <= 0) continue;
      final key = '$item $warehouse';
      final prior = requested[key];
      requested[key] = (
        item: item,
        warehouse: warehouse,
        qty: (prior?.qty ?? 0) + qty,
      );
    }

    for (final req in requested.values) {
      final bin = await engine.fetch('Bin', 'BIN-${req.item}-${req.warehouse}');
      final onHand = bin == null ? 0 : asNum(bin.payload['actual_qty']);
      if (req.qty > onHand + 0.0000001) {
        throw DocumentEngineError.validationFailed([
          ValidationError(
            stage: 'negative_stock',
            fieldKey: 'items',
            message:
                'Not enough stock of ${req.item} in ${req.warehouse}: '
                '${req.qty} requested but $onHand on hand. Receive stock first, '
                'or enable Allow Negative Stock in the Business Profile.',
          ),
        ]);
      }
    }
  }
}

/// Rejects submitting a voucher that would post a GL leg to a group (non-leaf)
/// account. Group accounts are the branches of the chart — they summarise their
/// children and must never carry transactions. Reuses the same
/// [LedgerDerivation] the engine posts with, so it catches every posting path
/// (journal entries, invoices with an overridden account, …) in one place.
class GroupAccountPostingGuardInterceptor extends DocumentInterceptor {
  const GroupAccountPostingGuardInterceptor();

  @override
  Future<void> beforeSubmit(
      DocumentEngine engine, Document doc, DocType docType) async {
    final legs = LedgerDerivation.derive(doc, reversal: false);
    final accountIds = <String>{};
    for (final leg in legs) {
      if (leg.docType != 'GL Entry') continue;
      final id = asNonEmpty(leg.payload['account']);
      if (id != null) accountIds.add(id);
    }
    if (accountIds.isEmpty) return;

    final groups = <String>[];
    for (final id in accountIds) {
      final acct = await engine.fetch('Account', id);
      if (acct != null && isTrue(acct.payload['is_group'])) groups.add(id);
    }
    if (groups.isEmpty) return;

    throw DocumentEngineError.validationFailed([
      ValidationError(
        stage: 'group_account_posting',
        fieldKey: 'account',
        message: 'Cannot post to group account'
            '${groups.length > 1 ? 's' : ''} ${groups.join(', ')}. Group '
            'accounts summarise their children — choose a leaf (posting) '
            'account instead.',
      ),
    ]);
  }
}

/// Keeps a Journal Entry's `total_debit` / `total_credit` / `difference`
/// display fields honest on every save, and blocks submitting an entry whose
/// debits and credits do not balance (cent tolerance). Invoices and payments
/// are balanced by construction in [LedgerDerivation]; a hand-entered journal
/// was the one posting path that could write an unbalanced GL.
class JournalBalanceGuardInterceptor extends DocumentInterceptor {
  const JournalBalanceGuardInterceptor();

  static const _tolerance = 0.005; // half a cent — same as invoice settlement

  @override
  Future<void> beforeSave(
      DocumentEngine engine, Document doc, DocType docType,
      {required bool isNew}) async {
    if (docType.id != 'Journal Entry') return;
    final (debit, credit) = _totals(doc);
    doc.payload['total_debit'] = debit;
    doc.payload['total_credit'] = credit;
    doc.payload['difference'] = debit - credit;
  }

  @override
  Future<void> beforeSubmit(
      DocumentEngine engine, Document doc, DocType docType) async {
    if (docType.id != 'Journal Entry') return;
    final (debit, credit) = _totals(doc);
    if ((debit - credit).abs() < _tolerance) return;
    throw DocumentEngineError.validationFailed([
      ValidationError(
        stage: 'journal_balance',
        fieldKey: 'accounts',
        message: 'Journal Entry does not balance: total debit $debit ≠ total '
            'credit $credit. Debits and credits must be equal before the '
            'entry can be submitted.',
      ),
    ]);
  }

  (num, num) _totals(Document doc) {
    num debit = 0;
    num credit = 0;
    for (final row in doc.children['accounts'] ?? const []) {
      debit += asNum(row.payload['debit']);
      credit += asNum(row.payload['credit']);
    }
    return (debit, credit);
  }
}

/// Warns about double-entering (and so double-paying) a supplier bill: saving
/// a Purchase Invoice whose supplier + supplier's-invoice-number pair already
/// exists on another live document is rejected. Blank numbers are never
/// checked (micro-businesses won't always have one), cancelled documents
/// don't count, and re-saving the same draft passes.
class DuplicateSupplierBillGuardInterceptor extends DocumentInterceptor {
  const DuplicateSupplierBillGuardInterceptor();

  @override
  Future<void> beforeSave(
      DocumentEngine engine, Document doc, DocType docType,
      {required bool isNew}) async {
    if (docType.id != 'Purchase Invoice') return;
    final supplier = asNonEmpty(doc.payload['supplier']);
    final number = asNonEmpty(doc.payload['supplier_invoice_no']);
    if (supplier == null || number == null) return;

    final others = await engine.list('Purchase Invoice',
        filters: {'supplier': supplier}, userRoles: _systemRoles);
    final normalized = number.trim().toLowerCase();
    for (final other in others) {
      if (other.id == doc.id) continue; // re-saving the same document
      if (other.docStatus == 2) continue; // cancelled bills don't count
      final otherNo = asNonEmpty(other.payload['supplier_invoice_no']);
      if (otherNo != null && otherNo.trim().toLowerCase() == normalized) {
        throw DocumentEngineError.validationFailed([
          ValidationError(
            stage: 'duplicate_supplier_bill',
            fieldKey: 'supplier_invoice_no',
            message: "Supplier invoice '$number' from $supplier already "
                'exists (${other.id}). Entering it again would risk paying '
                'the bill twice — open the existing document instead, or '
                'change the number if this is genuinely a different bill.',
          ),
        ]);
      }
    }
  }
}

// ---- shared guard helpers ------------------------------------------------

/// The active Company for [id] (or the first one when no id is given) — the
/// "business profile" the guards read their policy flags from.
Future<Document?> _companyFor(DocumentEngine engine, String? id) async {
  if (id != null && id.isNotEmpty) return engine.fetch('Company', id);
  final all = await engine.list('Company', userRoles: _systemRoles);
  return all.isEmpty ? null : all.first;
}


String _isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
