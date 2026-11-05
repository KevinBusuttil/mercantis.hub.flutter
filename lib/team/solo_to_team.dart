import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:sqflite_common/sqlite_api.dart';

import '../ledger/ledger_derivation.dart';
import '../ledger/ledger_values.dart';
import 'team_sync_runner.dart' show teamServerDerivedDocTypes;

/// C3 — moving a Solo book into a new Atlas Team company, once.
///
/// **Why a conversion and not "connect and sync":** a Solo book that has
/// issued invoices cannot simply start syncing into Team. Its submitted
/// vouchers and ledger rows are official state, which the Team server only
/// accepts from its own posting engine, so the first push is refused and
/// every later sync is refused the same way. Pushing them again as drafts
/// would have the server number them a second time. Neither is acceptable.
///
/// The conversion instead:
///
/// 1. **Preflight** ([preflight]): proves the Solo book is consistent
///    (integrity, no owed postings, trial balance, stock and party
///    subledgers agree with the ledger, numbering not on hold, nothing dated
///    after the cut-over) and lists what does not carry over.
/// 2. **Safety backup**: the caller makes and verifies an encrypted backup
///    first (the screen will not continue without one).
/// 3. **Publish masters** ([masterMutations]): accounts, customers,
///    suppliers, items, warehouses, settings, drafts: everything that is
///    not official history, as ordinary sync mutations with deterministic
///    ids (a retry re-sends the same ids, and the log is idempotent on id).
/// 4. **Server take-on** ([buildPackage]): the Solo position at the
///    cut-over date, posted by the Team server as one opening entry with
///    stock and party balances, and numbering that continues after the
///    last Solo numbers. The server reconciles it to the cent and refuses
///    anything that does not add up, and refuses a second take-on.
/// 5. **Build the Team book** in a separate file from the server and
///    [reconcile] it against the Solo figures, account by account, party by
///    party, item by item.
/// 6. **Switch**: only when everything matched, the Solo book is copied to
///    an archive folder (kept, never deleted) and the Team book takes its
///    place.
///
/// The Solo book is never edited. Nothing is renumbered: Solo documents keep
/// their numbers in the archive, and Team continues the sequence.
class SoloToTeamConversion {
  SoloToTeamConversion(this.solo);

  /// The Solo book (read only here).
  final Database solo;

  /// Doctypes whose submitted documents are official history: they stay in
  /// the Solo archive and their effect arrives as the opening position.
  static final historyDocTypes = {
    ...LedgerDerivation.postingSources,
  };

  /// Rows that are never published: ledger rows (the server derives its
  /// own) and the local posting outbox.
  static final neverPublished = {
    ...teamServerDerivedDocTypes,
    'Posting Batch',
  };

  /// Team numbering series the server keeps, by doctype (backend
  /// `series_key`). POS keeps its per-till receipt series instead.
  static const teamSeriesDocTypes = [
    'Sales Invoice',
    'Purchase Invoice',
    'Purchase Receipt',
    'Delivery Note',
    'Payment Entry',
    'Stock Entry',
  ];

  // ---------------------------------------------------------------- figures

  /// The Solo book's position: trial balance (net per account, base
  /// currency), party balances, stock by item and warehouse.
  Future<SoloFigures> figures() async {
    final tb = <String, num>{};
    final partyLines = <(String, String?, String?), num>{};
    var foreignCurrency = false;
    for (final row in await _payloads(LedgerDerivation.glEntry)) {
      final account = asNonEmpty(row['account']);
      if (account == null) continue;
      final debit = row['base_debit'] ?? row['debit'];
      final credit = row['base_credit'] ?? row['credit'];
      final net = asNum(debit) - asNum(credit);
      final rate = row['conversion_rate'];
      if (rate != null && (asNum(rate) - 1).abs() > 1e-9) {
        foreignCurrency = true;
      }
      tb[account] = (tb[account] ?? 0) + net;
      final pt = asNonEmpty(row['party_type']);
      final party = asNonEmpty(row['party']);
      final key = (account, pt, pt == null ? null : party);
      partyLines[key] = (partyLines[key] ?? 0) + net;
    }
    final customers = <String, num>{};
    for (final row in await _payloads(LedgerDerivation.customerTxn)) {
      final party = asNonEmpty(row['customer']);
      if (party == null) continue;
      customers[party] =
          (customers[party] ?? 0) + asNum(row['base_amount'] ?? row['amount']);
    }
    final suppliers = <String, num>{};
    for (final row in await _payloads(LedgerDerivation.supplierTxn)) {
      final party = asNonEmpty(row['supplier']);
      if (party == null) continue;
      suppliers[party] =
          (suppliers[party] ?? 0) + asNum(row['base_amount'] ?? row['amount']);
    }

    final company = await _company();
    final items = <String, Map<String, dynamic>>{
      for (final r in await _rows('Item')) '${r['id']}': _decode(r['payload']),
    };
    final stock = <SoloStock>[];
    for (final row in await _payloads(LedgerDerivation.bin)) {
      final item = asNonEmpty(row['item']);
      final warehouse = asNonEmpty(row['warehouse']);
      if (item == null || warehouse == null) continue;
      final qty = asNum(row['actual_qty']);
      final value = asNum(row['stock_value']);
      if (qty.abs() < 1e-9 && value.abs() < 0.005) continue;
      stock.add(SoloStock(
        item: item,
        warehouse: warehouse,
        qty: qty,
        value: value,
        account: asNonEmpty(items[item]?['inventory_account']) ??
            asNonEmpty(company?['default_inventory_account']) ??
            'Stock',
      ));
    }
    stock.sort((a, b) =>
        '${a.item}|${a.warehouse}'.compareTo('${b.item}|${b.warehouse}'));
    return SoloFigures(
      trialBalance: _clean(tb),
      partyLines: {
        for (final e in partyLines.entries)
          if (e.value.abs() >= 0.005) e.key: _round(e.value),
      },
      customerBalances: _clean(customers),
      supplierBalances: _clean(suppliers),
      stock: stock,
      foreignCurrency: foreignCurrency,
    );
  }

  // -------------------------------------------------------------- preflight

  /// Every check the conversion needs, in the order a person would fix
  /// them. Blocking checks stop the conversion; the others are what the
  /// person should know before going ahead.
  Future<SoloTeamPreflight> preflight({
    required String cutoverDate,
    required bool teamConnected,
    Set<String> numberingHolds = const {},
  }) async {
    final checks = <ConversionCheck>[];
    void block(String id, String message) =>
        checks.add(ConversionCheck(id, message, blocking: true));
    void note(String id, String message) =>
        checks.add(ConversionCheck(id, message, blocking: false));

    if (teamConnected) {
      block('team', 'This device is already connected to Atlas Team.');
    }

    final integrity = await solo.rawQuery('PRAGMA quick_check');
    final ok =
        integrity.isNotEmpty && '${integrity.first.values.first}' == 'ok';
    if (!ok) {
      block('integrity',
          'The books file failed its integrity check. Contact support before moving it.');
    }

    final companies = await _rows('Company');
    if (companies.length != 1) {
      block('company',
          'A Team company holds one business; this book holds ${companies.length}.');
    }

    final owed = await solo.rawQuery(
        "SELECT COUNT(*) AS n FROM posting_batches WHERE status != 'posted'");
    final owedCount = (owed.first['n'] as int?) ?? 0;
    if (owedCount > 0) {
      block(
          'owed',
          '$owedCount document${owedCount == 1 ? '' : 's'} still owe ledger postings. '
              'Choose Retry owed postings on Backup & restore first.');
    }

    if (numberingHolds.isNotEmpty) {
      block(
          'numbering',
          'Numbering is on hold for ${numberingHolds.join(', ')} after a restore. '
              'Confirm the last numbers in Settings › Numbering series first.');
    }

    final future = await solo.rawQuery(
      'SELECT doctype, id, payload FROM documents WHERE docstatus >= 1 '
      'AND doctype IN (${List.filled(historyDocTypes.length, '?').join(', ')})',
      historyDocTypes.toList(),
    );
    final later = [
      for (final r in future)
        if ('${_decode(r['payload'])['posting_date'] ?? ''}'
                .compareTo(cutoverDate) >
            0)
          '${r['doctype']} ${r['id']}',
    ];
    if (later.isNotEmpty) {
      block(
          'future',
          '${later.length} document${later.length == 1 ? ' is' : 's are'} dated after '
              '$cutoverDate (${later.take(3).join(', ')}${later.length > 3 ? ', …' : ''}). '
              'Move on that date or later.');
    }

    final company = await _company();
    final lock = asNonEmpty(company?['books_lock_date']);
    if (lock != null && lock.compareTo(cutoverDate) >= 0) {
      block(
          'lock',
          'The books are locked through $lock. The opening position is dated '
              '$cutoverDate, so move after the lock date.');
    }

    final f = await figures();
    final tbDifference = f.trialBalance.values.fold<num>(0, (a, b) => a + b);
    if (tbDifference.abs() >= 0.005) {
      block('trial_balance',
          'The trial balance is out by ${_money(tbDifference)}. Contact support.');
    }

    final byAccount = <String, num>{};
    for (final s in f.stock) {
      if (s.qty < 0) {
        block('negative_stock',
            '${s.item} in ${s.warehouse} is below zero (${s.qty}). Count and adjust it first.');
      } else if (s.qty.abs() < 1e-9) {
        block(
            'stock_value_without_qty',
            '${s.item} in ${s.warehouse} has a value of ${_money(s.value)} but no quantity. '
                'Count and adjust it first.');
      }
      byAccount[s.account] = (byAccount[s.account] ?? 0) + s.value;
    }
    for (final e in byAccount.entries) {
      final ledger = f.trialBalance[e.key] ?? 0;
      if ((ledger - e.value).abs() >= 0.01) {
        block(
            'stock_vs_ledger',
            'Stock on ${e.key} is worth ${_money(e.value)} but the account shows '
                '${_money(ledger)}. Run the stock reconciliation report first.');
      }
    }

    final receivables = f.receivables;
    final ar = f.customerBalances.values.fold<num>(0, (a, b) => a + b);
    if ((ar - receivables).abs() >= 0.01) {
      block(
          'receivables',
          'Customer balances total ${_money(ar)} but the ledger shows ${_money(receivables)} '
              'owed by customers. Contact support.');
    }
    final payables = f.payables;
    final ap = f.supplierBalances.values.fold<num>(0, (a, b) => a + b);
    if ((ap - payables).abs() >= 0.01) {
      block(
          'payables',
          'Supplier balances total ${_money(ap)} but the ledger shows ${_money(payables)} '
              'owed to suppliers. Contact support.');
    }

    if (f.foreignCurrency) {
      note(
          'currency',
          'Some balances are in a foreign currency. They move in your home currency '
              'at the rates already booked.');
    }
    final drafts = await solo.rawQuery(
      'SELECT COUNT(*) AS n FROM documents WHERE docstatus = 0 '
      'AND doctype IN (${List.filled(historyDocTypes.length, '?').join(', ')})',
      historyDocTypes.toList(),
    );
    final draftCount = (drafts.first['n'] as int?) ?? 0;
    if (draftCount > 0) {
      note(
          'drafts',
          '$draftCount draft${draftCount == 1 ? '' : 's'} move as drafts. In Team they are '
              'submitted from their form and numbered by the Team server.');
    }
    note(
        'history',
        'Invoices, bills and payments up to $cutoverDate stay in the Solo archive on '
            'this device and in the safety backup. Team starts from their balances: '
            'one opening balance per customer and supplier, not one per invoice.');
    note('devices',
        'Stop using Atlas Solo on any other device for this business before you move.');

    return SoloTeamPreflight(checks: checks, figures: f);
  }

  // ---------------------------------------------------------------- package

  /// The take-on package the Team server posts (see the backend's
  /// `posting::solo_migration`).
  Future<SoloTeamPackage> buildPackage({
    required String migrationId,
    required String cutoverDate,
    Map<String, Object?> source = const {},
  }) async {
    final f = await figures();
    final lines = <Map<String, Object?>>[];
    final keys = f.partyLines.keys.toList()
      ..sort((a, b) =>
          '${a.$1}|${a.$2}|${a.$3}'.compareTo('${b.$1}|${b.$2}|${b.$3}'));
    for (final key in keys) {
      final net = f.partyLines[key]!;
      lines.add({
        'account': key.$1,
        'debit': net > 0 ? _round(net) : 0,
        'credit': net < 0 ? _round(-net) : 0,
        if (key.$2 != null && key.$3 != null) ...{
          'party_type': key.$2,
          'party': key.$3,
        },
      });
    }
    return SoloTeamPackage(
      migrationId: migrationId,
      postingDate: cutoverDate,
      source: source,
      lines: lines,
      stock: [
        for (final s in f.stock)
          {
            'item': s.item,
            'warehouse': s.warehouse,
            'qty': s.qty,
            'stock_value': _round(s.value),
            'account': s.account,
          },
      ],
      numbering: await lastIssuedNumbers(),
      expected: {
        'trial_balance': {
          for (final e in f.trialBalance.entries) e.key: _round(e.value),
        },
        'receivables': _round(f.receivables),
        'payables': _round(f.payables),
        'stock_value': _round(f.stock.fold<num>(0, (a, s) => a + s.value)),
      },
    );
  }

  /// For each Team-numbered doctype, the last number the Solo book issued
  /// in its newest series, so Team continues the count after it.
  Future<List<Map<String, Object?>>> lastIssuedNumbers() async {
    final out = <Map<String, Object?>>[];
    final trailing = RegExp(r'(\d+)$');
    for (final docType in teamSeriesDocTypes) {
      final rows = [
        ...await solo.query('documents',
            columns: ['id', 'payload', 'created_at'],
            where: 'doctype = ? AND docstatus >= 1',
            whereArgs: [docType]),
      ];
      if (rows.isEmpty) continue;
      rows.sort((a, b) {
        final da = '${_decode(a['payload'])['posting_date'] ?? ''}';
        final db = '${_decode(b['payload'])['posting_date'] ?? ''}';
        final c = da.compareTo(db);
        return c != 0
            ? c
            : asNum(a['created_at']).compareTo(asNum(b['created_at']));
      });
      final newest = '${rows.last['id']}';
      final m = trailing.firstMatch(newest);
      if (m == null) continue;
      final prefix = newest.substring(0, m.start);
      var best = newest;
      var value = int.parse(m.group(1)!);
      for (final r in rows) {
        final id = '${r['id']}';
        if (!id.startsWith(prefix)) continue;
        final v = int.tryParse(id.substring(prefix.length));
        if (v != null && v > value) {
          value = v;
          best = id;
        }
      }
      out.add({'doctype': docType, 'last_issued': best, 'last_value': value});
    }
    return out;
  }

  // ---------------------------------------------------------------- masters

  /// Every document that moves to Team as an ordinary synced document: not
  /// a ledger row, and not official history.
  Future<List<Map<String, dynamic>>> masterRows() async {
    final rows =
        await solo.query('documents', orderBy: 'created_at ASC, id ASC');
    return [
      for (final r in rows)
        if (!neverPublished.contains(r['doctype']) &&
            !(historyDocTypes.contains(r['doctype']) &&
                asNum(r['docstatus']) >= 1))
          Map<String, dynamic>.from(r),
    ];
  }

  /// The masters as createDocument mutations in the engine's envelope
  /// (header row plus `__children`). Ids are derived from the migration and
  /// the document, so a retried push re-sends the same mutations.
  Future<List<MutationRecord>> masterMutations({
    required String migrationId,
    required String deviceId,
    required String userId,
  }) async {
    final out = <MutationRecord>[];
    for (final row in await masterRows()) {
      out.add(await _mutationFor(row,
          migrationId: migrationId, deviceId: deviceId, userId: userId));
    }
    return out;
  }

  /// The opening entry's draft (its lines as the `accounts` child table), so
  /// every Team device shows what the server posted.
  MutationRecord openingDraft(
    SoloTeamPackage package, {
    required String deviceId,
    required String userId,
  }) {
    final row = openingDraftRow(package);
    return MutationRecord(
      id: mutationIdFor(
          package.migrationId, 'Journal Entry', package.documentId),
      type: MutationType.createDocument,
      docType: 'Journal Entry',
      documentId: package.documentId,
      payload: row,
      deviceId: deviceId,
      userId: userId,
      localTimestamp: DateTime.now(),
    );
  }

  /// The draft row (envelope shape) of the opening entry.
  static Map<String, dynamic> openingDraftRow(SoloTeamPackage package) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = package.documentId;
    return {
      'id': id,
      'doctype': 'Journal Entry',
      'company': null,
      'docstatus': 0,
      'payload': jsonEncode({
        'posting_date': package.postingDate,
        'voucher_type': 'Opening Entry',
        'is_opening': 1,
        'title': 'Opening balances moved from Atlas Solo',
      }),
      'created_at': now,
      'modified_at': now,
      'sync_version': null,
      'sync_state': SyncState.synced.name,
      'amended_from': null,
      '__children': {
        'accounts': [
          for (var i = 0; i < package.lines.length; i++)
            {
              'id': '$id-acc-$i',
              'parent_id': id,
              'parent_doctype': 'Journal Entry',
              'table_name': 'accounts',
              'row_index': i,
              'payload': jsonEncode(package.lines[i]),
            },
        ],
      },
    };
  }

  static String mutationIdFor(String migrationId, String docType, String id) {
    final digest = sha256.convert(utf8.encode('$migrationId|$docType|$id'));
    return 'smig-${digest.toString().substring(0, 40)}';
  }

  Future<MutationRecord> _mutationFor(
    Map<String, dynamic> row, {
    required String migrationId,
    required String deviceId,
    required String userId,
  }) async {
    final id = '${row['id']}';
    final docType = '${row['doctype']}';
    final childRows = await solo.query('document_children',
        where: 'parent_id = ?', whereArgs: [id], orderBy: 'row_index ASC');
    final children = <String, List<Map<String, dynamic>>>{};
    for (final c in childRows) {
      children.putIfAbsent('${c['table_name']}', () => []).add({
        'id': c['id'],
        'parent_id': c['parent_id'],
        'parent_doctype': c['parent_doctype'],
        'table_name': c['table_name'],
        'row_index': c['row_index'],
        'payload': c['payload'],
      });
    }
    return MutationRecord(
      id: mutationIdFor(migrationId, docType, id),
      type: MutationType.createDocument,
      docType: docType,
      documentId: id,
      payload: {
        ...row,
        'sync_state': SyncState.synced.name,
        'sync_version': null,
        '__children': children,
      },
      deviceId: deviceId,
      userId: userId,
      localTimestamp: DateTime.now(),
    );
  }

  // --------------------------------------------------------------- staging

  /// Lays the published rows into the (empty, installed) Team book exactly
  /// as they were sent, marked synced: the server never echoes this
  /// device's own mutations back, so the Team book gets them from here and
  /// everything else (the posted opening entry, ledger rows, bins) from the
  /// server.
  static Future<void> seedTeamBook(
      Database team, List<MutationRecord> published) async {
    await team.transaction((txn) async {
      for (final m in published) {
        final row = Map<String, dynamic>.from(m.payload);
        final children = row.remove('__children');
        await txn.insert(
            'documents',
            {
              ...row,
              'sync_state': SyncState.synced.name,
            },
            conflictAlgorithm: ConflictAlgorithm.replace);
        await txn.delete('document_children',
            where: 'parent_id = ?', whereArgs: [m.documentId]);
        if (children is Map) {
          for (final table in children.values) {
            for (final c in (table as List)) {
              await txn.insert(
                  'document_children', Map<String, dynamic>.from(c as Map),
                  conflictAlgorithm: ConflictAlgorithm.replace);
            }
          }
        }
      }
    });
  }

  /// Compares the Team book built from the server with the Solo figures.
  /// Empty means every account, party and stock line matches to the cent.
  static Future<List<String>> reconcile(
      SoloFigures soloFigures, Database team) async {
    final teamFigures = await SoloToTeamConversion(team).figures();
    final problems = <String>[];
    void compare(String what, Map<String, num> a, Map<String, num> b) {
      for (final k in {...a.keys, ...b.keys}) {
        final x = a[k] ?? 0;
        final y = b[k] ?? 0;
        if ((x - y).abs() >= 0.01) {
          problems.add('$what $k: Solo ${_money(x)}, Team ${_money(y)}');
        }
      }
    }

    compare('Account', soloFigures.trialBalance, teamFigures.trialBalance);
    compare(
        'Customer', soloFigures.customerBalances, teamFigures.customerBalances);
    compare(
        'Supplier', soloFigures.supplierBalances, teamFigures.supplierBalances);
    final soloStock = {
      for (final s in soloFigures.stock) '${s.item} in ${s.warehouse}': s,
    };
    final teamStock = {
      for (final s in teamFigures.stock) '${s.item} in ${s.warehouse}': s,
    };
    for (final k in {...soloStock.keys, ...teamStock.keys}) {
      final a = soloStock[k];
      final b = teamStock[k];
      if (a == null || b == null) {
        problems
            .add('Stock $k: ${a == null ? 'only in Team' : 'missing in Team'}');
      } else if ((a.qty - b.qty).abs() > 1e-6 ||
          (a.value - b.value).abs() >= 0.01) {
        problems.add('Stock $k: Solo ${a.qty} worth ${_money(a.value)}, '
            'Team ${b.qty} worth ${_money(b.value)}');
      }
    }
    return problems;
  }

  // ---------------------------------------------------------------- helpers

  Future<List<Map<String, dynamic>>> _rows(String docType) =>
      solo.query('documents', where: 'doctype = ?', whereArgs: [docType]);

  Future<List<Map<String, dynamic>>> _payloads(String docType) async => [
        for (final r in await _rows(docType)) _decode(r['payload']),
      ];

  Future<Map<String, dynamic>?> _company() async {
    final rows = await _rows('Company');
    return rows.isEmpty ? null : _decode(rows.first['payload']);
  }

  static Map<String, dynamic> _decode(Object? raw) {
    if (raw is Map) return Map<String, dynamic>.from(raw);
    try {
      final v = jsonDecode('${raw ?? '{}'}');
      return v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  static Map<String, num> _clean(Map<String, num> m) => {
        for (final e in m.entries)
          if (e.value.abs() >= 0.005) e.key: _round(e.value),
      };

  static num _round(num v) => (v * 100).round() / 100;

  static String _money(num v) => v.toDouble().toStringAsFixed(2);
}

class SoloStock {
  const SoloStock({
    required this.item,
    required this.warehouse,
    required this.qty,
    required this.value,
    required this.account,
  });
  final String item;
  final String warehouse;
  final num qty;
  final num value;
  final String account;
}

class SoloFigures {
  const SoloFigures({
    required this.trialBalance,
    required this.partyLines,
    required this.customerBalances,
    required this.supplierBalances,
    required this.stock,
    required this.foreignCurrency,
  });

  /// Net (debit − credit) per account, base currency, zero rows dropped.
  final Map<String, num> trialBalance;

  /// Net per (account, party type, party); party null for unpartied rows.
  final Map<(String, String?, String?), num> partyLines;
  final Map<String, num> customerBalances;
  final Map<String, num> supplierBalances;
  final List<SoloStock> stock;
  final bool foreignCurrency;

  /// Owed by customers per the ledger's customer-tagged lines.
  num get receivables => partyLines.entries
      .where((e) => e.key.$2 == 'Customer')
      .fold<num>(0, (a, e) => a + e.value);

  /// Owed to suppliers per the ledger's supplier-tagged lines.
  num get payables => -partyLines.entries
      .where((e) => e.key.$2 == 'Supplier')
      .fold<num>(0, (a, e) => a + e.value);
}

class ConversionCheck {
  const ConversionCheck(this.id, this.message, {required this.blocking});
  final String id;
  final String message;
  final bool blocking;
}

class SoloTeamPreflight {
  const SoloTeamPreflight({required this.checks, required this.figures});
  final List<ConversionCheck> checks;
  final SoloFigures figures;
  List<ConversionCheck> get blockers => [
        for (final c in checks)
          if (c.blocking) c
      ];
  bool get canProceed => blockers.isEmpty;
}

class SoloTeamPackage {
  const SoloTeamPackage({
    required this.migrationId,
    required this.postingDate,
    required this.source,
    required this.lines,
    required this.stock,
    required this.numbering,
    required this.expected,
  });

  final String migrationId;
  final String postingDate;
  final Map<String, Object?> source;
  final List<Map<String, Object?>> lines;
  final List<Map<String, Object?>> stock;
  final List<Map<String, Object?>> numbering;
  final Map<String, Object?> expected;

  String get documentId => 'SOLO-OPENING-$migrationId';

  Map<String, Object?> toJson() => {
        'migration_id': migrationId,
        'posting_date': postingDate,
        'source': source,
        'lines': lines,
        'stock': stock,
        'numbering': numbering,
        'expected': expected,
      };
}
