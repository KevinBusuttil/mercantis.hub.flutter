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
  LineItemTotalsInterceptor(),
  TaxCalculationInterceptor(),
  FiscalYearGuardInterceptor(),
]);

const _systemRoles = {'System Manager'};

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

/// Pre-fills a new draft from the active Company ("business profile"): stamps
/// the company, default currency, default posting accounts (so they're visible
/// in the form, not just resolved at posting time), and today's posting date.
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
