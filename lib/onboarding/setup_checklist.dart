import 'package:mercantis_core/mercantis_core.dart';

import '../ledger/ledger_values.dart';
import '../settings/hub_settings.dart';

/// The guided setup checklist (Phase 1A): answers "what still needs doing?"
/// and "can I safely send my first invoice?" from the live document store.
/// Every check is deterministic — recomputed on each visit, never stored — so
/// the list can't drift from reality.

enum SetupItemStatus { done, todo, notApplicable }

class SetupChecklistItem {
  const SetupChecklistItem({
    required this.id,
    required this.label,
    required this.description,
    required this.status,
    required this.route,
    this.required = false,
  });

  final String id;
  final String label;
  final String description;
  final SetupItemStatus status;

  /// Router location that takes the user to where the step is completed.
  final String route;

  /// Whether this step gates "you can safely start invoicing".
  final bool required;

  bool get isDone => status == SetupItemStatus.done;
  bool get isApplicable => status != SetupItemStatus.notApplicable;
}

class SetupChecklist {
  const SetupChecklist(this.items);

  final List<SetupChecklistItem> items;

  List<SetupChecklistItem> get applicable =>
      [for (final i in items) if (i.isApplicable) i];

  int get doneCount => applicable.where((i) => i.isDone).length;
  int get totalCount => applicable.length;

  /// True when every invoicing-critical step is done: company profile, tax
  /// setup, a fiscal year covering today, at least one customer and one item.
  bool get readyToInvoice =>
      items.where((i) => i.required && i.isApplicable).every((i) => i.isDone);

  List<SetupChecklistItem> get missingForInvoicing => [
        for (final i in items)
          if (i.required && i.isApplicable && !i.isDone) i
      ];
}

/// Computes the checklist. [settings] decides which conditional steps apply
/// (stock, POS) — hidden modules report [SetupItemStatus.notApplicable].
Future<SetupChecklist> buildSetupChecklist(
  DocumentEngine engine,
  HubSettings settings, {
  Set<String> roles = const {'System Manager'},
}) async {
  Future<List<Document>> list(String docType) async {
    try {
      return await engine.list(docType, userRoles: roles);
    } catch (_) {
      return const []; // doctype missing (partial installs) → treat as empty
    }
  }

  SetupItemStatus has(bool condition) =>
      condition ? SetupItemStatus.done : SetupItemStatus.todo;

  final companies = await list('Company');
  final company = companies.isEmpty ? null : companies.first;
  final companyRoute =
      company == null ? '/list/Company' : '/form/Company/${company.id}';

  final taxCodes = await list('Tax Code');
  final hasEnabledTax = taxCodes.any((t) {
    final v = t.payload['enabled'];
    return v == null || isTrue(v); // blank counts as enabled (seeder default)
  });

  final today = DateTime.now();
  final fiscalYears = await list('Fiscal Year');
  final hasCurrentFiscalYear = fiscalYears.any((y) {
    final start = DateTime.tryParse('${y.payload['year_start_date'] ?? ''}');
    final end = DateTime.tryParse('${y.payload['year_end_date'] ?? ''}');
    if (start == null || end == null) return false;
    return !today.isBefore(start) && !today.isAfter(end);
  });

  final customers = await list('Customer');
  final suppliers = await list('Supplier');
  final items = await list('Item');
  final hasStockItem = items.any((i) => isStockItem(i.payload));

  final journals = await list('Journal Entry');
  final hasOpeningEntry = journals
      .any((j) => '${j.payload['voucher_type'] ?? ''}' == 'Opening Entry');

  final bankAccounts = await list('Bank Account');
  final posProfiles = await list('POS Profile');

  final quotes = await list('Quotation');
  final invoices = await list('Sales Invoice');

  return SetupChecklist([
    SetupChecklistItem(
      id: 'company',
      label: 'Company profile',
      description: 'Name, country and default accounts',
      status: has(company != null &&
          '${company.payload['company_name'] ?? ''}'.trim().isNotEmpty),
      route: companyRoute,
      required: true,
    ),
    SetupChecklistItem(
      id: 'branding',
      label: 'Logo & branding',
      description: 'Add your logo so documents look like yours',
      status: has(company != null &&
          '${company.payload['company_logo'] ?? ''}'.trim().isNotEmpty),
      route: companyRoute,
    ),
    SetupChecklistItem(
      id: 'tax',
      label: 'VAT / tax codes',
      description: 'At least one active tax code for your region',
      status: has(hasEnabledTax),
      route: '/list/Tax Code',
      required: true,
    ),
    SetupChecklistItem(
      id: 'fiscal_year',
      label: 'Fiscal year',
      description: 'A fiscal year covering today',
      status: has(hasCurrentFiscalYear),
      route: '/list/Fiscal Year',
      required: true,
    ),
    const SetupChecklistItem(
      id: 'numbering',
      label: 'Document numbering',
      description: 'Sensible defaults are in place — adjust if you need '
          'your own sequences',
      status: SetupItemStatus.done,
      route: '/w/setup/numbering-series',
    ),
    SetupChecklistItem(
      id: 'customers',
      label: 'Add customers',
      description: 'Create or import the people you invoice',
      status: has(customers.isNotEmpty),
      route: '/list/Customer',
      required: true,
    ),
    SetupChecklistItem(
      id: 'items',
      label: 'Add items or services',
      description: 'What you sell — products or services',
      status: has(items.isNotEmpty),
      route: '/list/Item',
      required: true,
    ),
    SetupChecklistItem(
      id: 'suppliers',
      label: 'Add suppliers',
      description: 'Who you buy from (needed for bills and expenses)',
      status: has(suppliers.isNotEmpty),
      route: '/list/Supplier',
    ),
    SetupChecklistItem(
      id: 'opening_balances',
      label: 'Opening balances',
      description: 'Bring over balances from your previous system — skip '
          'if you are starting fresh',
      status: has(hasOpeningEntry),
      route: '/w/setup/opening-balances',
    ),
    SetupChecklistItem(
      id: 'bank_account',
      label: 'Bank account',
      description: 'Record the account customers pay into',
      status: has(bankAccounts.isNotEmpty),
      route: '/list/Bank Account',
    ),
    SetupChecklistItem(
      id: 'stock',
      label: 'Stock items',
      description: 'Mark the items you keep on the shelf as stock items',
      status: settings.stockEnabled
          ? has(hasStockItem)
          : SetupItemStatus.notApplicable,
      route: '/list/Item',
    ),
    SetupChecklistItem(
      id: 'pos',
      label: 'POS profile',
      description: 'Till configuration: warehouse, cash account and taxes',
      status: settings.posEnabled
          ? has(posProfiles.isNotEmpty)
          : SetupItemStatus.notApplicable,
      route: '/list/POS Profile',
    ),
    SetupChecklistItem(
      id: 'first_document',
      label: 'Send your first quote or invoice',
      description: 'The moment it all becomes real',
      status: has(quotes.isNotEmpty || invoices.isNotEmpty),
      route: '/form/Quotation/new',
    ),
  ]);
}
