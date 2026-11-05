@Tags(['team-e2e', 'team-restore'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_hub_app/ledger/hub_interceptors.dart';
import 'package:mercantis_hub_app/ledger/ledger_values.dart' show asNum, round2;
import 'package:mercantis_hub_app/payments/pos_checkout.dart';
import 'package:mercantis_hub_app/team/team_account_client.dart';
import 'package:mercantis_hub_app/team/team_history.dart';
import 'package:mercantis_hub_app/team/team_history_recovery.dart';
import 'package:mercantis_hub_app/team/team_naming.dart';
import 'package:mercantis_hub_app/team/team_posting_guard.dart';
import 'package:mercantis_hub_app/team/team_posting_service.dart';
import 'package:mercantis_hub_app/team/team_session.dart';
import 'package:mercantis_hub_app/team/team_sync_runner.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/books_harness.dart';

/// C4 — the Team server is restored from a backup while devices hold newer
/// history. Real devices (SQLite books, the real sync runner) against a
/// REAL backend whose PostgreSQL database is snapshotted with `pg_dump` and
/// restored with `pg_restore --clean`, exactly as `scripts/restore.sh` does.
///
/// Needs `ATLAS_TEAM_E2E_URL` and `ATLAS_E2E_DB_URL` (the backend's
/// database). Restoring rewinds the WHOLE database, so `tool/team_e2e.sh`
/// runs this file on its own, after the other end-to-end files.
void main() {
  sqfliteFfiInit();
  final baseUrl = Platform.environment['ATLAS_TEAM_E2E_URL'];
  final dbUrl = Platform.environment['ATLAS_E2E_DB_URL'];
  final skip = baseUrl == null || dbUrl == null
      ? 'set ATLAS_TEAM_E2E_URL and ATLAS_E2E_DB_URL (tool/team_e2e.sh)'
      : null;

  late Directory root;
  final devices = <_Device>[];
  var snapshots = 0;

  setUp(
      () async => root = await Directory.systemTemp.createTemp('team-restore'));
  tearDown(() async {
    for (final d in devices) {
      await d.close();
    }
    devices.clear();
    if (root.existsSync()) await root.delete(recursive: true);
  });

  /// A backup of the server's database, as the nightly job takes it.
  Future<String> backup() async {
    final file = p.join(root.path, 'backup-${snapshots++}.dump');
    final r = await Process.run('pg_dump', ['-Fc', '-f', file, dbUrl!]);
    expect(r.exitCode, 0, reason: '${r.stderr}');
    return file;
  }

  /// The operator restores it over the live database.
  Future<void> restore(String file) async {
    final r = await Process.run('pg_restore', [
      '--clean',
      '--if-exists',
      '--no-owner',
      '--single-transaction',
      '-d',
      dbUrl!,
      file,
    ]);
    expect(r.exitCode, 0, reason: '${r.stderr}');
  }

  /// One company: owner A, admin B and till T, with masters and 24 bottles
  /// in stock, every device synced.
  Future<(_Device, _Device, _Device)> company() async {
    final account = TeamAccountClient(baseUrl: baseUrl!);
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final a = await _Device.open(root, 'a-$stamp', seed: true);
    devices.add(a);
    a.session = await account.createAndConnect(
      companyName: 'Restore $stamp',
      ownerEmail: 'owner-$stamp@e2e.test',
      ownerName: 'Owner',
      deviceName: 'Office',
    );
    await a.sync();
    Future<_Device> join(String name, String role) async {
      final invite = await account.createInvitation(
        companyId: a.session.companyId,
        authToken: a.session.userToken,
        email: '$name-$stamp@e2e.test',
        role: role,
      );
      final d = await _Device.open(root, '$name-$stamp', seed: false);
      devices.add(d);
      d.session = await account.joinAndConnect(
        invitationToken: invite.token,
        displayName: name,
        deviceName: name,
      );
      await d.sync();
      return d;
    }

    final b = await join('b', 'admin');
    final t = await join('till', 'pos');
    await a.h.save(Document(id: 'BOTTLE', docType: 'Item', payload: {
      'item_code': 'BOTTLE',
      'item_name': 'Bottle',
      'item_type': 'Stock',
      'stock_uom': 'Nos',
      'valuation_method': 'Moving Average',
    }));
    await a.h.save(Document(
        id: 'S-1',
        docType: 'Supplier',
        payload: {'supplier_name': 'Glassworks'}));
    await a.h.save(Document(id: 'C-1', docType: 'Customer', payload: {
      'customer_name': 'Harbour Bar',
      'customer_type': 'Company',
    }));
    await a.serverSubmit(await a.h.save(_purchase(24, 5)));
    for (final d in [a, b, t]) {
      await d.sync();
    }
    return (a, b, t);
  }

  /// A device joining after the restore: the server's books as they are.
  Future<_Device> witness(_Device owner) async {
    final account = TeamAccountClient(baseUrl: baseUrl!);
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final invite = await account.createInvitation(
      companyId: owner.session.companyId,
      authToken: owner.session.userToken,
      email: 'w-$stamp@e2e.test',
      role: 'accountant',
    );
    final w = await _Device.open(root, 'w-$stamp', seed: false);
    devices.add(w);
    w.session = await account.joinAndConnect(
      invitationToken: invite.token,
      displayName: 'witness',
      deviceName: 'witness',
    );
    await w.sync();
    return w;
  }

  /// Pads the server log with master edits from [d] until it reaches
  /// exactly [version].
  Future<void> padTo(_Device d, int version) async {
    var n = 0;
    while (true) {
      final head = (await d.posting.historyAt(0))!.head;
      if (head >= version) {
        expect(head, version, reason: 'padding overshot');
        return;
      }
      final c = (await d.h.engine.fetch('Customer', 'C-1'))!;
      c.payload['customer_name'] = 'Harbour Bar ${n++}';
      await d.h.save(c);
      await d.syncPlain();
    }
  }

  Future<PreparedTeamRecovery> recover(_Device d, {http.Client? client}) async {
    final divergence = (await d.history.diverged(d.session.companyId))!;
    final recovery = TeamHistoryRecovery(
      live: d.h.db.db,
      session: d.session,
      localDeviceId: d.id,
      factory: databaseFactoryFfi,
      client: client,
    );
    return recovery.prepare(
      divergence: divergence,
      recoveryId: 'rec-${d.id}',
      stagingPath: p.join(root.path, 'staging-${d.id}', 'mercantis.db'),
    );
  }

  /// The switch, as the Recover screen does it with Atlas stopped.
  Future<void> switchOver(_Device d, PreparedTeamRecovery prepared) async {
    await d.h.close();
    await TeamHistoryRecovery.switchOver(
      prepared: prepared,
      liveDatabasePath: d.path,
      archiveDirectory: p.join(root.path, 'archive-${d.id}'),
      factory: databaseFactoryFfi,
      companyId: d.session.companyId,
      cursorStore: d.cursor,
      historyStore: d.history,
    );
    await d.reopen();
  }

  Future<void> sameAsServer(_Device d, _Device witness) async {
    await witness.sync();
    expect(await d.balances(), await witness.balances(), reason: 'GL');
    expect(await d.parties(), await witness.parties(), reason: 'AR/AP');
    expect(await d.stock(), await witness.stock(), reason: 'stock');
    expect(await d.h.trialBalanceDifference(), 0);
  }

  test('1. restored behind the cursor, no new activity', () async {
    final (a, b, _) = await company();
    final file = await backup();
    final lost = await a.serverSubmit(await a.h.save(_sale(3, 12)));
    await b.sync();
    await restore(file);

    await expectLater(a.sync(), throwsA(isA<TeamHistoryDiverged>()));
    expect((await a.history.diverged(a.session.companyId))!.logBehind, isTrue);
    // Paused until recovered: the next attempt does not even reach the log.
    await expectLater(a.sync(), throwsA(isA<TeamHistoryDiverged>()));

    final prepared = await recover(a);
    final report = prepared.report;
    expect(report.lost.map((l) => l.number), [lost['number']]);
    expect(report.lostReported, isTrue);
    expect(report.numberReused, isEmpty);
    expect(report.canSwitch, isTrue);
    await switchOver(a, prepared);
    final w = await witness(a);
    await sameAsServer(a, w);
    expect(asNum((await a.bin('BOTTLE'))!.payload['actual_qty']), 24,
        reason: 'stock is the server’s again');

    // The lost number is never issued again.
    final next = await a.serverSubmit(await a.h.save(_sale(1, 12)));
    expect(_n(next['number']), greaterThan(_n(lost['number'])));
    // B recovers on its own.
    await expectLater(b.sync(), throwsA(isA<TeamHistoryDiverged>()));
  }, skip: skip, timeout: const Timeout(Duration(minutes: 5)));

  test('2. restored and advanced to exactly the old cursor', () async {
    final (a, b, _) = await company();
    final file = await backup();
    await a.serverSubmit(await a.h.save(_sale(2, 12)));
    final checkpoint = (await a.history.verified(a.session.companyId))!;
    await restore(file);
    // B last synced before A's sale, so its own view survives the restore.
    await padTo(b, checkpoint.version);

    // Same numeric head, different history.
    expect((await a.posting.historyAt(0))!.head, checkpoint.version);
    await expectLater(a.sync(), throwsA(isA<TeamHistoryDiverged>()));
    final prepared = await recover(a);
    expect(prepared.report.lost, hasLength(1));
    await switchOver(a, prepared);
    await sameAsServer(a, await witness(a));
  }, skip: skip, timeout: const Timeout(Duration(minutes: 5)));

  test('3 and 4. advanced beyond the cursor with a conflicting sale', () async {
    final (a, b, _) = await company();
    final file = await backup();
    final mine = await a.serverSubmit(await a.h.save(_sale(3, 12)));
    final checkpoint = (await a.history.verified(a.session.companyId))!;
    await restore(file);
    // After the restore B sells something else: the server gives it the
    // number A's lost sale had, and the log grows past A's cursor.
    final theirs = await b.serverSubmit(await b.h.save(_sale(5, 10)));
    expect(theirs['number'], mine['number']);
    await padTo(b, checkpoint.version + 3);

    await expectLater(a.sync(), throwsA(isA<TeamHistoryDiverged>()));
    expect((await a.history.diverged(a.session.companyId))!.logBehind, isFalse);
    final prepared = await recover(a);
    final r = prepared.report;
    expect(r.lost.single.number, mine['number']);
    expect(r.numberReused.single['number'], mine['number']);
    expect(r.numberReused.single['server_document_id'],
        isNot(r.lost.single.documentId));
    await switchOver(a, prepared);
    await sameAsServer(a, await witness(a));
    // Nineteen bottles: 24 bought, 5 sold by B; A's lost sale is not there.
    expect(asNum((await a.bin('BOTTLE'))!.payload['actual_qty']), 19);
    final next = await a.serverSubmit(await a.h.save(_sale(1, 12)));
    expect(_n(next['number']), greaterThan(_n(mine['number'])));
  }, skip: skip, timeout: const Timeout(Duration(minutes: 5)));

  test('5. the connection drops halfway through the recovery', () async {
    final (a, _, _) = await company();
    final file = await backup();
    await a.serverSubmit(await a.h.save(_sale(3, 12)));
    await restore(file);
    await expectLater(a.sync(), throwsA(isA<TeamHistoryDiverged>()));

    final flaky = _DropAfter(4);
    await expectLater(recover(a, client: flaky), throwsA(anything));
    // Nothing changed on the device: same books, still paused.
    expect(asNum((await a.bin('BOTTLE'))!.payload['actual_qty']), 21);
    expect(await a.history.diverged(a.session.companyId), isNotNull);
    await expectLater(a.sync(), throwsA(isA<TeamHistoryDiverged>()));

    // Run again: it completes.
    final prepared = await recover(a);
    expect(prepared.report.lost, hasLength(1));
    await switchOver(a, prepared);
    await sameAsServer(a, await witness(a));
    await a.sync();
  }, skip: skip, timeout: const Timeout(Duration(minutes: 5)));

  test('6. unsent drafts and drafts the restore lost are kept', () async {
    final (a, b, _) = await company();
    final file = await backup();
    // Sent before the restore (so lost with it), and one never sent.
    await a.h.save(Document(id: 'C-SENT', docType: 'Customer', payload: {
      'customer_name': 'Sent Before',
      'customer_type': 'Company',
    }));
    await a.sync();
    await restore(file);
    await a.h.save(Document(id: 'C-NEW', docType: 'Customer', payload: {
      'customer_name': 'Never Sent',
      'customer_type': 'Company',
    }));
    final draft = await a.h.save(_sale(2, 12));
    await expectLater(a.sync(), throwsA(isA<TeamHistoryDiverged>()));

    final prepared = await recover(a);
    expect(prepared.report.lost, isEmpty, reason: 'no official record lost');
    expect(prepared.report.carried.join(' '),
        allOf(contains('C-NEW'), contains('C-SENT'), contains(draft.id)));
    await switchOver(a, prepared);
    for (final id in ['C-NEW', 'C-SENT']) {
      expect(await a.h.engine.fetch('Customer', id), isNotNull, reason: id);
    }
    expect((await a.h.engine.fetch('Sales Invoice', draft.id))!.docStatus, 0);
    await a.sync(); // sent now
    final w = await witness(a);
    for (final id in ['C-NEW', 'C-SENT']) {
      expect(await w.h.engine.fetch('Customer', id), isNotNull,
          reason: '$id reached the server');
    }
    // And the draft can be posted as usual.
    final posted = await a.postNow(draft);
    expect(posted['number'], isNotNull);
  }, skip: skip, timeout: const Timeout(Duration(minutes: 5)));

  test('7. an offline till sale waiting for confirmation', () async {
    final (a, _, t) = await company();
    final file = await backup();
    // The till saw a sale from A that the restore then loses.
    final lost = await a.serverSubmit(await a.h.save(_sale(3, 12)));
    await t.sync();
    await restore(file);
    // The till sells offline after the restore and before it syncs.
    final sale = await t.h.saveAndSubmit(_till(4, 2.5));
    await expectLater(t.sync(), throwsA(isA<TeamHistoryDiverged>()));
    expect(
        (await t.h.engine.fetch('POS Invoice', sale.id))!
            .payload['official_number'],
        isNull);

    final prepared = await recover(t);
    expect(prepared.report.pendingTillSales.single, contains(sale.id));
    expect(prepared.report.lost.single.number, lost['number']);
    // A till may not move numbering: the list waits for an accountant.
    expect(prepared.report.lostReported, isFalse);
    expect(prepared.report.reportProblem, contains('accountant'));
    await switchOver(t, prepared);
    final back = await t.sync();
    expect(back.confirmedTillSales, 1);
    await t.sync();
    expect(asNum((await t.bin('BOTTLE'))!.payload['actual_qty']), 20);
    await sameAsServer(t, await witness(a));
  }, skip: skip, timeout: const Timeout(Duration(minutes: 5)));

  test('8. several devices recover independently', () async {
    final (a, b, t) = await company();
    final file = await backup();
    final lostA = await a.serverSubmit(await a.h.save(_sale(1, 12)));
    final lostB = await b.serverSubmit(await b.h.save(_sale(2, 12)));
    for (final d in [a, b, t]) {
      await d.sync();
    }
    await restore(file);
    for (final d in [a, b, t]) {
      await expectLater(d.sync(), throwsA(isA<TeamHistoryDiverged>()),
          reason: d.id);
    }
    for (final d in [b, a, t]) {
      final prepared = await recover(d);
      // Each device saw both sales and reports both; the server takes the
      // reports idempotently per device.
      expect(prepared.report.lost.map((l) => l.number).toSet(),
          {lostA['number'], lostB['number']},
          reason: d.id);
      await switchOver(d, prepared);
      await d.sync();
    }
    final w = await witness(a);
    for (final d in [a, b, t]) {
      await sameAsServer(d, w);
    }
    final next = await a.serverSubmit(await a.h.save(_sale(1, 12)));
    expect(_n(next['number']), greaterThan(_n(lostB['number'])));
  }, skip: skip, timeout: const Timeout(Duration(minutes: 8)));
}

int _n(Object? number) =>
    int.parse(RegExp(r'(\d+)$').firstMatch('$number')!.group(1)!);

class _MemCursor implements TeamSyncCursorStore {
  int value = 0;
  @override
  Future<int> load(String companyId) async => value;
  @override
  Future<void> save(String companyId, int cursor) async => value = cursor;
}

/// An HTTP client whose connection drops after [n] requests.
class _DropAfter extends http.BaseClient {
  _DropAfter(this.n);
  int n;
  final _inner = http.Client();
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (n-- <= 0) throw const SocketException('connection dropped');
    return _inner.send(request);
  }
}

class _Device {
  _Device(this.id, this.path, this.h);

  final String id;
  final String path;
  BooksHarness h;
  final cursor = _MemCursor();
  final history = MemoryTeamHistoryStore();
  TeamSession? _session;
  TeamSession get session => _session!;
  set session(TeamSession s) => _session = s;
  MetadataRegistry get registry => MetadataRegistry(h.db.db);
  late final posting = TeamPostingClient(
    baseUrl: session.baseUrl,
    companyId: session.companyId,
    deviceToken: session.deviceToken,
    history: history,
  );

  static Future<BooksHarness> _open(
          String path, String id, bool seed, String? Function() tag) =>
      BooksHarness.open(
        path,
        deviceId: id,
        seed: seed,
        interceptors: [
          TeamPostingAuthorityGuard(() => true),
          ...hubInterceptors,
        ],
        namingService: TeamScopedNamingService(tag),
      );

  static Future<_Device> open(Directory root, String id,
      {required bool seed}) async {
    _Device? device;
    final path = p.join(root.path, '$id.db');
    final h = await _open(path, id, seed, () {
      final s = device?._session;
      return s == null ? null : teamDeviceTag(s.deviceId);
    });
    return device = _Device(id, path, h);
  }

  /// Opens the (switched) live book again, as the app does after restart.
  Future<void> reopen() async {
    h = await _open(path, id, false, () => teamDeviceTag(session.deviceId));
  }

  Future<TeamSyncResult> sync() => runTeamSync(
        session: session,
        database: h.db.db,
        registry: registry,
        localDeviceId: id,
        cursorStore: cursor,
        historyStore: history,
      );

  /// A sync with no history check (padding the log in the tests).
  Future<void> syncPlain() async {
    final adapter = TeamAccountClient.adapterFor(session);
    try {
      await TeamSyncRunner(
        database: h.db.db,
        registry: registry,
        adapter: adapter,
        localDeviceId: id,
        companyId: session.companyId,
        cursorStore: cursor,
        historyStore: MemoryTeamHistoryStore(),
      ).run();
    } finally {
      adapter.close();
    }
  }

  Future<Map<String, dynamic>> serverSubmit(Document draft) async {
    await sync();
    final result = await postNow(draft);
    await sync();
    return result;
  }

  Future<Map<String, dynamic>> postNow(Document draft) async =>
      posting.submitDocument(
          buildSubmitCommand((await h.engine.fetch(draft.docType, draft.id))!));

  Future<Document?> bin(String item) async {
    final bins = await h.engine
        .list('Bin', filters: {'item': item}, userRoles: systemRoles);
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

  Future<Map<String, num>> parties() async {
    final out = <String, num>{};
    for (final r in await h.engine.list('GL Entry', userRoles: systemRoles)) {
      final party = '${r.payload['party'] ?? ''}';
      if (party.isEmpty) continue;
      out[party] = round2((out[party] ?? 0) +
          asNum(r.payload['debit']) -
          asNum(r.payload['credit']));
    }
    out.removeWhere((_, v) => v == 0);
    return out;
  }

  Future<Map<String, String>> stock() async => {
        for (final b in await h.engine.list('Bin', userRoles: systemRoles))
          '${b.payload['item']}@${b.payload['warehouse']}':
              '${asNum(b.payload['actual_qty'])}/${round2(asNum(b.payload['stock_value']))}',
      };

  Future<void> close() async {
    if (_session != null) posting.close();
    try {
      await h.close();
    } catch (_) {}
  }
}

Document _purchase(num qty, num rate) =>
    Document(id: '', docType: 'Purchase Invoice', payload: {
      'supplier': 'S-1',
      'posting_date': isoToday(),
      'due_date': isoToday(),
      'update_stock': 1,
      'set_warehouse': 'Main Store',
    })
      ..children['items'] = [
        itemLine('Purchase Invoice', {
          'item': 'BOTTLE',
          'qty': qty,
          'rate': rate,
          'warehouse': 'Main Store',
        }),
      ];

Document _sale(num qty, num rate) =>
    Document(id: '', docType: 'Sales Invoice', payload: {
      'customer': 'C-1',
      'posting_date': isoToday(),
      'due_date': isoToday(),
      'update_stock': 1,
      'set_warehouse': 'Main Store',
    })
      ..children['items'] = [
        itemLine('Sales Invoice', {
          'item': 'BOTTLE',
          'qty': qty,
          'rate': rate,
          'warehouse': 'Main Store',
        }),
      ];

Document _till(num qty, num rate) => PosCheckout.buildPosInvoice(
      postingDate: isoToday(),
      tillSeries: 'TILL1',
      warehouse: 'Main Store',
      lines: [
        PosCartLine(
            item: 'BOTTLE', qty: qty, rate: rate, warehouse: 'Main Store')
      ],
      tenders: [PosTender(type: 'Cash', amount: round2(qty * rate * 1.18))],
    );
