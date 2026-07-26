import 'package:mercantis_core/mercantis_core.dart';

/// One ledger account in the starter chart of accounts. [id] doubles as the
/// deterministic record id the Company defaults point at.
class SeedAccount {
  const SeedAccount(
    this.id,
    this.name,
    this.rootType,
    this.accountType, {
    this.isGroup = false,
    this.parent,
  });
  final String id;
  final String name;
  final String rootType; // Asset / Liability / Income / Expense / Equity
  final String accountType; // Cash / Bank / Receivable / Payable / Tax / …
  /// A group account holds children and takes no postings (the tree's branches).
  final bool isGroup;
  /// Parent account id in the chart hierarchy; null for a root group.
  final String? parent;
}

/// One node in a starter tree-master hierarchy (Item Group, Customer Group, …).
/// [id] is the deterministic record id children point at; it is namespaced per
/// master because `documents.id` is a single global key, so the same display
/// [name] (e.g. "Services") can appear under two masters without colliding.
class SeedTreeNode {
  const SeedTreeNode(this.id, this.name, {this.isGroup = false, this.parent});
  final String id;
  /// Display name (the tree label / link-picker title).
  final String name;
  /// A group (branch) node holds children; leaves are the ones records tag.
  final bool isGroup;
  /// Parent node id; null for the root.
  final String? parent;
}

/// A starter hierarchy for a self-referential tree DocType — its DocType id plus
/// the name/parent field keys and the nodes to lay down, so one loop seeds any
/// of them (see [HubChart.treeMasters]).
class SeedTreeMaster {
  const SeedTreeMaster({
    required this.docType,
    required this.nameField,
    required this.parentField,
    required this.nodes,
  });
  final String docType;
  final String nameField;
  final String parentField;
  final List<SeedTreeNode> nodes;
}

/// One tax band seeded so the tax engine works out of the box.
class SeedTaxCode {
  const SeedTaxCode(this.id, this.rate, {this.isDefault = false, this.type = 'VAT'});
  final String id;
  final num rate;
  final bool isDefault;
  final String type; // VAT / SalesTax / Excise / Withholding
}

/// A tax jurisdiction (country) the onboarding wizard can pick: its starter tax
/// bands and the currency it usually trades in. The chart of accounts is shared
/// across jurisdictions ([HubChart.accounts]); only the tax codes differ. Adding
/// a jurisdiction later and re-seeding is additive (ids are deterministic), so
/// the setup adapts on re-run.
class JurisdictionPreset {
  const JurisdictionPreset({
    required this.id,
    required this.label,
    required this.currencyCode,
    required this.taxCodes,
  });

  final String id;
  final String label;
  final String currencyCode;
  final List<SeedTaxCode> taxCodes;

  static const malta = JurisdictionPreset(
    id: 'MT',
    label: 'Malta',
    currencyCode: 'EUR',
    taxCodes: [
      SeedTaxCode('VAT 18%', 18, isDefault: true),
      SeedTaxCode('VAT 7%', 7),
      SeedTaxCode('VAT 5%', 5),
      SeedTaxCode('Zero-Rated', 0),
      SeedTaxCode('Exempt', 0),
    ],
  );

  static const unitedKingdom = JurisdictionPreset(
    id: 'GB',
    label: 'United Kingdom',
    currencyCode: 'GBP',
    taxCodes: [
      SeedTaxCode('VAT 20%', 20, isDefault: true),
      SeedTaxCode('VAT 5%', 5),
      SeedTaxCode('Zero-Rated', 0),
      SeedTaxCode('Exempt', 0),
    ],
  );

  static const ireland = JurisdictionPreset(
    id: 'IE',
    label: 'Ireland',
    currencyCode: 'EUR',
    taxCodes: [
      SeedTaxCode('VAT 23%', 23, isDefault: true),
      SeedTaxCode('VAT 13.5%', 13.5),
      SeedTaxCode('VAT 9%', 9),
      SeedTaxCode('Zero-Rated', 0),
      SeedTaxCode('Exempt', 0),
    ],
  );

  /// Fallback for anywhere without a built-in template: one editable standard
  /// band plus Exempt. The operator tunes the rate/type afterwards.
  static const generic = JurisdictionPreset(
    id: 'GENERIC',
    label: 'Other / No VAT',
    currencyCode: 'USD',
    taxCodes: [
      SeedTaxCode('Standard Tax', 0, isDefault: true),
      SeedTaxCode('Exempt', 0),
    ],
  );

  static const all = [malta, unitedKingdom, ireland, generic];

  /// The preset with [id], or [malta] when unknown/null — so an unrecognised
  /// stored jurisdiction degrades to the original default rather than failing.
  static JurisdictionPreset byId(String? id) =>
      all.firstWhere((j) => j.id == id, orElse: () => malta);
}

/// The starter master data the onboarding seeder lays down (ported from the
/// Swift `HubOnboardingSeeder`, extended with VAT bands). Kept as pure data so
/// it can be asserted without a database.
abstract final class HubChart {
  /// Starter chart of accounts, as a two-level tree: one group account per root
  /// type holds the posting (leaf) accounts under it, so the Account tree view
  /// reads as a real chart. The Company default-account fields wire to the leaf
  /// ids (see [companyDefaults]). Groups come first so a parent always exists
  /// before the child that points at it.
  static const accounts = <SeedAccount>[
    // Root groups — branches of the tree; hold children, take no postings.
    SeedAccount('Assets', 'Assets', 'Asset', '', isGroup: true),
    SeedAccount('Liabilities', 'Liabilities', 'Liability', '', isGroup: true),
    SeedAccount('Income', 'Income', 'Income', '', isGroup: true),
    SeedAccount('Expenses', 'Expenses', 'Expense', '', isGroup: true),
    SeedAccount('Equity', 'Equity', 'Equity', '', isGroup: true),
    // Posting (leaf) accounts, each parented under its root group.
    SeedAccount('Cash', 'Cash', 'Asset', 'Cash', parent: 'Assets'),
    SeedAccount('Bank', 'Bank', 'Asset', 'Bank', parent: 'Assets'),
    SeedAccount('Debtors', 'Debtors', 'Asset', 'Receivable', parent: 'Assets'),
    SeedAccount('Stock', 'Stock In Hand', 'Asset', 'Stock', parent: 'Assets'),
    SeedAccount('Creditors', 'Creditors', 'Liability', 'Payable', parent: 'Liabilities'),
    // Perpetual inventory (Phase 1B): receipts credit GRNI until the supplier
    // bill clears it; counts/adjustments post to Stock Adjustment.
    SeedAccount('GRNI', 'Stock Received But Not Billed', 'Liability', 'Stock Received But Not Billed', parent: 'Liabilities'),
    SeedAccount('VAT', 'VAT', 'Liability', 'Tax', parent: 'Liabilities'),
    SeedAccount('Customer Deposits', 'Customer Deposits', 'Liability', '', parent: 'Liabilities'),
    SeedAccount('Sales', 'Sales', 'Income', 'Income Account', parent: 'Income'),
    SeedAccount('COGS', 'Cost of Goods Sold', 'Expense', 'Cost of Goods Sold', parent: 'Expenses'),
    SeedAccount('Stock Adjustment', 'Stock Adjustment', 'Expense', 'Stock Adjustment', parent: 'Expenses'),
    // The contra the OpeningBalanceBuilder balances an opening entry against.
    SeedAccount('Opening Balance Equity', 'Opening Balance Equity', 'Equity', 'Equity', parent: 'Equity'),
    // Where the YearEndCloseBuilder posts the period's profit or loss.
    SeedAccount('Retained Earnings', 'Retained Earnings', 'Equity', 'Equity', parent: 'Equity'),
  ];

  /// Company default-account wiring: field key → account id.
  static const companyDefaults = <String, String>{
    'default_receivable_account': 'Debtors',
    'default_income_account': 'Sales',
    'default_payable_account': 'Creditors',
    'default_expense_account': 'COGS',
    'default_cash_account': 'Bank',
    'default_vat_account': 'VAT',
    'default_inventory_account': 'Stock',
    'default_cogs_account': 'COGS',
    'default_stock_adjustment_account': 'Stock Adjustment',
    'default_grni_account': 'GRNI',
    'default_customer_deposit_account': 'Customer Deposits',
  };

  /// Starter hierarchies for the other tree masters, kept deliberately small and
  /// micro-business oriented: a root group with a couple of practical leaves the
  /// operator can tag records under, so each tree view reads as a real hierarchy
  /// out of the box (mirrors the grouped chart of accounts above).
  static const treeMasters = <SeedTreeMaster>[
    SeedTreeMaster(
      docType: 'Item Group',
      nameField: 'item_group_name',
      parentField: 'parent_item_group',
      nodes: [
        SeedTreeNode('IG-All', 'All Item Groups', isGroup: true),
        SeedTreeNode('IG-Products', 'Products', parent: 'IG-All'),
        SeedTreeNode('IG-Services', 'Services', parent: 'IG-All'),
      ],
    ),
    SeedTreeMaster(
      docType: 'Customer Group',
      nameField: 'customer_group_name',
      parentField: 'parent_customer_group',
      nodes: [
        SeedTreeNode('CG-All', 'All Customer Groups', isGroup: true),
        SeedTreeNode('CG-Retail', 'Retail', parent: 'CG-All'),
        SeedTreeNode('CG-Business', 'Business', parent: 'CG-All'),
      ],
    ),
    SeedTreeMaster(
      docType: 'Supplier Group',
      nameField: 'supplier_group_name',
      parentField: 'parent_supplier_group',
      nodes: [
        SeedTreeNode('SG-All', 'All Supplier Groups', isGroup: true),
        SeedTreeNode('SG-Goods', 'Goods', parent: 'SG-All'),
        SeedTreeNode('SG-Services', 'Services', parent: 'SG-All'),
      ],
    ),
    SeedTreeMaster(
      docType: 'Territory',
      nameField: 'territory_name',
      parentField: 'parent_territory',
      nodes: [
        SeedTreeNode('TR-All', 'All Territories', isGroup: true),
        SeedTreeNode('TR-Local', 'Local', parent: 'TR-All'),
        SeedTreeNode('TR-Online', 'Online', parent: 'TR-All'),
      ],
    ),
    SeedTreeMaster(
      docType: 'Cost Center',
      nameField: 'cost_center_name',
      parentField: 'parent_cost_center',
      nodes: [
        SeedTreeNode('CC-Main', 'Main', isGroup: true),
        SeedTreeNode('CC-Operations', 'Operations', parent: 'CC-Main'),
      ],
    ),
  ];
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

  /// Re-runs the starter seeding against the EXISTING company, so a book
  /// created before the seed list grew (major currencies, default UOMs,
  /// company country) picks up the additions. Name, currency, and
  /// jurisdiction all come from the record: the stored country label is
  /// authoritative when it names a preset; otherwise the book's current
  /// default tax band identifies the preset it was seeded from. Only a
  /// confident match may re-enforce that preset's default band — a guessed
  /// fallback must not unseat whatever default the operator has chosen.
  Future<SeedSummary> reseed() async {
    final companies = await engine.list('Company', userRoles: roles);
    if (companies.isEmpty) {
      throw StateError('No company on file — run onboarding first.');
    }
    final company = companies.first;
    final country = '${company.payload['country'] ?? ''}'.trim();

    JurisdictionPreset? match;
    for (final j in JurisdictionPreset.all) {
      if (j.label == country) {
        match = j;
        break;
      }
    }
    if (match == null) {
      final defaults = (await engine.list('Tax Code', userRoles: roles))
          .where((c) => '${c.payload['is_default'] ?? '0'}' == '1')
          .map((c) => c.id)
          .toSet();
      for (final j in JurisdictionPreset.all) {
        if (j.taxCodes.any((t) => t.isDefault && defaults.contains(t.id))) {
          match = j;
          break;
        }
      }
    }
    final jurisdiction = match ?? JurisdictionPreset.malta;
    final currency = '${company.payload['default_currency'] ?? ''}'.trim();
    return seed(
      businessName: '${company.payload['company_name'] ?? ''}',
      currencyCode: currency.isEmpty ? jurisdiction.currencyCode : currency,
      jurisdiction: jurisdiction,
      enforceDefaultTaxCode: match != null,
    );
  }

  Future<SeedSummary> seed({
    required String businessName,
    required String currencyCode,
    int? year,
    JurisdictionPreset jurisdiction = JurisdictionPreset.malta,
    bool enforceDefaultTaxCode = true,
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

    // 1. Currencies — the chosen one plus the majors, so multi-currency
    //    documents have real options from day one (the company still
    //    defaults to the chosen code).
    for (final c in {code, ...majorCurrencies.keys}) {
      await ensure('Currency', c, {
        'currency_name': currencyName(c),
        'symbol': currencySymbol(c),
        'enabled': '1',
      });
    }

    // 2. Default warehouse.
    await ensure('Warehouse', 'Main Store', {'warehouse_name': 'Main Store'});

    // 2b. Units of measure — the everyday list, count units flagged
    //     whole-number. Matches (and extends) the line-item UOM options.
    for (final u in defaultUoms.entries) {
      await ensure('UOM', u.key, {
        'uom_name': u.key,
        'must_be_whole_number': u.value ? '1' : '0',
        'enabled': '1',
      });
    }

    // 3. Current fiscal year (Jan 1 – Dec 31).
    final (start, end) = fiscalYearBounds(cy);
    await ensure('Fiscal Year', 'FY-$cy', {
      'year': 'FY $cy',
      'year_start_date': start,
      'year_end_date': end,
    });

    // 4. Chart of accounts (before the company, which links them). Groups are
    //    listed first so a parent always exists before its children.
    for (final a in HubChart.accounts) {
      await ensure('Account', a.id, {
        'account_name': a.name,
        'root_type': a.rootType,
        if (a.accountType.isNotEmpty) 'account_type': a.accountType,
        'is_group': a.isGroup ? '1' : '0',
        if (a.parent != null) 'parent_account': a.parent,
        'currency': code,
      });
    }

    // 4b. Starter tree masters (item / customer / supplier groups, territories,
    //     cost centres) — a small hierarchy each so their trees aren't empty.
    //     Roots are listed first so a parent exists before its children.
    for (final m in HubChart.treeMasters) {
      for (final n in m.nodes) {
        await ensure(m.docType, n.id, {
          m.nameField: n.name,
          'is_group': n.isGroup ? '1' : '0',
          if (n.parent != null) m.parentField: n.parent,
        });
      }
    }

    // 5. Tax bands for the chosen jurisdiction, all posting to the VAT/Tax
    //    account. Re-seeding with a different jurisdiction adds its bands.
    String? defaultCode;
    for (final t in jurisdiction.taxCodes) {
      if (t.isDefault) defaultCode = t.id;
      await ensure('Tax Code', t.id, {
        'tax_code_name': t.id,
        'tax_type': t.type,
        'rate': t.rate,
        'tax_account': 'VAT',
        'is_default': t.isDefault ? '1' : '0',
        'enabled': '1',
      });
    }
    // Make this region's default the *sole* default — a re-run that switched
    // region would otherwise leave the previous region's default in place too.
    // Skipped when the caller only inferred the jurisdiction ([reseed] without
    // a confident match), so an operator-chosen default survives.
    if (enforceDefaultTaxCode && defaultCode != null) {
      for (final c in await engine.list('Tax Code', userRoles: roles)) {
        final want = c.id == defaultCode ? '1' : '0';
        if ('${c.payload['is_default'] ?? '0'}' != want) {
          c.payload['is_default'] = want;
          await engine.save(c, roles);
        }
      }
    }

    // 6. Company, wired to the accounts above. Create one if none exists;
    //    otherwise re-base its default currency to the chosen region (an
    //    adaptive re-run), so new drafts default to the right currency.
    if (!await companyExists()) {
      await engine.save(
        Document(id: '', docType: 'Company', payload: {
          'company_name': businessName.trim().isEmpty ? 'My Business' : businessName.trim(),
          'abbr': abbreviate(businessName),
          'default_currency': code,
          // The jurisdiction chosen in onboarding IS the company's country
          // — it must land on the record (the e-invoice seller country and
          // VAT box mapping read it, and the user typed it in good faith).
          'country': jurisdiction.label,
          ...HubChart.companyDefaults,
        }),
        roles,
      );
      created++;
    } else {
      final company = (await engine.list('Company', userRoles: roles)).first;
      var changed = false;
      if (company.payload['default_currency'] != code) {
        company.payload['default_currency'] = code;
        changed = true;
      }
      // Backfill a blank country (companies created before this existed).
      final country = company.payload['country'];
      if (country == null || '$country'.trim().isEmpty) {
        company.payload['country'] = jurisdiction.label;
        changed = true;
      }
      if (changed) await engine.save(company, roles);
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

  /// The majors seeded on every install: code → (name, symbol). The
  /// company defaults to the onboarding choice; these just exist and are
  /// enabled so multi-currency documents have real options.
  static const majorCurrencies = <String, (String, String)>{
    'EUR': ('Euro', '€'),
    'USD': ('US Dollar', r'$'),
    'GBP': ('Pound Sterling', '£'),
    'CHF': ('Swiss Franc', 'CHF'),
    'JPY': ('Japanese Yen', '¥'),
    'CNY': ('Chinese Yuan', '¥'),
    'AUD': ('Australian Dollar', r'A$'),
    'CAD': ('Canadian Dollar', r'C$'),
    'NZD': ('New Zealand Dollar', r'NZ$'),
    'SEK': ('Swedish Krona', 'kr'),
    'NOK': ('Norwegian Krone', 'kr'),
    'DKK': ('Danish Krone', 'kr'),
    'PLN': ('Polish Zloty', 'zł'),
    'CZK': ('Czech Koruna', 'Kč'),
    'HUF': ('Hungarian Forint', 'Ft'),
    'RON': ('Romanian Leu', 'lei'),
    'BGN': ('Bulgarian Lev', 'лв'),
    'TRY': ('Turkish Lira', '₺'),
    'AED': ('UAE Dirham', 'AED'),
  };

  /// The everyday units seeded on every install: name → whole-number.
  /// A superset of the line-item UOM select options, so picking from
  /// either place stays consistent.
  static const defaultUoms = <String, bool>{
    'Nos': true,
    'Unit': true,
    'Pair': true,
    'Set': true,
    'Box': true,
    'Pack': true,
    'Dozen': true,
    'Kg': false,
    'Grams': false,
    'Litre': false,
    'Millilitre': false,
    'Metre': false,
    'Centimetre': false,
    'Sq Metre': false,
    'Hour': false,
    'Day': false,
  };

  static String currencyName(String code) =>
      majorCurrencies[code]?.$1 ?? code;

  static String currencySymbol(String code) =>
      majorCurrencies[code]?.$2 ?? code;
}
