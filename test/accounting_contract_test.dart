import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_hub_app/ledger/ledger_values.dart' show asNum, round2;
import 'package:mercantis_hub_app/ledger/ledger_values.dart' as values show isTrue;
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/books_harness.dart';

/// The shared Dart ↔ Rust accounting contract, Dart half.
///
/// `test/fixtures/accounting_contract/*.json` are the Team backend's
/// `tests/fixtures` (copied verbatim; `tool/check_accounting_contract.sh`
/// fails when the copies drift). The backend drives them through its command
/// API; this drives the SAME files through the Solo engine (local submit,
/// local derivation) and checks the same expectations. A posting change on
/// either side that makes the engines disagree fails here or there.
///
/// Server-only steps are skipped, not faked: role rejections (403; Solo has
/// no server roles) and `number` (Team official numbering). Rejections
/// (409/422) must also be rejected locally; the message wording may differ.
void main() {
  sqfliteFfiInit();
  final dir = Directory('test/fixtures/accounting_contract');
  final files = dir.listSync().whereType<File>().where((f) => f.path.endsWith('.json')).toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  for (final file in files) {
    final fixture = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    test('${p.basename(file.path)}: ${fixture['name']}', () async {
      final root = await Directory.systemTemp.createTemp('contract');
      final h = await BooksHarness.open(p.join(root.path, 'books.db'));
      try {
        await _Runner(h).run(fixture);
      } finally {
        await h.close();
        await root.delete(recursive: true);
      }
    });
  }
}

class _Runner {
  _Runner(this.h);
  final BooksHarness h;
  late String company;

  Future<void> run(Map<String, dynamic> fixture) async {
    company = (await h.engine.list('Company', userRoles: systemRoles)).single.id;
    final setup = (fixture['setup'] as Map?) ?? const {};
    // The contract's company is the server's default company settings
    // (CompanySettings::default): the same chart, but cash defaults to
    // `Cash` where a seeded Solo company uses `Bank`. (In Team the draft
    // carries the company's own accounts, filled on save, so the server never
    // falls back to its built-in chart for an app-made document.)
    await _settings({'default_cash_account': 'Cash', ...?(setup['settings'] as Map?)});
    for (final item in (setup['items'] as List?) ?? const []) {
      await _item(item as Map<String, dynamic>);
    }
    await _references(fixture['actions'] as List);

    var step = 0;
    for (final raw in fixture['actions'] as List) {
      final action = raw as Map<String, dynamic>;
      step++;
      final label = 'step $step (${action['comment'] ?? ''})';
      final status = action['expect_status'] as int? ?? 200;
      if (status == 403) continue; // server-enforced role: no Solo analogue
      Object? error;
      try {
        if (action['submit'] != null) {
          await _submit(action['submit'] as Map<String, dynamic>);
        } else if (action['cancel'] != null) {
          final c = action['cancel'] as Map<String, dynamic>;
          final doc = await h.engine.fetch('${c['doctype']}', '${c['document_id']}');
          expect(doc, isNotNull, reason: '$label: nothing to cancel');
          await h.engine.cancel(doc!, systemRoles);
        }
      } on DocumentEngineError catch (e) {
        error = e;
      } on StateError catch (e) {
        error = e;
      }
      if (status == 200) {
        expect(error, isNull,
            reason: '$label: rejected locally: ${_describe(error)}');
      } else {
        expect(error, isNotNull,
            reason: '$label: the server rejects this ($status), Solo accepted it');
      }
      final checks = action['expect'] as Map<String, dynamic>?;
      if (checks != null) await _check(checks, action, label);
    }
    final finalChecks = fixture['expect'] as Map<String, dynamic>?;
    if (finalChecks != null) await _check(finalChecks, const {}, 'final');
  }

  String _describe(Object? e) => e is DocumentEngineError
      ? e.validationErrors.map((v) => v.message).join('; ').ifEmpty(e.humanMessage)
      : '$e';

  Future<void> _settings(Map settings) async {
    if (settings.isEmpty) return;
    final c = (await h.engine.fetch('Company', company))!;
    settings.forEach((k, v) => c.payload['$k'] = v is bool ? (v ? 1 : 0) : v);
    await h.save(c);
  }

  Future<void> _item(Map<String, dynamic> item) async {
    final doc = Document(id: '${item['id']}', docType: 'Item', payload: {
      'item_code': item['id'],
      'item_name': item['id'],
      'item_type': item['item_type'] ?? 'Stock',
      'stock_uom': item['stock_uom'] ?? 'Nos',
      if (item['valuation_method'] != null) 'valuation_method': item['valuation_method'],
      for (final k in const ['inventory_account', 'cogs_account', 'stock_adjustment_account'])
        if (item[k] != null) k: item[k],
    });
    final uoms = (item['uoms'] as List?) ?? const [];
    if (uoms.isNotEmpty) {
      doc.children['uoms'] = [
        for (var i = 0; i < uoms.length; i++)
          itemLine('Item', Map<String, dynamic>.from(uoms[i] as Map), i, 'uoms'),
      ];
    }
    await h.save(doc);
  }

  /// The fixtures name parties and warehouses without creating them (the
  /// server does not need masters); the Solo engine validates links, so the
  /// masters are laid down first.
  Future<void> _references(List actions) async {
    final customers = <String>{}, suppliers = <String>{}, warehouses = <String>{};
    for (final raw in actions) {
      final s = (raw as Map)['submit'] as Map?;
      if (s == null) continue;
      final pl = s['payload'] as Map;
      if (pl['customer'] != null) customers.add('${pl['customer']}');
      if (pl['supplier'] != null) suppliers.add('${pl['supplier']}');
      if (pl['party'] != null) {
        (pl['payment_type'] == 'Pay' ? suppliers : customers).add('${pl['party']}');
      }
      for (final k in const ['set_warehouse', 'from_warehouse', 'to_warehouse']) {
        if (pl[k] != null) warehouses.add('${pl[k]}');
      }
      for (final line in (s['items'] as List?) ?? const []) {
        for (final k in const ['warehouse', 's_warehouse', 't_warehouse', 'source_warehouse', 'target_warehouse']) {
          if ((line as Map)[k] != null) warehouses.add('${line[k]}');
        }
      }
    }
    for (final c in customers) {
      if (await h.engine.fetch('Customer', c) == null) {
        await h.save(Document(id: c, docType: 'Customer',
            payload: {'customer_name': c, 'customer_type': 'Company'}));
      }
    }
    for (final s in suppliers) {
      if (await h.engine.fetch('Supplier', s) == null) {
        await h.save(Document(id: s, docType: 'Supplier', payload: {'supplier_name': s}));
      }
    }
    for (final w in warehouses) {
      if (await h.engine.fetch('Warehouse', w) == null) {
        await h.save(Document(id: w, docType: 'Warehouse', payload: {'warehouse_name': w}));
      }
    }
  }

  Future<void> _submit(Map<String, dynamic> cmd) async {
    final docType = '${cmd['doctype']}';
    final payload = <String, dynamic>{};
    final tables = <String, List>{};
    (cmd['payload'] as Map).forEach((k, v) {
      if (v is List) {
        tables['$k'] = v;
      } else {
        payload['$k'] = v;
      }
    });
    tables['items'] = (cmd['items'] as List?) ?? const [];
    // Representation adapters (same semantics, different wire shape):
    // the contract states tax as explicit rows, which the server checks
    // against the lines; Solo derives the rows from Tax Codes on save. Lay
    // the codes down and let Solo derive.
    final taxes = tables.remove('taxes');
    if (taxes != null && taxes.isNotEmpty) {
      for (final t in taxes.cast<Map>()) {
        final account = '${t['tax_account']}';
        if (await h.engine.fetch('Account', account) == null) {
          await h.save(Document(id: account, docType: 'Account', payload: {
            'account_name': account,
            'root_type': 'Liability',
            'account_type': 'Tax',
            'is_group': '0',
          }));
        }
        final code = '${t['tax_code']}';
        if (await h.engine.fetch('Tax Code', code) == null) {
          await h.save(Document(id: code, docType: 'Tax Code', payload: {
            'tax_code_name': code,
            'tax_type': t['tax_type'] ?? 'VAT',
            'rate': t['rate'],
            'tax_account': t['tax_account'],
          }));
        }
      }
      payload['tax_code'] = '${(taxes.first as Map)['tax_code']}';
    }
    // A till tender's kind is `mode_of_payment` on the wire, `tender_type`
    // in the Solo form (tenders never post on either side).
    tables['tenders'] = [
      for (final t in (tables['tenders'] ?? const []).cast<Map>())
        {...t, if (t['mode_of_payment'] != null) 'tender_type': t['mode_of_payment']},
    ];
    final doc = Document(id: '${cmd['document_id']}', docType: docType,
        company: company, payload: payload);
    tables.forEach((table, rows) {
      if (rows.isEmpty) return;
      doc.children[table] = [
        for (var i = 0; i < rows.length; i++)
          itemLine(docType, Map<String, dynamic>.from(rows[i] as Map), i, table),
      ];
    });
    await h.saveAndSubmit(doc);
  }

  Future<num> _sum(String docType, Map<String, dynamic> filters) async {
    num total = 0;
    for (final r in await h.engine.list(docType, filters: filters, userRoles: systemRoles)) {
      total += asNum(r.payload['debit']) - asNum(r.payload['credit']);
    }
    return round2(total);
  }

  Future<int> _count(String docType, Map<String, dynamic> filters) async =>
      (await h.engine.list(docType, filters: filters, userRoles: systemRoles)).length;

  void _near(Object? actual, Object? expected, String what) => expect(
      (asNum(actual) - asNum(expected)).abs() < 0.005, isTrue,
      reason: '$what is $actual, expected $expected');

  Future<void> _check(Map<String, dynamic> c, Map action, String label) async {
    for (final e in ((c['account_balances'] as Map?) ?? const {}).entries) {
      _near(await _sum('GL Entry', {'account': e.key}), e.value, '$label: ${e.key} balance');
    }
    for (final v in (c['voucher_accounts'] as List?) ?? const []) {
      _near(await _sum('GL Entry', {'account': v['account'], 'voucher_no': v['voucher']}),
          v['balance'], '$label: ${v['account']} on ${v['voucher']}');
    }
    for (final e in ((c['bins'] as Map?) ?? const {}).entries) {
      final at = '${e.key}'.indexOf('@');
      final item = '${e.key}'.substring(0, at), wh = '${e.key}'.substring(at + 1);
      final bin = await h.bin(item, wh);
      final want = e.value as Map;
      _near(bin?.payload['actual_qty'] ?? 0, want['qty'], '$label: bin ${e.key} qty');
      _near(bin?.payload['stock_value'] ?? 0, want['value'], '$label: bin ${e.key} value');
      if (want['rate'] != null) {
        _near(bin?.payload['valuation_rate'] ?? 0, want['rate'], '$label: bin ${e.key} rate');
      }
    }
    for (final e in ((c['gl_count'] as Map?) ?? const {}).entries) {
      expect(await _count('GL Entry', {'voucher_no': e.key}), e.value, reason: '$label: GL count ${e.key}');
    }
    for (final e in ((c['sle_count'] as Map?) ?? const {}).entries) {
      expect(await _count('Stock Ledger Entry', {'voucher_no': e.key}), e.value,
          reason: '$label: SLE count ${e.key}');
    }
    for (final e in ((c['settlement_count'] as Map?) ?? const {}).entries) {
      expect(await _count('Settlement', {'payment_voucher_no': e.key}), e.value,
          reason: '$label: settlement count ${e.key}');
    }
    for (final e in ((c['outstanding'] as Map?) ?? const {}).entries) {
      final at = '${e.key}'.indexOf('/');
      final doc = await h.engine.fetch('${e.key}'.substring(0, at), '${e.key}'.substring(at + 1));
      _near(doc?.payload['outstanding_amount'], e.value, '$label: outstanding ${e.key}');
    }
    if (c['docstatus'] != null) {
      final target = (action['submit'] ?? action['cancel']) as Map;
      final doc = await h.engine.fetch('${target['doctype']}', '${target['document_id']}');
      expect(doc?.docStatus, c['docstatus'], reason: '$label: docstatus');
    }
    for (final row in (c['gl_rows'] as List?) ?? const []) {
      final r = await h.engine.fetch('GL Entry', '${row['id']}');
      expect(r, isNotNull, reason: '$label: missing GL ${row['id']}');
      _fields(r!, row as Map, const {'account', 'currency'},
          const {'debit', 'credit', 'base_debit', 'base_credit', 'conversion_rate'}, label);
    }
    for (final row in (c['sle_rows'] as List?) ?? const []) {
      final r = await h.engine.fetch('Stock Ledger Entry', '${row['id']}');
      expect(r, isNotNull, reason: '$label: missing SLE ${row['id']}');
      _fields(r!, row as Map, const {'uom'}, const {'qty_change', 'valuation_rate'}, label);
    }
    for (final row in (c['party_rows'] as List?) ?? const []) {
      final r = await h.engine.fetch('${row['doctype']}', '${row['id']}');
      expect(r, isNotNull, reason: '$label: missing ${row['doctype']} ${row['id']}');
      _fields(r!, row as Map, const {'trans_type', 'due_date'},
          const {'amount', 'base_amount'}, label);
      // The server's party abstraction is `party`; Solo's subledgers name
      // the side (`customer` / `supplier`).
      if (row['party'] != null) {
        expect('${r.payload['party'] ?? r.payload['customer'] ?? r.payload['supplier']}',
            '${row['party']}', reason: '$label: ${r.id} party');
      }
      if (row['is_reversal'] != null) {
        expect(values.isTrue(r.payload['is_reversal']), row['is_reversal'], reason: '$label: is_reversal');
      }
    }
    for (final row in (c['tax_rows'] as List?) ?? const []) {
      final r = await h.engine.fetch('Tax Transaction', '${row['id']}');
      expect(r, isNotNull, reason: '$label: missing tax row ${row['id']}');
      _fields(r!, row as Map, const {'tax_type', 'tax', 'party_type', 'party'},
          const {'base_amount', 'tax_amount', 'rate'}, label);
    }
    for (final e in ((c['party_count'] as Map?) ?? const {}).entries) {
      final n = await _count('Customer Transaction', {'voucher_no': e.key}) +
          await _count('Supplier Transaction', {'voucher_no': e.key});
      expect(n, e.value, reason: '$label: party rows ${e.key}');
    }
    for (final e in ((c['tax_count'] as Map?) ?? const {}).entries) {
      expect(await _count('Tax Transaction', {'voucher_no': e.key}), e.value,
          reason: '$label: tax rows ${e.key}');
    }
    final gp = c['gross_profit'] as Map?;
    if (gp != null) {
      final income = -await _sum('GL Entry', {'account': gp['income']});
      final cogs = await _sum('GL Entry', {'account': gp['cogs']});
      _near(income - cogs, gp['value'], '$label: gross profit');
    }
  }

  void _fields(Document r, Map want, Set<String> strings, Set<String> numbers, String label) {
    for (final k in strings) {
      if (want[k] != null) expect('${r.payload[k]}', '${want[k]}', reason: '$label: ${r.id} $k');
    }
    for (final k in numbers) {
      if (want[k] != null) _near(r.payload[k], want[k], '$label: ${r.id} $k');
    }
  }
}

extension on String {
  String ifEmpty(String other) => this.isEmpty ? other : this;
}
