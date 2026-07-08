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
];

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
