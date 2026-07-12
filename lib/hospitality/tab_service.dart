import 'package:mercantis_core/mercantis_core.dart';

import '../ledger/ledger_values.dart';
import '../payments/pos_checkout.dart';
import '../pricing/price_resolver.dart';

const _systemRoles = {'System Manager'};

/// V2 Hospitality: the tab lifecycle. A tab is pre-fiscal working state —
/// it opens on a table, accumulates rounds, and only becomes money when it
/// settles into a POS Invoice on the existing till spine (per-till fiscal
/// series, session, Z report). Voiding an un-settled tab requires a reason
/// and leaves the record (status Void), never deletes it — that trail is
/// what a fiscal auditor looks for.
class TabService {
  TabService(this._engine, {Set<String> roles = _systemRoles})
      : _roles = roles;

  final DocumentEngine _engine;
  final Set<String> _roles;

  /// Opens a tab on [table]. One OPEN tab per table — a second sitting
  /// needs the first settled or voided (bar tabs pass no table and are
  /// unlimited).
  Future<Document> openTab({
    String? table,
    int covers = 1,
    String? server,
    String? customer,
  }) async {
    if (table != null) {
      final tableDoc = await _engine.fetch('POS Table', table);
      if (tableDoc == null) throw StateError('Table $table not found.');
      final open = await _openTabFor(table);
      if (open != null) {
        throw StateError(
            'Table $table already has open tab ${open.id} — settle or '
            'void it first.');
      }
    }
    return _engine.save(
        Document(id: '', docType: 'POS Tab', payload: {
          if (table != null) 'table': table,
          'status': 'Open',
          'opened_at': DateTime.now().toIso8601String(),
          'covers': covers,
          if (server != null) 'server': server,
          if (customer != null) 'customer': customer,
        }),
        _roles);
  }

  Future<Document?> _openTabFor(String table) async {
    final tabs = await _engine.list('POS Tab',
        filters: {'table': table}, userRoles: _roles);
    for (final t in tabs) {
      if ('${t.payload['status']}' == 'Open') return t;
    }
    return null;
  }

  /// Adds a line to an open tab. A blank rate resolves through S8 pricing
  /// (price list → standard rate); [modifiers] is the human summary and
  /// [modifierAmount] the per-unit price delta of the chosen options.
  Future<Document> addItem(
    String tabId, {
    required String item,
    num qty = 1,
    num? rate,
    String? modifiers,
    num modifierAmount = 0,
    String? notes,
    String? priceList,
  }) async {
    final tab = await _requireOpen(tabId);
    var lineRate = rate;
    if (lineRate == null) {
      final resolved = await PriceResolver(_engine).resolve(
        item: item,
        qty: qty,
        customer: asNonEmpty(tab.payload['customer']),
        priceList: priceList,
      );
      lineRate = resolved?.rate ?? 0;
    }
    final rows = tab.children['items'] ?? <ChildRow>[];
    rows.add(ChildRow(
      id: '', parentId: tab.id, parentDocType: 'POS Tab',
      tableName: 'items', rowIndex: rows.length,
      payload: {
        'item': item,
        'qty': qty,
        'rate': lineRate,
        if (modifiers != null && modifiers.isNotEmpty)
          'modifiers': modifiers,
        if (modifierAmount != 0) 'modifier_amount': modifierAmount,
        if (notes != null && notes.isNotEmpty) 'notes': notes,
      },
    ));
    tab.children['items'] = rows;
    return _engine.save(tab, _roles);
  }

  /// The tab's running total: Σ qty × (rate + modifier delta), pre-tax
  /// semantics identical to what settlement will invoice. Static — pure
  /// arithmetic over a hydrated tab.
  static num tabTotal(Document tab) {
    num total = 0;
    for (final row in tab.children['items'] ?? const <ChildRow>[]) {
      total += asNum(row.payload['qty']) *
          (asNum(row.payload['rate']) +
              asNum(row.payload['modifier_amount']));
    }
    return round2(total);
  }

  /// Settlement: the tab becomes a submitted POS Invoice — the fiscal
  /// moment. Modifier deltas fold into each line's rate (backend invariant
  /// amount == qty × rate holds untouched) and the modifiers ride the line
  /// description onto the receipt. The tab is stamped Billed with the
  /// invoice id; the table frees.
  Future<Document> settleTab(
    String tabId, {
    required List<PosTender> tenders,
    String? warehouse,
    String? taxCode,
    bool pricesIncludeTax = false,
    String? company,
    String? posProfile,
    String? posSession,
    String? tillSeries,
    String? priceList,
  }) async {
    final tab = await _requireOpen(tabId);
    final rows = tab.children['items'] ?? const <ChildRow>[];
    if (rows.isEmpty) {
      throw StateError('Tab $tabId has no items — nothing to settle.');
    }

    final lines = <PosCartLine>[];
    for (final row in rows) {
      final modifiers = asNonEmpty(row.payload['modifiers']);
      lines.add(PosCartLine(
        item: '${row.payload['item']}',
        qty: asNum(row.payload['qty']),
        rate: asNum(row.payload['rate']) +
            asNum(row.payload['modifier_amount']),
        description:
            modifiers == null ? null : '${row.payload['item']} ($modifiers)',
      ));
    }

    final draft = PosCheckout.buildPosInvoice(
      postingDate: DateTime.now().toIso8601String().split('T').first,
      customer: asNonEmpty(tab.payload['customer']),
      warehouse: warehouse,
      taxCode: taxCode,
      pricesIncludeTax: pricesIncludeTax,
      company: company,
      posProfile: posProfile,
      posSession: posSession,
      tillSeries: tillSeries,
      priceList: priceList,
      lines: lines,
      tenders: tenders,
    );
    final saved = await _engine.save(draft, _roles);
    final posted = await _engine.submit(saved, _roles);

    tab.payload['status'] = 'Billed';
    tab.payload['pos_invoice'] = posted.id;
    await _engine.save(tab, _roles);
    return posted;
  }

  /// V2-3: sends the tab's not-yet-sent lines to the kitchen as ONE
  /// ticket (a round). The lines are snapshotted onto the ticket and
  /// flagged `sent_to_kitchen` on the tab, so the next round only carries
  /// what's new. Nothing new to send is an error the server sees.
  Future<Document> sendToKitchen(String tabId) async {
    final tab = await _requireOpen(tabId);
    final rows = tab.children['items'] ?? const <ChildRow>[];
    final unsent = [
      for (final r in rows)
        if (!isTrue(r.payload['sent_to_kitchen'])) r,
    ];
    if (unsent.isEmpty) {
      throw StateError(
          'Tab $tabId has nothing new to send — every line is already '
          'in the kitchen.');
    }

    final ticket = Document(id: '', docType: 'Kitchen Ticket', payload: {
      'tab': tab.id,
      if (asNonEmpty(tab.payload['table']) != null)
        'table': tab.payload['table'],
      'status': 'Open',
      'sent_at': DateTime.now().toIso8601String(),
      if (asNonEmpty(tab.payload['server']) != null)
        'server': tab.payload['server'],
    });
    ticket.children['items'] = [
      for (var i = 0; i < unsent.length; i++)
        ChildRow(
          id: '', parentId: '', parentDocType: 'Kitchen Ticket',
          tableName: 'items', rowIndex: i,
          payload: {
            'item': unsent[i].payload['item'],
            'qty': unsent[i].payload['qty'],
            if (asNonEmpty(unsent[i].payload['modifiers']) != null)
              'modifiers': unsent[i].payload['modifiers'],
            if (asNonEmpty(unsent[i].payload['notes']) != null)
              'notes': unsent[i].payload['notes'],
          },
        ),
    ];
    final saved = await _engine.save(ticket, _roles);

    for (final r in unsent) {
      r.payload['sent_to_kitchen'] = 1;
    }
    await _engine.save(tab, _roles);
    return saved;
  }

  /// The kitchen bumps a finished ticket off the rail.
  Future<Document> bumpTicket(String ticketId) async {
    final ticket = await _engine.fetch('Kitchen Ticket', ticketId);
    if (ticket == null) throw StateError('Ticket $ticketId not found.');
    if ('${ticket.payload['status']}' != 'Open') {
      throw StateError(
          'Ticket $ticketId is ${ticket.payload['status']}, not Open.');
    }
    ticket.payload['status'] = 'Done';
    return _engine.save(ticket, _roles);
  }

  /// Voids an un-settled tab. The reason is mandatory and the record stays
  /// — a disappeared tab is exactly what a fiscal audit flags. Any ticket
  /// still open on the kitchen rail voids with it, so the kitchen never
  /// cooks a dead order.
  Future<Document> voidTab(String tabId, {required String reason}) async {
    if (reason.trim().isEmpty) {
      throw StateError('A void needs a reason.');
    }
    final tab = await _engine.fetch('POS Tab', tabId);
    if (tab == null) throw StateError('Tab $tabId not found.');
    if ('${tab.payload['status']}' == 'Billed') {
      throw StateError(
          'Tab $tabId is settled as ${tab.payload['pos_invoice']} — cancel '
          'that POS Invoice instead of voiding the tab.');
    }
    final tickets = await _engine.list('Kitchen Ticket',
        filters: {'tab': tab.id}, userRoles: _roles);
    for (final t in tickets) {
      if ('${t.payload['status']}' != 'Open') continue;
      t.payload['status'] = 'Void';
      await _engine.save(t, _roles);
    }
    tab.payload['status'] = 'Void';
    tab.payload['void_reason'] = reason.trim();
    return _engine.save(tab, _roles);
  }

  Future<Document> _requireOpen(String tabId) async {
    final tab = await _engine.fetch('POS Tab', tabId);
    if (tab == null) throw StateError('Tab $tabId not found.');
    if ('${tab.payload['status']}' != 'Open') {
      throw StateError('Tab $tabId is ${tab.payload['status']}, not Open.');
    }
    return tab;
  }
}
