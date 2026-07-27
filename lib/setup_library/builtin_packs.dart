import 'setup_pack.dart';

/// The built-in starter catalogue (design doc §2 — the first slice of it).
/// These compose over whatever the onboarding seeder laid down: masters are
/// ensure-if-absent, so a pack is safe on any install regardless of preset.
/// Solo ships them in the binary (offline by construction); the hosted
/// catalogue distributes the same format later.
final List<SetupPack> builtinSetupPacks = [
  stockAndCogsPack,
  posShopPack,
  bankRulesStarterPack,
  appointmentsPack,
  clinicPack,
];

/// V8 Clinic Pack (B-2): the business side of a medical GP practice,
/// composed on the appointments machinery. Consultations bill VAT-exempt
/// as medical care — the B-1 category so e-invoices export E with the
/// Article 132(1) reason — while certificates/reports for third parties
/// are NOT therapeutic care and deliberately carry no tax code, so the
/// book's default (standard) band applies to them. No clinical data
/// anywhere: the Customer record is billing identity only, and every
/// seeded name stays neutral (GDPR §6.1 — "Consultation", never the
/// complaint). Atlas is not an EMR; patient records live in a clinical
/// system and reach Atlas only as integration events.
const clinicPack = SetupPack(
  id: 'clinic',
  name: 'Clinic (Medical GP)',
  version: '1.0.0',
  dependsOn: ['appointments'],
  description: 'Front desk and billing for a medical practice: '
      'consultation and home-visit items billed VAT-exempt with the '
      'Article 132(1) exemption stated on the e-invoice, a taxable '
      'medical-certificate item, a Doctor diary, and deposits held as '
      'a liability until the visit invoices. Patient clinical records '
      'stay in your clinical system — Atlas holds billing identity '
      'only.',
  masters: [
    PackMaster(docType: 'Account', id: 'Customer Deposits', payload: {
      'account_name': 'Customer Deposits',
      'root_type': 'Liability',
    }),
    PackMaster(docType: 'Tax Code', id: 'VAT-EX-MED', payload: {
      'tax_code_name': 'Exempt — Medical Care',
      'tax_type': 'VAT',
      'rate': 0,
      'vat_category': 'Exempt',
      'exemption_reason': 'Exempt from VAT — medical care '
          '(Article 132(1) of the VAT Directive)',
      'enabled': 1,
    }),
    PackMaster(docType: 'Item Group', id: 'IG-Medical', payload: {
      'item_group_name': 'Medical Services',
    }),
    // Exempt therapeutic services. Prices are the practice's to set.
    PackMaster(docType: 'Item', id: 'CONSULT', payload: {
      'item_code': 'CONSULT',
      'item_name': 'Consultation',
      'item_type': 'Service',
      'stock_uom': 'Nos',
      'item_group': 'IG-Medical',
      'tax_code': 'VAT-EX-MED',
    }),
    PackMaster(docType: 'Item', id: 'CONSULT-FU', payload: {
      'item_code': 'CONSULT-FU',
      'item_name': 'Follow-up Consultation',
      'item_type': 'Service',
      'stock_uom': 'Nos',
      'item_group': 'IG-Medical',
      'tax_code': 'VAT-EX-MED',
    }),
    PackMaster(docType: 'Item', id: 'HOME-VISIT', payload: {
      'item_code': 'HOME-VISIT',
      'item_name': 'Home Visit',
      'item_type': 'Service',
      'stock_uom': 'Nos',
      'item_group': 'IG-Medical',
      'tax_code': 'VAT-EX-MED',
    }),
    // A certificate/report for an employer or insurer is not therapeutic
    // care — it is standard-rated, so NO tax code here: the book's
    // default (standard) band applies.
    PackMaster(docType: 'Item', id: 'MED-CERT', payload: {
      'item_code': 'MED-CERT',
      'item_name': 'Medical Certificate / Report',
      'item_type': 'Service',
      'stock_uom': 'Nos',
      'item_group': 'IG-Medical',
    }),
    PackMaster(docType: 'Schedulable Resource', id: 'Doctor', payload: {
      'resource_name': 'Doctor',
      'resource_type': 'Person',
      'enabled': 1,
    }),
  ],
  // The clinic shape: appointments on; trade/production surfaces off.
  // POS stays off until the EXO fiscal-receipt question (spec §7) says
  // otherwise — the operator can flip it any time in Settings.
  moduleToggles: {
    'appointments': true,
    'stock': false,
    'pos': false,
    'projects': false,
    'manufacturing': false,
    'deliveries': false,
  },
);

/// Phase 4: the appointments composition (salon / tutor / studio /
/// clinic front desk). Books need a deposit liability account to hold
/// prepayments (S4); the pack seeds it and turns the booking surfaces on.
const appointmentsPack = SetupPack(
  id: 'appointments',
  name: 'Appointments & Booking',
  version: '1.0.0',
  description: 'Front-desk booking on your existing invoicing: '
      'conflict-checked slots per staff member, deposits held as a '
      'liability until the visit invoices, and commission rules per '
      'staff member or service.',
  masters: [
    PackMaster(docType: 'Account', id: 'Customer Deposits', payload: {
      'account_name': 'Customer Deposits',
      'root_type': 'Liability',
    }),
  ],
  moduleToggles: {'appointments': true},
);

/// Stock & COGS module pack: the perpetual-inventory accounts and company
/// defaults, for installs whose preset didn't enable stock.
const stockAndCogsPack = SetupPack(
  id: 'stock-and-cogs',
  name: 'Stock and COGS',
  version: '1.0.0',
  description: 'Perpetual inventory: stock, COGS, GRNI and adjustment '
      'accounts, wired as company defaults. Sales and purchases with '
      'update_stock post real cost of goods sold.',
  masters: [
    PackMaster(docType: 'Account', id: 'Stock', payload: {
      'account_name': 'Stock In Hand',
      'root_type': 'Asset',
      'account_type': 'Stock',
    }),
    PackMaster(docType: 'Account', id: 'COGS', payload: {
      'account_name': 'Cost of Goods Sold',
      'root_type': 'Expense',
      'account_type': 'Cost of Goods Sold',
    }),
    PackMaster(docType: 'Account', id: 'GRNI', payload: {
      'account_name': 'Stock Received But Not Billed',
      'root_type': 'Liability',
      'account_type': 'Stock Received But Not Billed',
    }),
    PackMaster(docType: 'Account', id: 'Stock Adjustment', payload: {
      'account_name': 'Stock Adjustment',
      'root_type': 'Expense',
      'account_type': 'Stock Adjustment',
    }),
  ],
  companyDefaults: {
    'default_inventory_account': 'Stock',
    'default_cogs_account': 'COGS',
    'default_grni_account': 'GRNI',
    'default_stock_adjustment_account': 'Stock Adjustment',
  },
  moduleToggles: {'stock': true},
);

/// POS module pack: counter-sales accounts and visibility.
const posShopPack = SetupPack(
  id: 'pos-shop',
  name: 'Point of Sale',
  version: '1.0.0',
  description: 'Over-the-counter sales: a cash-drawer account and the POS '
      'surfaces (till, sessions, Z-reports).',
  masters: [
    PackMaster(docType: 'Account', id: 'Cash Drawer', payload: {
      'account_name': 'Cash Drawer',
      'root_type': 'Asset',
      'account_type': 'Cash',
    }),
  ],
  moduleToggles: {'pos': true},
);

/// Starter bank-categorisation rules: the common noise every statement
/// carries, pre-explained. All Suggest Only — nothing posts from a rule
/// without a person accepting the suggestion (rule-first AI doctrine §5).
const bankRulesStarterPack = SetupPack(
  id: 'bank-rules-starter',
  name: 'Bank Categorisation Starter Rules',
  version: '1.0.0',
  description: 'Deterministic starter rules for everyday statement lines: '
      'bank fees and card-provider charges. Suggestions only — you stay in '
      'charge of what posts.',
  masters: [
    PackMaster(docType: 'Account', id: 'Bank Charges', payload: {
      'account_name': 'Bank Charges',
      'root_type': 'Expense',
      'account_type': 'Expense',
    }),
  ],
  rules: [
    {
      'rule_name': 'Bank fees',
      'rule_type': 'Bank Categorisation',
      'active': 1,
      'priority': 10,
      'match_contains': 'fee',
      'match_direction': 'Money Out',
      'set_account': 'Bank Charges',
      'auto_action': 'Suggest Only',
      'affects_accounting': 1,
    },
    {
      'rule_name': 'Bank charges',
      'rule_type': 'Bank Categorisation',
      'active': 1,
      'priority': 11,
      'match_contains': 'charge',
      'match_direction': 'Money Out',
      'set_account': 'Bank Charges',
      'auto_action': 'Suggest Only',
      'affects_accounting': 1,
    },
  ],
);
