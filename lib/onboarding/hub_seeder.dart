import 'package:mercantis_core/mercantis_core.dart';

/// One ledger account in the starter chart of accounts. [id] doubles as the
/// deterministic record id the Company defaults point at.
class SeedAccount {
  const SeedAccount(this.id, this.name, this.rootType, this.accountType);
  final String id;
  final String name;
  final String rootType; // Asset / Liability / Income / Expense / Equity
  final String accountType; // Cash / Bank / Receivable / Payable / Tax / …
}

/// One VAT band seeded so the tax engine works out of the box.
class SeedTaxCode {
  const SeedTaxCode(this.id, this.rate, {this.isDefault = false});
  final String id;
  final num rate;
  final bool isDefault;
}

/// The starter master data the onboarding seeder lays down (ported from the
/// Swift `HubOnboardingSeeder`, extended with VAT bands). Kept as pure data so
/// it can be asserted without a database.
abstract final class HubChart {
  /// Flat starter chart of accounts. The Company default-account fields wire to
  /// these ids (see [companyDefaults]).
  static const accounts = <SeedAccount>[
    SeedAccount('Cash', 'Cash', 'Asset', 'Cash'),
    SeedAccount('Bank', 'Bank', 'Asset', 'Bank'),
    SeedAccount('Debtors', 'Debtors', 'Asset', 'Receivable'),
    SeedAccount('Stock', 'Stock In Hand', 'Asset', 'Stock'),
    SeedAccount('Creditors', 'Creditors', 'Liability', 'Payable'),
    SeedAccount('VAT', 'VAT', 'Liability', 'Tax'),
    SeedAccount('Sales', 'Sales', 'Income', 'Income Account'),
    SeedAccount('COGS', 'Cost of Goods Sold', 'Expense', 'Cost of Goods Sold'),
  ];

  /// Malta-style VAT bands; Standard (18%) is the default. All post to `VAT`.
  static const taxCodes = <SeedTaxCode>[
    SeedTaxCode('VAT 18%', 18, isDefault: true),
    SeedTaxCode('VAT 7%', 7),
    SeedTaxCode('VAT 5%', 5),
    SeedTaxCode('Zero-Rated', 0),
    SeedTaxCode('Exempt', 0),
  ];

  /// Company default-account wiring: field key → account id.
  static const companyDefaults = <String, String>{
    'default_receivable_account': 'Debtors',
    'default_income_account': 'Sales',
    'default_payable_account': 'Creditors',
    'default_expense_account': 'COGS',
    'default_cash_account': 'Bank',
    'default_vat_account': 'VAT',
  };
}

/// What a seed run created/found, for the onboarding summary.
class SeedSummary {
  const SeedSummary({required this.created, required this.alreadyPresent});
  final int created;
  final int alreadyPresent;
}

/// Lays down the foundational master data a fresh install needs so the finance
/// loop (invoicing + VAT, statements, payments) works immediately: a Currency,
/// the Main Store warehouse, the current Fiscal Year, a starter chart of
/// accounts, VAT bands, and a Company wired to those accounts.
///
/// Idempotent: every record has a deterministic id and is created only if
/// missing, so re-running is safe.
class HubSeeder {
  HubSeeder(this.engine, {this.roles = const {'System Manager'}});

  final DocumentEngine engine;
  final Set<String> roles;

  Future<bool> companyExists() async =>
      (await engine.list('Company', userRoles: roles)).isNotEmpty;

  Future<SeedSummary> seed({
    required String businessName,
    required String currencyCode,
    int? year,
  }) async {
    final code = currencyCode.trim().toUpperCase();
    final cy = year ?? DateTime.now().year;
    var created = 0;
    var present = 0;
    Future<void> ensure(String docType, String id, Map<String, dynamic> payload) async {
      if (await engine.fetch(docType, id) != null) {
        present++;
        return;
      }
      await engine.save(Document(id: id, docType: docType, payload: payload), roles);
      created++;
    }

    // 1. Currency — referenced by accounts + the company default.
    await ensure('Currency', code, {
      'currency_name': currencyName(code),
      'symbol': currencySymbol(code),
      'enabled': '1',
    });

    // 2. Default warehouse.
    await ensure('Warehouse', 'Main Store', {'warehouse_name': 'Main Store'});

    // 3. Current fiscal year (Jan 1 – Dec 31).
    final (start, end) = fiscalYearBounds(cy);
    await ensure('Fiscal Year', 'FY-$cy', {
      'year': 'FY $cy',
      'year_start_date': start,
      'year_end_date': end,
    });

    // 4. Chart of accounts (before the company, which links them).
    for (final a in HubChart.accounts) {
      await ensure('Account', a.id, {
        'account_name': a.name,
        'root_type': a.rootType,
        'account_type': a.accountType,
        'is_group': '0',
        'currency': code,
      });
    }

    // 5. VAT bands, all posting to the VAT account.
    for (final t in HubChart.taxCodes) {
      await ensure('Tax Code', t.id, {
        'tax_code_name': t.id,
        'tax_type': 'VAT',
        'rate': t.rate,
        'tax_account': 'VAT',
        'is_default': t.isDefault ? '1' : '0',
        'enabled': '1',
      });
    }

    // 6. Company, wired to the accounts above — only if none exists yet.
    if (!await companyExists()) {
      await engine.save(
        Document(id: '', docType: 'Company', payload: {
          'company_name': businessName.trim().isEmpty ? 'My Business' : businessName.trim(),
          'abbr': abbreviate(businessName),
          'default_currency': code,
          ...HubChart.companyDefaults,
        }),
        roles,
      );
      created++;
    } else {
      present++;
    }

    return SeedSummary(created: created, alreadyPresent: present);
  }

  /// (startIso, endIso) for the calendar [year].
  static (String, String) fiscalYearBounds(int year) {
    final y = year.toString().padLeft(4, '0');
    return ('$y-01-01', '$y-12-31');
  }

  /// A short uppercase abbreviation from a business name (initials, max 5).
  static String abbreviate(String name) {
    final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    final letters = words.map((w) => w[0].toUpperCase()).join();
    if (letters.isEmpty) return 'MB';
    return letters.length > 5 ? letters.substring(0, 5) : letters;
  }

  static String currencyName(String code) {
    switch (code) {
      case 'EUR':
        return 'Euro';
      case 'USD':
        return 'US Dollar';
      case 'GBP':
        return 'Pound Sterling';
      default:
        return code;
    }
  }

  static String currencySymbol(String code) {
    switch (code) {
      case 'EUR':
        return '€';
      case 'USD':
        return r'$';
      case 'GBP':
        return '£';
      default:
        return code;
    }
  }
}
