import 'package:mercantis_core/mercantis_core.dart';

import '../ledger/ledger_values.dart';
import '../modules/accounting/opening_balance_builder.dart';
import 'take_on_templates.dart';

const _roles = {'System Manager'};

/// What will happen (or happened) to one source row.
enum TakeOnRowStatus {
  /// Valid and not in Atlas yet: will be created.
  create,

  /// Already in Atlas with the same values (a re-import): nothing to do.
  unchanged,

  /// An opening document from an earlier, interrupted run that was saved but
  /// not posted: it will be posted now.
  resume,

  /// A control-account line in the trial balance: not posted, reconciled
  /// against the open invoices / bills / stock instead.
  control,

  /// A zero line: nothing to post.
  skipped,

  /// In Atlas already with DIFFERENT values. Never overwritten.
  conflict,

  /// Invalid. The problem says what to fix in the file.
  rejected,
}

/// One source row and its verdict.
class TakeOnRow {
  TakeOnRow(this.line, this.values);

  /// 1-based line number in the source file (the header is line 1).
  final int line;
  final Map<String, String> values;
  TakeOnRowStatus status = TakeOnRowStatus.create;
  final List<String> problems = [];

  /// Atlas document id this row creates or matched.
  String? targetId;

  /// Amount in cents (money sections), for totals.
  int cents = 0;

  /// Quantity (opening stock).
  num qty = 0;

  void reject(String problem) {
    status = TakeOnRowStatus.rejected;
    problems.add(problem);
  }

  String v(String key) => (values[key] ?? '').trim();
}

/// The verdict for one section.
class SectionPlan {
  SectionPlan(this.template);
  final TakeOnTemplate template;
  final List<TakeOnRow> rows = [];

  /// Problems with the section as a whole (missing columns, out of balance,
  /// a control total that does not match).
  final List<String> problems = [];

  bool get provided => rows.isNotEmpty || problems.isNotEmpty;

  int count(TakeOnRowStatus s) => rows.where((r) => r.status == s).length;

  /// A posting section imports all-or-nothing.
  bool get blocked =>
      template.posts &&
      (problems.isNotEmpty ||
          rows.any((r) =>
              r.status == TakeOnRowStatus.rejected ||
              r.status == TakeOnRowStatus.conflict));

  /// Rows that were not accepted, for the rejected-records file.
  List<TakeOnRow> get notAccepted => [
        for (final r in rows)
          if (r.status == TakeOnRowStatus.rejected ||
              r.status == TakeOnRowStatus.conflict)
            r,
      ];

  /// The not-accepted rows as CSV with a `problem` column, so the user can
  /// fix them and re-import.
  String rejectedCsv() => CsvCodec.encode(
        headers: ['line', ...template.columns.map((c) => c.key), 'problem'],
        rows: [
          for (final r in notAccepted)
            {
              'line': '${r.line}',
              ...r.values,
              'problem': r.problems.join('; '),
            },
        ],
      );
}

/// A source file and how its columns map to a template.
class TakeOnInput {
  const TakeOnInput(this.csv, {this.mapping = const {}});
  final String csv;

  /// Template column key → header in the file. Unmapped columns are matched
  /// automatically by name or alias.
  final Map<String, String> mapping;
}

/// The dry-run result for a whole migration.
class TakeOnPlan {
  TakeOnPlan(this.openingDate, this.sections);
  final String openingDate;
  final Map<TakeOnSection, SectionPlan> sections;

  /// Problems that block every posting section (fiscal year, books lock).
  final List<String> problems = [];

  SectionPlan? operator [](TakeOnSection s) => sections[s];

  bool get canImport =>
      problems.isEmpty && sections.values.every((s) => !s.blocked);
}

/// What an import run did.
class TakeOnResult {
  final Map<TakeOnSection, int> created = {};
  final Map<TakeOnSection, int> posted = {};
  final List<String> errors = [];
}

/// Guided opening-data migration (M1.3): validates take-on CSVs against the
/// live books in a dry run, then imports them in dependency order through the
/// normal document engine, so every validation, posting rule, audit row and
/// the posting outbox apply exactly as for documents typed in by hand.
///
/// It orchestrates existing parts rather than adding an accounting path:
/// masters are ordinary documents, opening stock is a Material Receipt Stock
/// Entry, open receivables/payables are opening Sales/Purchase Invoices
/// against Opening Balance Equity (so payments settle them later), and the
/// trial balance becomes one [OpeningBalanceBuilder] journal.
///
/// Safe to re-run: every created document has an id derived from the source
/// key (`OPEN-AR:<invoice>`, `OPEN-STK:<item>@<warehouse>`, …). A re-run finds
/// it and reports "unchanged", posts a draft an interrupted run left behind,
/// or reports a conflict when the file now says something different. It never
/// posts the same opening balance twice and never overwrites.
///
/// Money must have at most 2 decimals and is handled in integer cents;
/// quantities at most 6 decimals. Nothing is rounded silently and no missing
/// value is filled in.
class OpeningTakeOn {
  OpeningTakeOn(this.engine);
  final DocumentEngine engine;

  static const equityAccount = 'Opening Balance Equity';

  static String customerId(String code) => code;
  static String supplierId(String code) => code;
  static String itemId(String code) => code;
  static String warehouseId(String code) => code;
  static String stockEntryId(String item, String warehouse) =>
      'OPEN-STK:$item@$warehouse';
  static String receivableId(String invoiceNo) => 'OPEN-AR:$invoiceNo';
  static String payableId(String supplier, String billNo) =>
      'OPEN-AP:$supplier:$billNo';
  static String journalId(String openingDate) => 'OPEN-GL:$openingDate';

  /// Automatic column mapping: exact key, label or alias, ignoring case,
  /// spaces and punctuation. Explicit [overrides] win.
  static Map<String, String> autoMap(TakeOnTemplate t, List<String> headers,
      [Map<String, String> overrides = const {}]) {
    String norm(String s) =>
        s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    final byNorm = {for (final h in headers) norm(h): h};
    final out = <String, String>{};
    for (final c in t.columns) {
      final explicit = overrides[c.key];
      if (explicit != null && headers.contains(explicit)) {
        out[c.key] = explicit;
        continue;
      }
      for (final candidate in [c.key, c.label, ...c.aliases]) {
        final h = byNorm[norm(candidate)];
        if (h != null) {
          out[c.key] = h;
          break;
        }
      }
    }
    return out;
  }

  // ------------------------------------------------------------------ plan

  /// Dry run: validate every supplied section against the books as they are
  /// now. Writes nothing.
  Future<TakeOnPlan> plan({
    required String openingDate,
    required Map<TakeOnSection, TakeOnInput> inputs,
  }) async {
    final sections = <TakeOnSection, SectionPlan>{};
    for (final t in TakeOnTemplate.all) {
      final sp = SectionPlan(t);
      sections[t.section] = sp;
      final input = inputs[t.section];
      if (input != null) _parse(sp, input);
    }
    final plan = TakeOnPlan(openingDate, sections);
    if (_isoDate(openingDate) == null) {
      plan.problems.add('The opening date must be a date (YYYY-MM-DD).');
      return plan;
    }
    await _checkPeriod(plan);

    final ctx = await _Context.load(engine)
      ..plannedCustomers = sections[TakeOnSection.customers]
      ..plannedSuppliers = sections[TakeOnSection.suppliers]
      ..plannedItems = sections[TakeOnSection.items]
      ..plannedWarehouses = sections[TakeOnSection.warehouses];
    _planCustomers(sections[TakeOnSection.customers]!, ctx);
    _planSuppliers(sections[TakeOnSection.suppliers]!, ctx);
    _planWarehouses(sections[TakeOnSection.warehouses]!, ctx);
    _planItems(sections[TakeOnSection.items]!, ctx);
    await _planStock(sections[TakeOnSection.openingStock]!, ctx, openingDate);
    await _planOpenInvoices(sections[TakeOnSection.receivables]!, ctx,
        openingDate, receivable: true);
    await _planOpenInvoices(sections[TakeOnSection.payables]!, ctx,
        openingDate, receivable: false);
    await _planTrialBalance(plan, ctx);
    _planBank(sections[TakeOnSection.bankBalances]!, ctx);
    return plan;
  }

  void _parse(SectionPlan sp, TakeOnInput input) {
    final DecodedTable table;
    try {
      var text = input.csv;
      if (text.startsWith('﻿')) text = text.substring(1);
      table = CsvCodec.decode(text);
    } catch (e) {
      sp.problems.add('The file is not valid CSV: $e');
      return;
    }
    final widths = _recordWidths(input.csv);
    final map = autoMap(sp.template, table.headers, input.mapping);
    for (final c in sp.template.columns) {
      if (c.required && !map.containsKey(c.key)) {
        sp.problems.add('No column for "${c.label}". Map one of the file\'s '
            'columns to it, or add a "${c.key}" column.');
      }
    }
    if (sp.problems.isNotEmpty) return;
    for (var i = 0; i < table.rows.length; i++) {
      final raw = table.rows[i];
      if (raw.values.every((v) => v.trim().isEmpty)) continue;
      final row = TakeOnRow(i + 2, {
        for (final e in map.entries) e.key: (raw[e.value] ?? '').trim(),
      });
      final width = i + 1 < widths.length ? widths[i + 1] : 0;
      if (width > table.headers.length) {
        // The CSV decoder drops surplus fields, so "1,234.00" unquoted would
        // otherwise import as 1.
        row.reject('Line ${i + 2} has $width values but the header has '
            '${table.headers.length}. Put quotes around a value that '
            'contains a comma, or remove the thousands separator.');
      }
      for (final c in sp.template.columns) {
        if (c.required && row.v(c.key).isEmpty) {
          row.reject('${c.label} is missing.');
        }
      }
      sp.rows.add(row);
    }
  }

  /// The number of fields in each CSV record, using the same quoting and
  /// line rules as [CsvCodec.decode] (one record per line break outside
  /// quotes).
  static List<int> _recordWidths(String text) {
    final widths = <int>[];
    var fields = 1, inQuotes = false, pending = false;
    for (var i = 0; i < text.length; i++) {
      final ch = text[i];
      if (inQuotes) {
        if (ch == '"') {
          if (i + 1 < text.length && text[i + 1] == '"') {
            i++;
          } else {
            inQuotes = false;
          }
        }
        continue;
      }
      pending = true;
      if (ch == '"') {
        inQuotes = true;
      } else if (ch == ',') {
        fields++;
      } else if (ch == '\n') {
        widths.add(fields);
        fields = 1;
        pending = false;
      }
    }
    if (pending) widths.add(fields);
    return widths;
  }

  Future<void> _checkPeriod(TakeOnPlan plan) async {
    final date = _isoDate(plan.openingDate)!;
    final years = await engine.list('Fiscal Year', userRoles: _roles);
    if (years.isNotEmpty &&
        !years.any((y) {
          final s = _isoDate('${y.payload['year_start_date'] ?? ''}');
          final e = _isoDate('${y.payload['year_end_date'] ?? ''}');
          return s != null && e != null && !date.isBefore(s) && !date.isAfter(e);
        })) {
      plan.problems.add('No financial year covers the opening date '
          '${plan.openingDate}. Create that year first.');
    }
    for (final c in await engine.list('Company', userRoles: _roles)) {
      final lock = _isoDate('${c.payload['books_lock_date'] ?? ''}');
      if (lock != null && !date.isAfter(lock)) {
        plan.problems.add('The books are locked through '
            '${c.payload['books_lock_date']}. Choose a later opening date or '
            'move the lock date.');
      }
    }
  }

  /// Rejects a second row with the same key, pointing at the first.
  void _dedupe(SectionPlan sp, String Function(TakeOnRow) key, String what) {
    final seen = <String, int>{};
    for (final r in sp.rows) {
      if (r.status == TakeOnRowStatus.rejected) continue;
      final k = key(r).toLowerCase();
      final first = seen[k];
      if (first != null) {
        r.reject('Duplicate $what (same as line $first).');
      } else {
        seen[k] = r.line;
      }
    }
  }

  bool _validCode(TakeOnRow r, String key, String label) {
    final code = r.v(key);
    if (code.isEmpty) return false;
    if (RegExp(r'[/?#\\]').hasMatch(code) || code.length > 140) {
      r.reject('$label "$code" contains / ? # or \\ (or is too long). '
          'Use letters, digits, spaces, - or _.');
      return false;
    }
    return true;
  }

  /// Compare the file's non-blank values to an existing record. Blank cells
  /// never count as a difference (a blank never overwrites).
  static const _numericMatchFields = {'standard_rate', 'standard_buying_rate'};

  void _matchExisting(TakeOnRow r, Document existing, Map<String, String> fields,
      String what) {
    final diffs = <String>[];
    fields.forEach((fileKey, payloadKey) {
      final want = r.v(fileKey);
      if (want.isEmpty) return;
      final have = '${existing.payload[payloadKey] ?? ''}'.trim();
      // Only amounts compare as numbers ("12" = "12.00"). Identifiers and
      // other text compare as text, so "00123" and "123" differ.
      final numWant =
          _numericMatchFields.contains(payloadKey) ? num.tryParse(want) : null;
      final numHave =
          _numericMatchFields.contains(payloadKey) ? num.tryParse(have) : null;
      final same = numWant != null && numHave != null
          ? numWant == numHave
          : want.toLowerCase() == have.toLowerCase();
      if (!same) diffs.add('$payloadKey is "$have" in Atlas, "$want" in the file');
    });
    r.targetId = existing.id;
    if (diffs.isEmpty) {
      r.status = TakeOnRowStatus.unchanged;
    } else {
      r.status = TakeOnRowStatus.conflict;
      r.problems.add('$what ${existing.id} already exists with different '
          'values (${diffs.join('; ')}). Atlas never overwrites it: change '
          'it in Atlas or correct the file.');
    }
  }

  void _planCustomers(SectionPlan sp, _Context ctx) {
    for (final r in sp.rows) {
      if (r.status == TakeOnRowStatus.rejected) continue;
      if (!_validCode(r, 'customer_code', 'Customer code')) continue;
      final type = r.v('customer_type');
      if (type.isNotEmpty && !const {'company', 'individual'}.contains(type.toLowerCase())) {
        r.reject('Type must be Company or Individual, not "$type".');
      }
    }
    _dedupe(sp, (r) => r.v('customer_code'), 'customer code');
    for (final r in sp.rows) {
      if (r.status == TakeOnRowStatus.rejected) continue;
      final id = customerId(r.v('customer_code'));
      r.targetId = id;
      final existing = ctx.customers[id];
      if (existing != null) {
        _matchExisting(r, existing, const {
          'customer_name': 'customer_name',
          'customer_type': 'customer_type',
          'email': 'email',
          'tax_id': 'tax_id',
          'country': 'country',
        }, 'Customer');
      }
    }
  }

  void _planSuppliers(SectionPlan sp, _Context ctx) {
    for (final r in sp.rows) {
      if (r.status == TakeOnRowStatus.rejected) continue;
      if (!_validCode(r, 'supplier_code', 'Supplier code')) continue;
      final type = r.v('supplier_type');
      if (type.isNotEmpty && !const {'company', 'individual'}.contains(type.toLowerCase())) {
        r.reject('Type must be Company or Individual, not "$type".');
      }
    }
    _dedupe(sp, (r) => r.v('supplier_code'), 'supplier code');
    for (final r in sp.rows) {
      if (r.status == TakeOnRowStatus.rejected) continue;
      final id = supplierId(r.v('supplier_code'));
      r.targetId = id;
      final existing = ctx.suppliers[id];
      if (existing != null) {
        _matchExisting(r, existing, const {
          'supplier_name': 'supplier_name',
          'supplier_type': 'supplier_type',
          'tax_id': 'tax_id',
          'country': 'country',
        }, 'Supplier');
      }
    }
  }

  void _planWarehouses(SectionPlan sp, _Context ctx) {
    for (final r in sp.rows) {
      if (r.status == TakeOnRowStatus.rejected) continue;
      _validCode(r, 'warehouse_code', 'Warehouse code');
    }
    _dedupe(sp, (r) => r.v('warehouse_code'), 'warehouse code');
    for (final r in sp.rows) {
      if (r.status == TakeOnRowStatus.rejected) continue;
      final id = warehouseId(r.v('warehouse_code'));
      r.targetId = id;
      final existing = ctx.warehouses[id];
      if (existing != null) {
        _matchExisting(r, existing, const {'warehouse_name': 'warehouse_name'},
            'Warehouse');
      }
    }
  }

  void _planItems(SectionPlan sp, _Context ctx) {
    for (final r in sp.rows) {
      if (r.status == TakeOnRowStatus.rejected) continue;
      if (!_validCode(r, 'item_code', 'Item code')) continue;
      final type = r.v('item_type').toLowerCase();
      if (type != 'stock' && type != 'service') {
        r.reject('Type must be Stock or Service, not "${r.v('item_type')}".');
      }
      for (final k in const ['selling_price', 'buying_price']) {
        final raw = r.v(k);
        if (raw.isEmpty) continue;
        final c = parseCents(raw);
        if (c == null || c < 0) {
          r.reject('${k == 'selling_price' ? 'Selling' : 'Buying'} price '
              '"$raw" must be a number ≥ 0 with at most 2 decimals and no '
              'thousands separators.');
        }
      }
      final vm = r.v('valuation_method');
      if (vm.isNotEmpty &&
          !const {'moving average', 'fifo'}.contains(vm.toLowerCase())) {
        r.reject('Valuation method must be Moving Average or FIFO.');
      }
    }
    _dedupe(sp, (r) => r.v('item_code'), 'item code');
    for (final r in sp.rows) {
      if (r.status == TakeOnRowStatus.rejected) continue;
      final id = itemId(r.v('item_code'));
      r.targetId = id;
      final existing = ctx.items[id];
      if (existing != null) {
        _matchExisting(r, existing, const {
          'item_name': 'item_name',
          'item_type': 'item_type',
          'uom': 'stock_uom',
          'selling_price': 'standard_rate',
          'buying_price': 'standard_buying_rate',
          'valuation_method': 'valuation_method',
        }, 'Item');
      }
    }
  }

  Future<void> _planStock(
      SectionPlan sp, _Context ctx, String openingDate) async {
    final itemsInFile = _accepted(ctx.plannedItems);
    final whInFile = _accepted(ctx.plannedWarehouses);
    for (final r in sp.rows) {
      if (r.status == TakeOnRowStatus.rejected) continue;
      final item = r.v('item_code');
      final wh = r.v('warehouse_code');
      final itemDoc = ctx.items[item];
      final fileType = itemsInFile[item]?.v('item_type').toLowerCase();
      final isStock = fileType != null
          ? fileType == 'stock'
          : '${itemDoc?.payload['item_type'] ?? 'Stock'}' == 'Stock';
      if (itemDoc == null && fileType == null) {
        r.reject('Item "$item" is not in Atlas or in the items file.');
      } else if (!isStock) {
        r.reject('Item "$item" is a Service item; only Stock items carry stock.');
      }
      if (!ctx.warehouses.containsKey(wh) && !whInFile.containsKey(wh)) {
        r.reject('Warehouse "$wh" is not in Atlas or in the warehouses file.');
      }
      final qty = parseQty(r.v('qty'));
      if (qty == null || qty <= 0) {
        r.reject('Quantity "${r.v('qty')}" must be a number above 0 with at '
            'most 6 decimals.');
      } else {
        r.qty = qty;
      }
      final cents = parseCents(r.v('value'));
      if (cents == null || cents < 0) {
        r.reject('Value "${r.v('value')}" must be a number ≥ 0 with at most 2 '
            'decimals and no thousands separators.');
      } else {
        r.cents = cents;
      }
    }
    for (final r in sp.rows) {
      // '@' joins item and warehouse in the opening id; allowing it would let
      // two different pairs share one id.
      if (r.v('item_code').contains('@') ||
          r.v('warehouse_code').contains('@')) {
        r.reject('An item or warehouse code containing "@" cannot be given '
            'opening stock here. Rename it in Atlas first.');
      }
    }
    _dedupe(sp, (r) => '${r.v('item_code')}@${r.v('warehouse_code')}',
        'item and warehouse');
    // Positions with stock movements on or after the opening date. A
    // backdated opening balance would not re-cost those movements, so their
    // saved valuation and cost of sales would stay wrong even when the
    // position is empty today.
    final movedSince = <String, String>{};
    if (sp.rows.isNotEmpty) {
      for (final d
          in await engine.list('Stock Ledger Entry', userRoles: _roles)) {
        final p = d.payload;
        // An unreadable date counts as a movement: it cannot be shown to
        // fall before the opening date.
        final day = _dayOf(p['posting_date']);
        if (day != null && day.compareTo(openingDate) < 0) continue;
        movedSince.putIfAbsent('${p['item']}@${p['warehouse']}',
            () => '${p['voucher_type']} ${p['voucher_no']}');
      }
    }
    for (final r in sp.rows) {
      if (r.status == TakeOnRowStatus.rejected) continue;
      final item = r.v('item_code');
      final wh = r.v('warehouse_code');
      final id = stockEntryId(item, wh);
      r.targetId = id;
      final existing = await engine.fetch('Stock Entry', id);
      if (existing != null) {
        final lines = existing.children['items'] ?? const [];
        final same = lines.length == 1 &&
            '${existing.payload['posting_date']}' == openingDate &&
            asNum(lines.first.payload['qty']) == r.qty &&
            _cents(asNum(lines.first.payload['qty']) *
                    asNum(lines.first.payload['valuation_rate'])) ==
                r.cents;
        if (!same) {
          r.status = TakeOnRowStatus.conflict;
          r.problems.add('Opening stock for $item in $wh was already imported '
              'with a different quantity, value or opening date. Cancel $id '
              'in Atlas first if the file is right.');
        } else {
          r.status = existing.docStatus == 1
              ? TakeOnRowStatus.unchanged
              : existing.docStatus == 0
                  ? TakeOnRowStatus.resume
                  : TakeOnRowStatus.conflict;
          if (r.status == TakeOnRowStatus.conflict) {
            r.problems.add('$id was cancelled. Amend or delete it in Atlas '
                'before importing it again.');
          }
          // A draft left by an interrupted import has no ledger rows yet,
          // so movements since then would sit after it uncosted.
          final moved = movedSince['$item@$wh'];
          if (r.status == TakeOnRowStatus.resume && moved != null) {
            r.status = TakeOnRowStatus.conflict;
            r.problems.add('$item in $wh has had stock movements on or after '
                'the opening date since $id was saved as a draft (for example '
                '$moved). Delete the draft $id in Atlas and record the '
                'opening stock as a stock adjustment instead.');
          }
        }
        continue;
      }
      final moved = movedSince['$item@$wh'];
      if (moved != null) {
        r.reject('$item in $wh already has stock movements on or after the '
            'opening date (for example $moved). Opening stock cannot be '
            'backdated under them; record it as a stock adjustment in Atlas, '
            'or choose an opening date after those movements.');
        continue;
      }
      final bin = await engine.fetch('Bin', 'BIN-$item-$wh');
      final onHand = asNum(bin?.payload['actual_qty']);
      if (onHand != 0) {
        r.reject('Atlas already holds $onHand of $item in $wh from other '
            'transactions. Opening stock goes into an empty position only, '
            'so it is never counted twice.');
      }
    }
  }

  Future<void> _planOpenInvoices(SectionPlan sp, _Context ctx,
      String openingDate, {required bool receivable}) async {
    final partyKey = receivable ? 'customer_code' : 'supplier_code';
    final noKey = receivable ? 'invoice_no' : 'bill_no';
    final dateKey = receivable ? 'invoice_date' : 'bill_date';
    final docType = receivable ? 'Sales Invoice' : 'Purchase Invoice';
    final parties = receivable ? ctx.customers : ctx.suppliers;
    final partiesInFile =
        _accepted(receivable ? ctx.plannedCustomers : ctx.plannedSuppliers);
    final opening = _isoDate(openingDate);
    for (final r in sp.rows) {
      if (r.status == TakeOnRowStatus.rejected) continue;
      if (!_validCode(r, noKey, receivable ? 'Invoice number' : 'Bill number')) {
        continue;
      }
      final party = r.v(partyKey);
      if (!parties.containsKey(party) && !partiesInFile.containsKey(party)) {
        r.reject('${receivable ? 'Customer' : 'Supplier'} "$party" is not in '
            'Atlas, or was rejected in the ${receivable ? 'customers' : 'suppliers'} file.');
      }
      final date = _isoDate(r.v(dateKey));
      if (date == null) {
        r.reject('Date "${r.v(dateKey)}" must be YYYY-MM-DD.');
      } else if (opening != null && date.isAfter(opening)) {
        r.reject('Dated after the opening date: enter it in Atlas as a normal '
            '${receivable ? 'invoice' : 'bill'} instead.');
      }
      final due = r.v('due_date');
      if (due.isNotEmpty) {
        final d = _isoDate(due);
        if (d == null) {
          r.reject('Due date "$due" must be YYYY-MM-DD.');
        } else if (date != null && d.isBefore(date)) {
          r.reject('Due date is before the ${receivable ? 'invoice' : 'bill'} date.');
        }
      }
      final cents = parseCents(r.v('outstanding'));
      if (cents == null) {
        r.reject('Amount "${r.v('outstanding')}" must be a number with at '
            'most 2 decimals and no thousands separators.');
      } else if (cents <= 0) {
        r.reject('Amount must be above zero. Bring a '
            '${receivable ? 'customer credit' : 'supplier debit'} balance over '
            'as a credit note after opening, so it is not netted silently.');
      } else {
        r.cents = cents;
      }
    }
    if (!receivable) {
      for (final r in sp.rows) {
        // ':' joins supplier and bill number in the opening id.
        if (r.v(partyKey).contains(':')) {
          r.reject('A supplier code containing ":" cannot carry an opening '
              'bill here. Rename it in Atlas first.');
        }
      }
    }
    _dedupe(
        sp,
        (r) => receivable ? r.v(noKey) : '${r.v(partyKey)}:${r.v(noKey)}',
        receivable ? 'invoice number' : 'bill number for this supplier');
    for (final r in sp.rows) {
      if (r.status == TakeOnRowStatus.rejected) continue;
      final id = receivable
          ? receivableId(r.v(noKey))
          : payableId(r.v(partyKey), r.v(noKey));
      r.targetId = id;
      final existing = await engine.fetch(docType, id);
      if (existing == null) continue;
      final partyField = receivable ? 'customer' : 'supplier';
      final due = r.v('due_date').isEmpty ? r.v(dateKey) : r.v('due_date');
      final same = '${existing.payload[partyField]}' == r.v(partyKey) &&
          _cents(asNum(existing.payload['grand_total'])) == r.cents &&
          '${existing.payload['posting_date']}' == openingDate &&
          '${existing.payload['due_date']}' == due;
      if (!same) {
        r.status = TakeOnRowStatus.conflict;
        r.problems.add('$id was already imported with a different party, '
            'amount, opening date or due date. Atlas will not post it twice; '
            'correct it in Atlas instead.');
      } else if (existing.docStatus == 1) {
        r.status = TakeOnRowStatus.unchanged;
      } else if (existing.docStatus == 0) {
        r.status = TakeOnRowStatus.resume;
      } else {
        r.status = TakeOnRowStatus.conflict;
        r.problems.add('$id was cancelled in Atlas. Amend it there instead.');
      }
    }
  }

  Future<void> _planTrialBalance(TakeOnPlan plan, _Context ctx) async {
    final sp = plan.sections[TakeOnSection.trialBalance]!;
    var debit = 0, credit = 0;
    for (final r in sp.rows) {
      if (r.status == TakeOnRowStatus.rejected) continue;
      final account = ctx.resolveAccount(r.v('account'));
      if (account == null) {
        r.reject('Account "${r.v('account')}" is not in the Atlas chart of '
            'accounts. Create it (or use its exact Atlas name) first.');
        continue;
      }
      if (isTrue(account.payload['is_group'])) {
        r.reject('"${account.id}" is a group account; use one of its '
            'sub-accounts.');
        continue;
      }
      r.targetId = account.id;
      final d = r.v('debit').isEmpty ? 0 : parseCents(r.v('debit'));
      final c = r.v('credit').isEmpty ? 0 : parseCents(r.v('credit'));
      if (d == null || c == null || d < 0 || c < 0) {
        r.reject('Debit and credit must be positive numbers with at most 2 '
            'decimals and no thousands separators.');
        continue;
      }
      if (d != 0 && c != 0) {
        r.reject('Put the balance in debit OR credit, not both.');
        continue;
      }
      r.cents = d - c; // net debit
      debit += d;
      credit += c;
      if (d == 0 && c == 0) {
        r.status = TakeOnRowStatus.skipped;
        continue;
      }
      if (_controlTypes.contains('${account.payload['account_type'] ?? ''}')) {
        r.status = TakeOnRowStatus.control;
      }
    }
    _dedupeAccounts(sp);
    if (sp.rows.isEmpty) return;
    if (debit != credit) {
      sp.problems.add('The trial balance does not balance: debits '
          '${formatCents(debit)}, credits ${formatCents(credit)}, difference '
          '${formatCents(debit - credit)}. Atlas will not invent the missing '
          'amount; correct the file.');
    }

    // Control accounts must equal the documents that will carry them.
    int controlTotal(String type) => [
          for (final r in sp.rows)
            if (r.status == TakeOnRowStatus.control &&
                '${ctx.accounts[r.targetId]?.payload['account_type']}' == type)
              r.cents,
        ].fold(0, (a, b) => a + b);
    int sectionTotal(TakeOnSection s) => [
          for (final r in plan.sections[s]!.rows)
            if (r.status != TakeOnRowStatus.rejected) r.cents,
        ].fold(0, (a, b) => a + b);
    void requireMatch(String type, TakeOnSection s, String label, int sign) {
      final tb = controlTotal(type) * sign;
      final docs = sectionTotal(s);
      if (tb != 0 && plan.sections[s]!.blocked) {
        // Posting the journal without the detail would leave the control
        // account short, so the two import together or not at all.
        sp.problems.add('The ${TakeOnTemplate.of(s).title.toLowerCase()} '
            'file has rows to fix, and the trial balance carries '
            '${formatCents(tb)} of $label that only that file can post. Fix '
            'it first; the trial balance imports with it.');
        return;
      }
      if (tb == docs) return;
      sp.problems.add(plan.sections[s]!.rows.isEmpty && tb != 0
          ? 'The trial balance shows ${formatCents(tb)} of $label but no '
              '${TakeOnTemplate.of(s).title.toLowerCase()} file was given. '
              'Import them, or that balance would be lost.'
          : '$label: the trial balance says ${formatCents(tb)} but the '
              '${TakeOnTemplate.of(s).title.toLowerCase()} add up to '
              '${formatCents(docs)} (difference ${formatCents(tb - docs)}). '
              'Find the difference in the old system first.');
    }

    requireMatch('Receivable', TakeOnSection.receivables, 'receivables', 1);
    requireMatch('Payable', TakeOnSection.payables, 'payables', -1);
    requireMatch('Stock', TakeOnSection.openingStock, 'stock', 1);

    // Never a second opening journal.
    final id = journalId(plan.openingDate);
    final ours = await engine.fetch('Journal Entry', id);
    for (final je in await engine.list('Journal Entry', userRoles: _roles)) {
      if (je.id == id || je.docStatus != 1) continue;
      if ('${je.payload['voucher_type'] ?? ''}' == 'Opening Entry') {
        sp.problems.add('Opening journal ${je.id} is already posted. Atlas '
            'will not post opening balances twice: cancel it first, or leave '
            'the trial balance file out.');
      }
    }
    if (ours != null) {
      final expected = _journalLines(sp);
      final actual = <String, int>{};
      for (final row in ours.children['accounts'] ?? const <ChildRow>[]) {
        final a = '${row.payload['account']}';
        if (a == equityAccount) continue;
        actual[a] = (actual[a] ?? 0) +
            _cents(asNum(row.payload['debit'])) -
            _cents(asNum(row.payload['credit']));
      }
      final same = expected.length == actual.length &&
          expected.entries.every((e) => actual[e.key] == e.value);
      for (final r in sp.rows) {
        if (r.status != TakeOnRowStatus.create) continue;
        if (!same) {
          r.status = TakeOnRowStatus.conflict;
          r.problems.add('The opening journal $id was already imported with '
              'different balances.');
        } else {
          r.status = ours.docStatus == 1
              ? TakeOnRowStatus.unchanged
              : ours.docStatus == 0
                  ? TakeOnRowStatus.resume
                  : TakeOnRowStatus.conflict;
        }
      }
    }
  }

  void _dedupeAccounts(SectionPlan sp) {
    final seen = <String, int>{};
    for (final r in sp.rows) {
      final id = r.targetId;
      if (id == null || r.status == TakeOnRowStatus.rejected) continue;
      final first = seen[id];
      if (first != null) {
        r.reject('Account appears twice (also line $first).');
      } else {
        seen[id] = r.line;
      }
    }
  }

  void _planBank(SectionPlan sp, _Context ctx) {
    for (final r in sp.rows) {
      if (r.status == TakeOnRowStatus.rejected) continue;
      final account = ctx.resolveAccount(r.v('account'));
      if (account == null) {
        r.reject('Account "${r.v('account')}" is not in the Atlas chart.');
        continue;
      }
      if (!const {'Bank', 'Cash'}
          .contains('${account.payload['account_type'] ?? ''}')) {
        r.reject('"${account.id}" is not a bank or cash account.');
        continue;
      }
      r.targetId = account.id;
      final c = parseCents(r.v('statement_balance'));
      if (c == null) {
        r.reject('Balance must be a number with at most 2 decimals.');
        continue;
      }
      r.cents = c;
      r.status = TakeOnRowStatus.control;
    }
    _dedupeAccounts(sp);
  }

  static const _controlTypes = {'Receivable', 'Payable', 'Stock'};

  Map<String, int> _journalLines(SectionPlan sp) => {
        for (final r in sp.rows)
          if ((r.status == TakeOnRowStatus.create ||
                  r.status == TakeOnRowStatus.unchanged ||
                  r.status == TakeOnRowStatus.resume) &&
              r.targetId != null)
            r.targetId!: r.cents,
      };

  /// Rows of a master section that will exist after import, by code.
  static Map<String, TakeOnRow> _accepted(SectionPlan? sp) => {
        if (sp != null)
          for (final r in sp.rows)
            if (r.status != TakeOnRowStatus.rejected &&
                r.status != TakeOnRowStatus.conflict &&
                r.targetId != null)
              r.targetId!: r,
      };

  // ---------------------------------------------------------------- commit

  /// Re-validate against the books as they are now, then import every
  /// section that is not blocked, in dependency order. A posting section with
  /// any rejected or conflicting row is skipped whole; masters import their
  /// valid rows. Each document is saved and posted through the engine.
  Future<(TakeOnPlan, TakeOnResult)> commit({
    required String openingDate,
    required Map<TakeOnSection, TakeOnInput> inputs,
  }) async {
    final plan = await this.plan(openingDate: openingDate, inputs: inputs);
    final result = TakeOnResult();
    if (plan.problems.isNotEmpty) {
      result.errors.addAll(plan.problems);
      return (plan, result);
    }
    final company = await _companyId();

    Future<void> each(TakeOnSection s,
        Future<void> Function(TakeOnRow r) create) async {
      final sp = plan.sections[s]!;
      if (sp.blocked) return;
      for (final r in sp.rows) {
        if (r.status != TakeOnRowStatus.create &&
            r.status != TakeOnRowStatus.resume) {
          continue;
        }
        try {
          await create(r);
          if (r.status == TakeOnRowStatus.create) {
            result.created[s] = (result.created[s] ?? 0) + 1;
          } else {
            result.posted[s] = (result.posted[s] ?? 0) + 1;
          }
        } catch (e) {
          final msg = e is DocumentEngineError ? e.humanMessage : '$e';
          r.problems.add('Not imported: $msg');
          result.errors.add('${TakeOnTemplate.of(s).title} line ${r.line}: $msg');
        }
      }
    }

    await each(TakeOnSection.customers, (r) => engine.save(
        Document(id: r.targetId!, docType: 'Customer', company: company, payload: {
          'customer_name': r.v('customer_name'),
          if (r.v('customer_type').isNotEmpty)
            'customer_type': _title(r.v('customer_type')),
          if (r.v('email').isNotEmpty) 'email': r.v('email'),
          if (r.v('tax_id').isNotEmpty) 'tax_id': r.v('tax_id'),
          if (r.v('country').isNotEmpty) 'country': r.v('country'),
        }),
        _roles));
    await each(TakeOnSection.suppliers, (r) => engine.save(
        Document(id: r.targetId!, docType: 'Supplier', company: company, payload: {
          'supplier_name': r.v('supplier_name'),
          if (r.v('supplier_type').isNotEmpty)
            'supplier_type': _title(r.v('supplier_type')),
          if (r.v('tax_id').isNotEmpty) 'tax_id': r.v('tax_id'),
          if (r.v('country').isNotEmpty) 'country': r.v('country'),
        }),
        _roles));
    await each(TakeOnSection.warehouses, (r) => engine.save(
        Document(id: r.targetId!, docType: 'Warehouse', company: company, payload: {
          'warehouse_name': r.v('warehouse_name'),
          if (company != null) 'company': company,
        }),
        _roles));
    await each(TakeOnSection.items, (r) async {
      final uom = r.v('uom');
      if (await engine.fetch('UOM', uom) == null) {
        await engine.save(
            Document(id: uom, docType: 'UOM', payload: {'uom_name': uom}),
            _roles);
      }
      final stock = r.v('item_type').toLowerCase() == 'stock';
      await engine.save(
          Document(id: r.targetId!, docType: 'Item', company: company, payload: {
            'item_code': r.v('item_code'),
            'item_name': r.v('item_name'),
            'item_type': stock ? 'Stock' : 'Service',
            'stock_uom': uom,
            if (r.v('selling_price').isNotEmpty)
              'standard_rate': parseCents(r.v('selling_price'))! / 100,
            if (r.v('buying_price').isNotEmpty)
              'standard_buying_rate': parseCents(r.v('buying_price'))! / 100,
            if (stock)
              'valuation_method': r.v('valuation_method').toLowerCase() == 'fifo'
                  ? 'FIFO'
                  : 'Moving Average',
          }),
          _roles);
    });

    await each(TakeOnSection.openingStock, (r) async {
      var doc = await engine.fetch('Stock Entry', r.targetId!);
      if (doc == null) {
        final value = r.cents / 100;
        doc = Document(
            id: r.targetId!,
            docType: 'Stock Entry',
            company: company,
            payload: {
              'stock_entry_type': 'Material Receipt',
              'posting_date': openingDate,
              'to_warehouse': r.v('warehouse_code'),
              'is_opening': 1,
              'total_amount': value,
              'remarks': 'Opening stock from previous system',
            });
        doc.children['items'] = [
          ChildRow(
            id: '',
            parentId: '',
            parentDocType: 'Stock Entry',
            tableName: 'items',
            rowIndex: 0,
            payload: {
              'item': r.v('item_code'),
              'qty': r.qty,
              'target_warehouse': r.v('warehouse_code'),
              // Unit cost derived from the supplied total so qty × rate gives
              // back exactly that value; never a guessed cost.
              'valuation_rate': value / r.qty,
              'amount': value,
            },
          ),
        ];
        doc = await engine.save(doc, _roles);
      }
      await engine.submit(doc, _roles);
    });

    for (final receivable in const [true, false]) {
      await each(
          receivable ? TakeOnSection.receivables : TakeOnSection.payables,
          (r) => _postOpenInvoice(r, company, openingDate,
              receivable: receivable));
    }

    final tb = plan.sections[TakeOnSection.trialBalance]!;
    if (!tb.blocked &&
        tb.rows.any((r) =>
            r.status == TakeOnRowStatus.create ||
            r.status == TakeOnRowStatus.resume)) {
      try {
        final id = journalId(openingDate);
        var je = await engine.fetch('Journal Entry', id);
        if (je == null) {
          final built = OpeningBalanceBuilder.build(
            [
              for (final e in _journalLines(tb).entries)
                OpeningBalanceEntry(e.key,
                    debit: e.value > 0 ? e.value / 100 : 0,
                    credit: e.value < 0 ? -e.value / 100 : 0),
            ],
            postingDate: openingDate,
            equityAccount: equityAccount,
            company: company,
          );
          built.id = id;
          built.payload['user_remark'] =
              'Opening balances from previous system (trial balance at $openingDate)';
          je = await engine.save(built, _roles);
          result.created[TakeOnSection.trialBalance] = 1;
        } else {
          result.posted[TakeOnSection.trialBalance] = 1;
        }
        if (je.docStatus == 0) await engine.submit(je, _roles);
      } catch (e) {
        result.errors.add('Trial balance: '
            '${e is DocumentEngineError ? e.humanMessage : e}');
      }
    }
    return (plan, result);
  }

  Future<void> _postOpenInvoice(TakeOnRow r, String? company,
      String openingDate, {required bool receivable}) async {
    final docType = receivable ? 'Sales Invoice' : 'Purchase Invoice';
    var doc = await engine.fetch(docType, r.targetId!);
    if (doc == null) {
      await _ensureOpeningItem();
      final legacyNo = r.v(receivable ? 'invoice_no' : 'bill_no');
      final legacyDate = r.v(receivable ? 'invoice_date' : 'bill_date');
      final due = r.v('due_date').isEmpty ? legacyDate : r.v('due_date');
      final amount = r.cents / 100;
      doc = Document(id: r.targetId!, docType: docType, company: company, payload: {
        if (receivable) 'customer': r.v('customer_code'),
        if (!receivable) 'supplier': r.v('supplier_code'),
        if (!receivable) 'supplier_invoice_no': legacyNo,
        'posting_date': openingDate,
        'due_date': due,
        'is_opening': 1,
        // The other side of an opening balance is equity, never income or
        // expense, and no VAT is computed again.
        if (receivable) 'income_account': equityAccount,
        if (!receivable) 'expense_account': equityAccount,
      });
      doc.children['items'] = [
        ChildRow(
          id: '',
          parentId: '',
          parentDocType: docType,
          tableName: 'items',
          rowIndex: 0,
          payload: {
            'item': openingItemCode,
            'description': 'Opening balance: ${receivable ? 'invoice' : 'bill'} '
                '$legacyNo dated $legacyDate',
            'qty': 1,
            'rate': amount,
          },
        ),
      ];
      doc = await engine.save(doc, _roles);
    }
    await engine.submit(doc, _roles);
  }

  /// The non-stock line item carried by opening invoices and bills.
  static const openingItemCode = 'OPENING-BALANCE';

  Future<void> _ensureOpeningItem() async {
    if (await engine.fetch('Item', openingItemCode) != null) return;
    await engine.save(
        Document(id: openingItemCode, docType: 'Item', payload: {
          'item_code': openingItemCode,
          'item_name': 'Opening balance (previous system)',
          'item_type': 'Service',
          'stock_uom': 'Nos',
        }),
        _roles);
  }

  Future<String?> _companyId() async {
    final all = await engine.list('Company', userRoles: _roles);
    return all.isEmpty ? null : all.first.id;
  }

  static String _title(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1).toLowerCase();
}

/// Snapshot of the masters a plan validates against.
class _Context {
  _Context();
  final customers = <String, Document>{};
  final suppliers = <String, Document>{};
  final items = <String, Document>{};
  final warehouses = <String, Document>{};
  final accounts = <String, Document>{};
  final _accountByName = <String, Document>{};
  SectionPlan? plannedCustomers;
  SectionPlan? plannedSuppliers;
  SectionPlan? plannedItems;
  SectionPlan? plannedWarehouses;

  static Future<_Context> load(DocumentEngine engine) async {
    final c = _Context();
    Future<void> fill(String type, Map<String, Document> into) async {
      for (final d in await engine.list(type, userRoles: _roles)) {
        into[d.id] = d;
      }
    }

    await fill('Customer', c.customers);
    await fill('Supplier', c.suppliers);
    await fill('Item', c.items);
    await fill('Warehouse', c.warehouses);
    await fill('Account', c.accounts);
    for (final a in c.accounts.values) {
      c._accountByName['${a.payload['account_name'] ?? ''}'.toLowerCase()] = a;
      c._accountByName[a.id.toLowerCase()] = a;
    }
    return c;
  }

  Document? resolveAccount(String nameOrId) =>
      accounts[nameOrId] ?? _accountByName[nameOrId.toLowerCase()];
}

/// Parse a money amount into integer cents. Accepts `-`, digits and up to two
/// decimals; anything else (thousands separators, currency signs, three
/// decimals) is refused rather than guessed. Null when invalid.
int? parseCents(String raw) {
  final s = raw.trim();
  final m = RegExp(r'^(-)?(\d+)(?:\.(\d{1,2}))?$').firstMatch(s);
  if (m == null) return null;
  final whole = int.parse(m.group(2)!);
  final frac = (m.group(3) ?? '').padRight(2, '0');
  final cents = whole * 100 + int.parse(frac.isEmpty ? '0' : frac);
  return m.group(1) == null ? cents : -cents;
}

/// Parse a quantity (up to 6 decimals, no sign). Null when invalid.
num? parseQty(String raw) {
  final s = raw.trim();
  if (!RegExp(r'^\d+(\.\d{1,6})?$').hasMatch(s)) return null;
  return num.parse(s);
}

String formatCents(int cents) {
  final sign = cents < 0 ? '-' : '';
  final c = cents.abs();
  return '$sign${c ~/ 100}.${(c % 100).toString().padLeft(2, '0')}';
}

int _cents(num v) => (v * 100).round();

/// The YYYY-MM-DD day of a stored date, which is an ISO string or epoch
/// milliseconds.
String? _dayOf(Object? v) {
  final DateTime? d = v is int
      ? DateTime.fromMillisecondsSinceEpoch(v)
      : v is String
          ? DateTime.tryParse(v.trim())
          : null;
  if (d == null) return null;
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year.toString().padLeft(4, '0')}-${two(d.month)}-${two(d.day)}';
}

DateTime? _isoDate(String s) {
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s)) return null;
  final d = DateTime.tryParse(s);
  if (d == null) return null;
  final back =
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  return back == s ? d : null;
}
