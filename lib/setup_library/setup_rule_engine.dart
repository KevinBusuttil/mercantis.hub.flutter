import 'package:mercantis_core/mercantis_core.dart';

import '../ledger/ledger_values.dart';

/// The rule engine's verdict for one input: which rule fired and a
/// plain-language explanation of WHY — every rule decision must be
/// explainable (design doc §3).
class RuleMatch {
  const RuleMatch({required this.rule, required this.explanation});

  final Document rule;
  final String explanation;

  String? get account => asNonEmpty(rule.payload['set_account']);
  String? get partyType => asNonEmpty(rule.payload['set_party_type']);
  String? get party => asNonEmpty(rule.payload['set_party']);
  String? get taxCode => asNonEmpty(rule.payload['set_tax_code']);
  String? get item => asNonEmpty(rule.payload['set_item']);
  bool get affectsAccounting => isTrue(rule.payload['affects_accounting']);
  String get provenance =>
      asNonEmpty(rule.payload['provenance']) ?? 'user-created';
}

/// The deterministic Setup Rule evaluator (design doc §3): same input, same
/// output, always. Rules run in priority order (lower first), ties broken
/// by id, first match wins — so the outcome never depends on storage order.
/// No AI anywhere in this path; AI may only ever SUGGEST a rule that a user
/// reviews into existence (provenance `AI-suggested`), after which execution
/// is exactly this code.
abstract final class SetupRuleEngine {
  /// Categorises one bank statement line against the active
  /// `Bank Categorisation` rules. All set conditions on a rule must hold.
  static RuleMatch? categoriseBankLine({
    required List<Document> rules,
    String? description,
    String? reference,
    required num amount, // signed: positive = money in
  }) {
    final candidates = _ordered(rules, 'Bank Categorisation');
    final desc = (description ?? '').toLowerCase();
    final ref = (reference ?? '').toLowerCase();

    for (final rule in candidates) {
      final p = rule.payload;
      final why = <String>[];

      final contains = asNonEmpty(p['match_contains'])?.toLowerCase();
      if (contains != null) {
        if (!desc.contains(contains)) continue;
        why.add('description contains "${p['match_contains']}"');
      }
      final refContains = asNonEmpty(p['match_reference'])?.toLowerCase();
      if (refContains != null) {
        if (!ref.contains(refContains)) continue;
        why.add('reference contains "${p['match_reference']}"');
      }
      final direction = asNonEmpty(p['match_direction']);
      if (direction == 'Money In') {
        if (amount <= 0) continue;
        why.add('money in');
      } else if (direction == 'Money Out') {
        if (amount >= 0) continue;
        why.add('money out');
      }
      final magnitude = amount.abs();
      final min = p['match_min_amount'];
      if (min != null && asNum(min) > 0) {
        if (magnitude < asNum(min)) continue;
        why.add('amount ≥ ${asNum(min)}');
      }
      final max = p['match_max_amount'];
      if (max != null && asNum(max) > 0) {
        if (magnitude > asNum(max)) continue;
        why.add('amount ≤ ${asNum(max)}');
      }
      if (why.isEmpty) continue; // a rule with no conditions matches nothing

      return RuleMatch(
        rule: rule,
        explanation:
            'Matched "${p['rule_name']}" because ${why.join(' and ')}.',
      );
    }
    return null;
  }

  /// Maps a key (channel SKU, merchant string) through `SKU Mapping` /
  /// `Supplier Mapping` rules: exact match on `match_key`,
  /// case-insensitive.
  static RuleMatch? mapKey({
    required List<Document> rules,
    required String ruleType,
    required String key,
  }) {
    final wanted = key.trim().toLowerCase();
    for (final rule in _ordered(rules, ruleType)) {
      final matchKey =
          asNonEmpty(rule.payload['match_key'])?.trim().toLowerCase();
      if (matchKey == null || matchKey != wanted) continue;
      return RuleMatch(
        rule: rule,
        explanation: 'Matched "${rule.payload['rule_name']}" because the '
            'key equals "${rule.payload['match_key']}".',
      );
    }
    return null;
  }

  /// Active rules of [ruleType], priority order, id tiebreak — the
  /// deterministic evaluation order everything above relies on.
  static List<Document> _ordered(List<Document> rules, String ruleType) {
    final filtered = [
      for (final r in rules)
        if (r.payload['rule_type'] == ruleType && isTrue(r.payload['active']))
          r,
    ]..sort((a, b) {
        final byPriority = asNum(a.payload['priority'])
            .compareTo(asNum(b.payload['priority']));
        return byPriority != 0 ? byPriority : a.id.compareTo(b.id);
      });
    return filtered;
  }
}
