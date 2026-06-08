import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

import 'ledger_derivation.dart';
import 'ledger_values.dart';

/// Riverpod override that registers the Hub's document lifecycle hooks. Added to
/// the app's [ProviderScope] so [documentEngineProvider] picks them up.
final hubInterceptorsOverride =
    documentInterceptorsProvider.overrideWithValue(const [
  BusinessProfileDefaultsInterceptor(),
  LineItemTotalsInterceptor(),
  FiscalYearGuardInterceptor(),
]);

const _systemRoles = {'System Manager'};

/// The line-item child table key shared by selling/buying transaction docs.
const _itemsTable = 'items';

/// Authoritatively computes line-item and document totals on save, so every
/// save path (UI, import, programmatic) posts correct amounts — the ledger
/// derives GL/stock from `grand_total` and the line rows. For each `items` row
/// it sets `amount = qty * rate`, then `total` = Σ amount and `grand_total` =
/// `total` (until the Tax module adds tax legs). Docs without an `items` table
/// are left untouched.
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
    if (keys.contains('grand_total')) doc.payload['grand_total'] = total;
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
