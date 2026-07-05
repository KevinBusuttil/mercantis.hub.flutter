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
/// [id] doubles as the deterministic record id and its display name, and the id
/// children point at.
class SeedTreeNode {
  const SeedTreeNode(this.id, {this.isGroup = false, this.parent});
  final String id;
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
    SeedAccount('VAT', 'VAT', 'Liability', 'Tax', parent: 'Liabilities'),
    SeedAccount('Sales', 'Sales', 'Income', 'Income Account', parent: 'Income'),
    SeedAccount('COGS', 'Cost of Goods Sold', 'Expense', 'Cost of Goods Sold', parent: 'Expenses'),
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
        SeedTreeNode('All Item Groups', isGroup: true),
        SeedTreeNode('Products', parent: 'All Item Groups'),
        SeedTreeNode('Services', parent: 'All Item Groups'),
      ],
    ),
    SeedTreeMaster(
      docType: 'Customer Group',
      nameField: 'customer_group_name',
      parentField: 'parent_customer_group',
      nodes: [
        SeedTreeNode('All Customer Groups', isGroup: true),
        SeedTreeNode('Retail', parent: 'All Customer Groups'),
        SeedTreeNode('Business', parent: 'All Customer Groups'),
      ],
    ),
    SeedTreeMaster(
      docType: 'Supplier Group',
      nameField: 'supplier_group_name',
      parentField: 'parent_supplier_group',
      nodes: [
        SeedTreeNode('All Supplier Groups', isGroup: true),
        SeedTreeNode('Goods', parent: 'All Supplier Groups'),
        SeedTreeNode('Services', parent: 'All Supplier Groups'),
      ],
    ),
    SeedTreeMaster(
      docType: 'Territory',
      nameField: 'territory_name',
      parentField: 'parent_territory',
      nodes: [
        SeedTreeNode('All Territories', isGroup: true),
        SeedTreeNode('Local', parent: 'All Territories'),
        SeedTreeNode('Online', parent: 'All Territories'),
      ],
    ),
    SeedTreeMaster(
      docType: 'Cost Center',
      nameField: 'cost_center_name',
      parentField: 'parent_cost_center',
      nodes: [
        SeedTreeNode('Main', isGroup: true),
        SeedTreeNode('Operations', parent: 'Main'),
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

  Future<SeedSummary> seed({
    required String businessName,
    required String currencyCode,
    int? year,
    JurisdictionPreset jurisdiction = JurisdictionPreset.malta,
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
          m.nameField: n.id,
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
    if (defaultCode != null) {
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
          ...HubChart.companyDefaults,
        }),
        roles,
      );
      created++;
    } else {
      final company = (await engine.list('Company', userRoles: roles)).first;
      if (company.payload['default_currency'] != code) {
        company.payload['default_currency'] = code;
        await engine.save(company, roles);
      }
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
