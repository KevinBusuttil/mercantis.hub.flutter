@Tags(['team-e2e'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_hub_app/ledger/hub_interceptors.dart';
import 'package:mercantis_hub_app/ledger/ledger_values.dart' show asNum, round2;
import 'package:mercantis_hub_app/payments/pos_checkout.dart';
import 'package:mercantis_hub_app/team/team_account_client.dart';
import 'package:mercantis_hub_app/team/team_naming.dart';
import 'package:mercantis_hub_app/team/team_posting_guard.dart';
import 'package:mercantis_hub_app/team/team_posting_service.dart';
import 'package:mercantis_hub_app/team/team_session.dart';
import 'package:mercantis_hub_app/team/team_sync_runner.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/books_harness.dart';

/// Real multi-device Team test: three hub installs, each with its own SQLite
/// books, the real document engine, the Team posting guard and the ledger
/// derivation, talking to a REAL Atlas Team backend over HTTP (PostgreSQL
/// behind it). Nothing is mocked between the devices and the server.
///
/// Skipped unless `ATLAS_TEAM_E2E_URL` points at a running backend started
/// without `ATLAS_BOOTSTRAP_TOKEN` (it creates companies).
/// `tool/team_e2e.sh` builds the backend, starts it on a fresh database and
/// runs this file.
///
/// Devices: A (owner, office), B (admin, laptop), T (till, `pos` role).
void main() {
  sqfliteFfiInit();
  final baseUrl = Platform.environment['ATLAS_TEAM_E2E_URL'];
  final skip = baseUrl == null
      ? 'set ATLAS_TEAM_E2E_URL to a running Atlas Team backend'
      : null;

  late Directory root;
  final devices = <_Device>[];

  setUp(() async => root = await Directory.systemTemp.createTemp('team-e2e'));
  tearDown(() async {
    for (final d in devices) {
      await d.close();
    }
    devices.clear();
    if (root.existsSync()) await root.delete(recursive: true);
  });

  test('three devices share one set of official books', () async {
    final account = TeamAccountClient(baseUrl: baseUrl!);
    final stamp = DateTime.now().microsecondsSinceEpoch;

    // ---- Company bootstrap: A seeds locally, creates the Team company and
    // publishes its books; B and T join by invitation and pull everything.
    final a = await _Device.open(root, 'device-a', seed: true);
    devices.add(a);
    a.session = await account.createAndConnect(
      companyName: 'E2E Trading $stamp',
      ownerEmail: 'owner-$stamp@e2e.test',
      ownerName: 'Owner',
      deviceName: 'Office PC',
    );
    final first = await a.sync();
    expect(first.pushed, greaterThan(0), reason: 'the seed is published');

    Future<_Device> join(String id, String role) async {
      final invite = await account.createInvitation(
        companyId: a.session.companyId,
        authToken: a.session.userToken,
        email: '$id-$stamp@e2e.test',
        role: role,
      );
      final d = await _Device.open(root, id, seed: false);
      devices.add(d);
      d.session = await account.joinAndConnect(
        invitationToken: invite.token,
        displayName: id,
        deviceName: id,
      );
      final r = await d.sync();
      expect(r.applied, greaterThan(0), reason: '$id pulls the company');
      return d;
    }

    final b = await join('device-b', 'admin');
    final t = await join('till-1', 'pos');
    for (final d in [b, t]) {
      expect(await d.h.rowCount('Account'), await a.h.rowCount('Account'),
          reason: '${d.id} has the same chart of accounts');
      expect(await d.h.rowCount('Company'), 1);
    }

    // ---- Master data from B reaches everyone (an alternative-UOM stock
    // item and a service item; the server reads them for posting).
    await b.h.save(Document(id: 'BOTTLE', docType: 'Item', payload: {
      'item_code': 'BOTTLE',
      'item_name': 'Bottle',
      'item_type': 'Stock',
      'stock_uom': 'Nos',
      'valuation_method': 'Moving Average',
    })
      ..children['uoms'] = [
        itemLine('Item', {'uom': 'Box', 'conversion_factor': 12}, 0, 'uoms'),
      ]);
    await b.h.save(Document(id: 'DELIVERY', docType: 'Item', payload: {
      'item_code': 'DELIVERY',
      'item_name': 'Delivery',
      'item_type': 'Service',
      'stock_uom': 'Nos',
    }));
    await b.h.save(Document(id: 'S-1', docType: 'Supplier', payload: {
      'supplier_name': 'Glassworks',
    }));
    await b.h.save(Document(id: 'C-1', docType: 'Customer', payload: {
      'customer_name': 'Harbour Bar',
      'customer_type': 'Company',
    }));
    await b.sync();
    await a.sync();
    await t.sync();
    expect(await a.h.engine.fetch('Item', 'BOTTLE'), isNotNull);
    expect(await t.h.engine.fetch('Item', 'DELIVERY'), isNotNull);

    // ---- Concurrent edits to one customer: the second writer gets a
    // conflict to resolve, never a silent overwrite.
    Future<void> rename(_Device d, String name) async {
      final c = (await d.h.engine.fetch('Customer', 'C-1'))!;
      c.payload['customer_name'] = name;
      await d.h.save(c);
    }

    await rename(a, 'Harbour Bar (A)');
    await rename(b, 'Harbour Bar (B)');
    await a.sync();
    await b.sync();
    final conflicts = await b.h.db.db.query('sync_conflicts',
        where: 'document_id = ?', whereArgs: ['C-1']);
    expect(conflicts, hasLength(1), reason: 'B must see the conflict');
    expect((await b.h.engine.fetch('Customer', 'C-1'))!.payload['customer_name'],
        'Harbour Bar (B)', reason: "B's edit is kept until resolved");
    await t.sync();
    expect((await t.h.engine.fetch('Customer', 'C-1'))!.payload['customer_name'],
        'Harbour Bar (A)', reason: 'the first writer stands everywhere else');
    // B resolves by taking A's version.
    await ConflictService(
      database: b.h.db.db,
      syncEngine: SyncEngine(database: b.h.db.db, registry: b.registry),
      deviceId: b.id,
      userId: 'owner',
    ).takeTheirs('Customer', 'C-1');
    await b.sync();
    expect((await b.h.engine.fetch('Customer', 'C-1'))!.payload['customer_name'],
        'Harbour Bar (A)');

    // ---- The guard: no device can make official accounting on its own.
    final localTry = await a.h.save(_purchase('BOTTLE', 1, 'Box', 60));
    await expectLater(a.h.submit(localTry), throwsA(isA<DocumentEngineError>()));
    expect(await a.h.rowCount('GL Entry'), 0);

    // ---- Server posting: A buys 2 boxes (24 bottles) plus a delivery
    // charge. The server posts it, every device receives the same rows.
    final bill = await a.serverSubmit(await a.h.save(
        _purchase('BOTTLE', 2, 'Box', 60, service: 'DELIVERY', serviceRate: 15)));
    expect(bill['number'], isNotNull);
    for (final d in [a, b, t]) {
      await d.sync();
    }
    for (final d in [a, b, t]) {
      final bin = await d.bin('BOTTLE');
      expect(asNum(bin?.payload['actual_qty']), 24,
          reason: '${d.id}: 2 boxes of 12, in stock units');
      expect(await d.bin('DELIVERY'), isNull,
          reason: '${d.id}: a service line moves no stock');
      expect(await d.h.trialBalanceDifference(), 0, reason: d.id);
    }
    await _sameBooks([a, b, t]);

    // ---- Concurrency: A and B post sales at the same moment. Both are
    // numbered by the server, gap-free and distinct, stock goes down once
    // per sale, and everyone converges.
    final saleA = await a.h.save(_sale('BOTTLE', 5, 3));
    final saleB = await b.h.save(_sale('BOTTLE', 4, 3));
    expect(saleA.id, isNot(saleB.id), reason: 'device-unique draft ids');
    await Future.wait([a.sync(), b.sync()]); // drafts into the log
    final results = await Future.wait([
      a.postNow(saleA),
      b.postNow(saleB),
    ]);
    final numbers = results.map((r) => '${r['number']}').toSet();
    expect(numbers, hasLength(2), reason: 'distinct official numbers');
    for (final d in [a, b, t]) {
      await d.sync();
    }
    for (final d in [a, b, t]) {
      expect(asNum((await d.bin('BOTTLE'))!.payload['actual_qty']), 15,
          reason: d.id);
    }
    await _sameBooks([a, b, t]);

    // ---- A payment from B with the receiving account left blank: the
    // draft takes the company's own default (Bank in the seeded chart) on
    // save, so the server books it exactly where Solo would, not to its
    // built-in `Cash`. Every device sees the invoice settled.
    final pay = await b.h.save(Document(id: '', docType: 'Payment Entry', payload: {
      'payment_type': 'Receive',
      'party_type': 'Customer',
      'party': 'C-1',
      'posting_date': isoToday(),
      'paid_amount': 15,
    })
      ..children['references'] = [
        itemLine('Payment Entry', {
          'reference_doctype': 'Sales Invoice',
          'reference_name': saleA.id,
          'allocated_amount': 15,
        }, 0, 'references'),
      ]);
    await b.serverSubmit(pay);
    for (final d in [a, b, t]) {
      await d.sync();
    }
    for (final d in [a, b, t]) {
      final legs = await d.h.engine.list('GL Entry',
          filters: {'voucher_no': pay.id}, userRoles: systemRoles);
      expect(legs.map((g) => g.payload['account']).toSet(), {'Bank', 'Debtors'},
          reason: d.id);
      expect(asNum((await d.h.engine.fetch('Sales Invoice', saleA.id))!
              .payload['outstanding_amount']),
          0, reason: '${d.id}: the sale is settled');
    }
    await _sameBooks([a, b, t]);

    // ---- Interrupted submit: the response is lost and the device retries
    // with the same command. The server replays; nothing posts twice.
    final retried = await a.h.save(_sale('BOTTLE', 1, 3));
    await a.sync();
    final cmd = await a.command(retried);
    final once = await a.posting.submitDocument(cmd);
    final again = await a.posting.submitDocument(cmd);
    expect(jsonEncode(again), jsonEncode(once));
    await a.sync();
    await b.sync();
    expect(asNum((await b.bin('BOTTLE'))!.payload['actual_qty']), 14);

    // ---- Offline till: the network is down, the till keeps selling under
    // its own receipt series. Its sales post locally at once.
    final s1 = await t.h.saveAndSubmit(_till('BOTTLE', 3, 2.5));
    final s2 = await t.h.saveAndSubmit(_till('BOTTLE', 2, 2.5));
    expect(s1.id, contains('TILL1'));
    // The till last synced at 15 (it missed the retried sale while offline)
    // and sees its own sales at once.
    expect(asNum((await t.bin('BOTTLE'))!.payload['actual_qty']), 10);
    // Back online: the sync confirms both with the server, which posts them
    // under their receipt numbers for everyone.
    final back = await t.sync();
    expect(back.confirmedTillSales, 2);
    expect(back.tillSalesNeedingAttention, isEmpty);
    expect((await t.sync()).confirmedTillSales, 0, reason: 'confirmed once');
    await a.sync();
    await b.sync();
    for (final d in [a, b, t]) {
      expect(asNum((await d.bin('BOTTLE'))!.payload['actual_qty']), 9,
          reason: '${d.id} converges on the till sales');
      final official = await d.h.engine.fetch('POS Invoice', s2.id);
      expect(official?.payload['official_number'], s2.id, reason: d.id);
      expect(await d.h.trialBalanceDifference(), 0, reason: d.id);
    }
    await _sameBooks([a, b, t]);

    // ---- A device cannot push ledger rows: a GL row saved on B is dropped
    // from its queue, never published.
    await b.h.save(Document(id: 'FORGED-GL', docType: 'GL Entry', payload: {
      'posting_date': isoToday(),
      'account': 'Cash',
      'debit': 1000000,
      'credit': 0,
      'voucher_type': 'Journal Entry',
      'voucher_no': 'FORGED',
    }));

    await b.sync();
    await a.sync();
    expect(await a.h.engine.fetch('GL Entry', 'FORGED-GL'), isNull);
    await b.h.db.db.delete('documents', where: 'id = ?', whereArgs: ['FORGED-GL']);

    // ---- Another company's data is out of reach of these credentials.
    final other = await account.createAndConnect(
      companyName: 'Other $stamp',
      ownerEmail: 'other-$stamp@e2e.test',
      ownerName: 'Other',
      deviceName: 'Other PC',
    );
    final crossPull = await http.get(
      Uri.parse('$baseUrl/companies/${other.companyId}/sync/pull?after=0'),
      headers: {'Authorization': 'Bearer ${b.session.deviceToken}'},
    );
    expect(crossPull.statusCode, 403, reason: 'B cannot read company 2');
    final crossPost = await http.post(
      Uri.parse('$baseUrl/companies/${other.companyId}/commands/submit-document'),
      headers: {
        'Authorization': 'Bearer ${a.session.userToken}',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(cmd),
    );
    expect(crossPost.statusCode, 403, reason: 'A cannot post into company 2');

    // ---- Server restored from an older backup: the device's cursor is
    // ahead of the log head; it notices and re-pulls from 0, idempotently.
    b.cursor.value += 1000000;
    final resync = await b.sync();
    expect(resync.cursorReset, isTrue);
    await _sameBooks([a, b]);

    // ---- Revocation: the owner revokes the till; its next sync is refused
    // and its local books are untouched.
    await account.revokeDevice(
      companyId: a.session.companyId,
      authToken: a.session.userToken,
      deviceId: t.session.deviceId,
    );
    await expectLater(t.sync(), throwsA(isA<CloudHttpException>()));
    expect(asNum((await t.bin('BOTTLE'))!.payload['actual_qty']), 9);
  }, skip: skip, timeout: const Timeout(Duration(minutes: 5)));
}

Document _purchase(String item, num qty, String uom, num rate,
        {String? service, num serviceRate = 0}) =>
    Document(id: '', docType: 'Purchase Invoice', payload: {
      'supplier': 'S-1',
      'posting_date': isoToday(),
      'due_date': isoToday(),
      'update_stock': 1,
      'set_warehouse': 'Main Store',
    })
      ..children['items'] = [
        itemLine('Purchase Invoice', {
          'item': item,
          'qty': qty,
          'uom': uom,
          'rate': rate,
          'warehouse': 'Main Store',
        }),
        if (service != null)
          itemLine('Purchase Invoice', {'item': service, 'qty': 1, 'rate': serviceRate}, 1),
      ];

Document _sale(String item, num qty, num rate) =>
    Document(id: '', docType: 'Sales Invoice', payload: {
      'customer': 'C-1',
      'posting_date': isoToday(),
      'due_date': isoToday(),
      'update_stock': 1,
      'set_warehouse': 'Main Store',
    })
      ..children['items'] = [
        itemLine('Sales Invoice',
            {'item': item, 'qty': qty, 'rate': rate, 'warehouse': 'Main Store'}),
      ];

Document _till(String item, num qty, num rate) => PosCheckout.buildPosInvoice(
      postingDate: isoToday(),
      tillSeries: 'TILL1',
      warehouse: 'Main Store',
      lines: [PosCartLine(item: item, qty: qty, rate: rate, warehouse: 'Main Store')],
      tenders: [PosTender(type: 'Cash', amount: round2(qty * rate * 1.18))],
    );

/// Every device holds the same GL, account by account.
Future<void> _sameBooks(List<_Device> devices) async {
  final books = [for (final d in devices) await d.balances()];
  for (var i = 1; i < devices.length; i++) {
    expect(books[i], books[0],
        reason: '${devices[i].id} and ${devices[0].id} disagree');
  }
}

class _MemCursor implements TeamSyncCursorStore {
  int value = 0;
  @override
  Future<int> load(String companyId) async => value;
  @override
  Future<void> save(String companyId, int cursor) async => value = cursor;
}

class _Device {
  _Device(this.id, this.h);

  final String id;
  final BooksHarness h;
  final cursor = _MemCursor();
  TeamSession? _session;
  TeamSession get session => _session!;
  set session(TeamSession s) => _session = s;
  late final registry = MetadataRegistry(h.db.db);
  late final posting = TeamPostingClient(
    baseUrl: session.baseUrl,
    companyId: session.companyId,
    deviceToken: session.deviceToken,
  );

  static Future<_Device> open(Directory root, String id,
      {required bool seed}) async {
    _Device? device;
    final h = await BooksHarness.open(
      p.join(root.path, '$id.db'),
      deviceId: id,
      seed: seed,
      interceptors: [
        TeamPostingAuthorityGuard(() => true),
        ...hubInterceptors,
      ],
      // The app's Team naming: series ids carry the device's tag.
      namingService: TeamScopedNamingService(() {
        final s = device?._session;
        return s == null ? null : teamDeviceTag(s.deviceId);
      }),
    );
    return device = _Device(id, h);
  }

  Future<TeamSyncResult> sync() => runTeamSync(
        session: session,
        database: h.db.db,
        registry: registry,
        localDeviceId: id,
        cursorStore: cursor,
      );

  /// The form's Submit in Team: drafts up, server posts, results home.
  Future<Map<String, dynamic>> serverSubmit(Document draft) async {
    await sync();
    final result = await postNow(draft);
    await sync();
    return result;
  }

  /// What the form's Submit sends for a saved draft.
  Future<Map<String, dynamic>> command(Document draft) async =>
      buildSubmitCommand((await h.engine.fetch(draft.docType, draft.id))!);

  Future<Map<String, dynamic>> postNow(Document draft) async =>
      posting.submitDocument(await command(draft));

  Future<Document?> bin(String item) async {
    final bins = await h.engine.list('Bin',
        filters: {'item': item}, userRoles: systemRoles);
    return bins.isEmpty ? null : bins.single;
  }

  Future<Map<String, num>> balances() async {
    final out = <String, num>{};
    for (final r in await h.engine.list('GL Entry', userRoles: systemRoles)) {
      final account = '${r.payload['account']}';
      out[account] = round2((out[account] ?? 0) +
          asNum(r.payload['debit']) -
          asNum(r.payload['credit']));
    }
    out.removeWhere((_, v) => v == 0);
    return out;
  }

  Future<void> close() async {
    posting.close();
    await h.close();
  }
}
