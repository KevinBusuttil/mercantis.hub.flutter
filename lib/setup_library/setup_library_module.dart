import 'package:mercantis_core/mercantis_core.dart';

/// Atlas Setup Library doctypes (ATLAS_SETUP_LIBRARY_AND_RULE_FIRST_AI.md):
///
///  * `Setup Rule` — one deterministic rule. Stored as an ordinary document
///    so it syncs, diffs and audits like everything else. Every rule carries
///    its provenance (built-in / user-created / accountant-created /
///    AI-suggested) and an `affects_accounting` flag that forces
///    review-before-apply.
///  * `Setup Pack Application` — the recorded diff of one pack apply: what
///    was created, what already existed, exactly which version ran. This is
///    both the user-facing "what did this pack change" answer and the
///    upgrade ledger.
abstract final class SetupLibraryModule {
  static const _module = 'Setup Library';

  static List<DocType> docTypes() => [
        _setupRule(),
        _packApplication(),
      ];

  static DocType _setupRule() => const DocType(
        id: 'Setup Rule',
        name: 'Setup Rule',
        module: _module,
        namingRule: 'RULE-.####',
        fields: [
          FieldDefinition(key: 'rule_name', label: 'Rule Name', type: FieldType.data, required: true),
          FieldDefinition(
            key: 'rule_type',
            label: 'Type',
            type: FieldType.select,
            options: 'Bank Categorisation\nSupplier Mapping\nSKU Mapping\nTax Treatment\nDefault Account',
            required: true,
          ),
          FieldDefinition(
            key: 'provenance',
            label: 'Provenance',
            type: FieldType.select,
            options: 'built-in\nuser-created\naccountant-created\nAI-suggested',
            defaultValue: 'user-created',
          ),
          FieldDefinition(key: 'active', label: 'Active', type: FieldType.check, defaultValue: '1'),
          // Lower runs first; ties break on id so evaluation is deterministic.
          FieldDefinition(key: 'priority', label: 'Priority', type: FieldType.integer, defaultValue: '100'),
          // Conditions (used by types that match transactions/rows). All the
          // set conditions must hold — one rule is one explainable AND.
          FieldDefinition(key: 'match_contains', label: 'Description Contains', type: FieldType.data),
          FieldDefinition(key: 'match_reference', label: 'Reference Contains', type: FieldType.data),
          FieldDefinition(
            key: 'match_direction',
            label: 'Direction',
            type: FieldType.select,
            options: '\nMoney In\nMoney Out',
          ),
          FieldDefinition(key: 'match_min_amount', label: 'Min Amount', type: FieldType.currency),
          FieldDefinition(key: 'match_max_amount', label: 'Max Amount', type: FieldType.currency),
          // For mapping types: the key being mapped (e.g. a channel SKU or a
          // merchant string).
          FieldDefinition(key: 'match_key', label: 'Match Key', type: FieldType.data),
          // Outcomes — what the rule decides. Which ones apply depends on
          // rule_type; unused ones stay blank.
          FieldDefinition(key: 'set_account', label: 'Account', type: FieldType.link, linkDocType: 'Account', options: 'Account'),
          FieldDefinition(key: 'set_party_type', label: 'Party Type', type: FieldType.select, options: '\nCustomer\nSupplier'),
          FieldDefinition(key: 'set_party', label: 'Party', type: FieldType.data),
          FieldDefinition(key: 'set_tax_code', label: 'Tax Code', type: FieldType.link, linkDocType: 'Tax Code', options: 'Tax Code'),
          FieldDefinition(key: 'set_item', label: 'Item', type: FieldType.link, linkDocType: 'Item', options: 'Item'),
          FieldDefinition(
            key: 'auto_action',
            label: 'Automatic Action',
            type: FieldType.select,
            options: '\nSuggest Only\nCreate Expense Draft',
            defaultValue: 'Suggest Only',
          ),
          // Accounting-affecting rules are surfaced for review and audited.
          FieldDefinition(key: 'affects_accounting', label: 'Affects Accounting', type: FieldType.check),
          // Where the rule came from, for the audit trail ("accepted by…").
          FieldDefinition(key: 'accepted_by', label: 'Accepted By', type: FieldType.data),
          FieldDefinition(key: 'source_pack', label: 'From Setup Pack', type: FieldType.data, readOnly: true),
          FieldDefinition(key: 'notes', label: 'Notes', type: FieldType.smallText),
        ],
      );

  static DocType _packApplication() => const DocType(
        id: 'Setup Pack Application',
        name: 'Setup Pack Application',
        module: _module,
        namingRule: 'PACKAPP-.####',
        fields: [
          FieldDefinition(key: 'pack_id', label: 'Pack', type: FieldType.data, required: true),
          FieldDefinition(key: 'pack_version', label: 'Version', type: FieldType.data, required: true),
          FieldDefinition(key: 'applied_at', label: 'Applied At', type: FieldType.data, readOnly: true),
          FieldDefinition(key: 'created_count', label: 'Created', type: FieldType.integer, readOnly: true, defaultValue: '0'),
          FieldDefinition(key: 'skipped_count', label: 'Already Present', type: FieldType.integer, readOnly: true, defaultValue: '0'),
          // The full recorded diff, JSON: [{action, doctype, id}, …].
          FieldDefinition(key: 'diff', label: 'What Changed', type: FieldType.longText, readOnly: true),
        ],
      );
}
