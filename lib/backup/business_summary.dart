import 'dart:convert';

import 'package:sqflite_common/sqflite.dart';

/// The business facts a backup records and a restore must reproduce exactly:
/// document counts, every account's GL balance, receivables, payables, stock
/// and bank/cash. Computed straight from the `documents` table (no engine,
/// no metadata), so the same code reads the live database at backup time and
/// the freshly installed file during restore verification, whatever schema
/// version the backup came from.
///
/// Money is summed in a fixed row order and stored as 2-decimal strings, so
/// identical books always produce identical summaries and any difference,
/// even one cent, is reported.
abstract final class BusinessSummary {
  static const _bankCashTypes = {'Bank', 'Cash'};

  static Future<Map<String, Object?>> compute(DatabaseExecutor db) async {
    final rows = await db.rawQuery(
        'SELECT id, doctype, docstatus, payload FROM documents ORDER BY doctype, id');

    final counts = <String, int>{};
    final submitted = <String, int>{};
    final accountType = <String, String>{};
    final balances = <String, num>{};
    final companies = <String>[];
    num debit = 0, credit = 0, ar = 0, ap = 0, stockValue = 0, stockQty = 0;

    final decoded = <(String, int, Map<String, dynamic>)>[];
    for (final r in rows) {
      final type = r['doctype'] as String;
      final status = (r['docstatus'] as int?) ?? 0;
      counts[type] = (counts[type] ?? 0) + 1;
      if (status == 1) submitted[type] = (submitted[type] ?? 0) + 1;
      Map<String, dynamic> payload;
      try {
        payload = Map<String, dynamic>.from(
            jsonDecode(r['payload'] as String) as Map);
      } catch (_) {
        payload = const {};
      }
      decoded.add((type, status, payload));
      if (type == 'Account') {
        accountType[r['id'] as String] = '${payload['account_type'] ?? ''}';
      }
      if (type == 'Company') {
        companies.add('${payload['company_name'] ?? r['id']}');
      }
    }

    for (final (type, status, p) in decoded) {
      switch (type) {
        case 'GL Entry':
          final d = _num(p['debit']);
          final c = _num(p['credit']);
          debit += d;
          credit += c;
          final account = '${p['account'] ?? ''}';
          balances[account] = (balances[account] ?? 0) + d - c;
        case 'Sales Invoice':
          if (status == 1) ar += _num(p['outstanding_amount']);
        case 'Purchase Invoice':
          if (status == 1) ap += _num(p['outstanding_amount']);
        case 'Bin':
          stockValue += _num(p['stock_value']);
          stockQty += _num(p['actual_qty']);
      }
    }

    num bankCash = 0;
    final sortedAccounts = balances.keys.toList()..sort();
    for (final a in sortedAccounts) {
      if (_bankCashTypes.contains(accountType[a])) bankCash += balances[a]!;
    }

    final attachmentCount = await _count(db, 'attachments');
    return {
      'companies': companies,
      'document_counts': _sorted(counts),
      'submitted_counts': _sorted(submitted),
      'gl_total_debit': money(debit),
      'gl_total_credit': money(credit),
      'account_balances': {
        for (final a in sortedAccounts) a: money(balances[a]!),
      },
      'receivables_outstanding': money(ar),
      'payables_outstanding': money(ap),
      'stock_value': money(stockValue),
      'stock_quantity': stockQty.toStringAsFixed(4),
      'bank_and_cash': money(bankCash),
      'attachments': attachmentCount,
    };
  }

  /// Human-readable differences between [expected] (from the backup) and
  /// [actual] (recomputed after restore). Empty when they agree exactly.
  static List<String> differences(
      Map<String, Object?> expected, Map<String, Object?> actual) {
    final out = <String>[];
    for (final key in expected.keys) {
      final e = expected[key];
      final a = actual[key];
      if (e is Map && a is Map) {
        final keys = {...e.keys, ...a.keys}.toList()..sort();
        for (final k in keys) {
          if ('${e[k]}' != '${a[k]}') {
            out.add('$key[$k]: expected ${e[k] ?? 'none'}, found ${a[k] ?? 'none'}');
          }
        }
      } else if (jsonEncode(e) != jsonEncode(a)) {
        out.add('$key: expected $e, found $a');
      }
    }
    return out;
  }

  /// Round half away from zero to cents and print with two decimals.
  static String money(num v) {
    final cents = (v * 100).abs().round() * (v < 0 ? -1 : 1);
    final sign = cents < 0 ? '-' : '';
    final c = cents.abs();
    return '$sign${c ~/ 100}.${(c % 100).toString().padLeft(2, '0')}';
  }

  static num _num(Object? v) {
    if (v is num) return v;
    if (v is String) return num.tryParse(v) ?? 0;
    return 0;
  }

  static Map<String, int> _sorted(Map<String, int> m) =>
      {for (final k in (m.keys.toList()..sort())) k: m[k]!};

  static Future<int> _count(DatabaseExecutor db, String table) async {
    final exists = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name=?", [table]);
    if (exists.isEmpty) return 0;
    final r = await db.rawQuery('SELECT COUNT(*) AS n FROM $table');
    return r.first['n'] as int;
  }
}
