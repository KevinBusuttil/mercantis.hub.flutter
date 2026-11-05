@Tags(['team-e2e'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_hub_app/ledger/hub_interceptors.dart';
import 'package:mercantis_hub_app/ledger/ledger_values.dart' show asNum, round2;
import 'package:mercantis_hub_app/team/solo_to_team.dart';
import 'package:mercantis_hub_app/team/solo_to_team_runner.dart';
import 'package:mercantis_hub_app/team/team_account_client.dart';
import 'package:mercantis_hub_app/team/team_naming.dart';
import 'package:mercantis_hub_app/team/team_posting_guard.dart';
import 'package:mercantis_hub_app/team/team_posting_service.dart';
import 'package:mercantis_hub_app/team/team_session.dart';
import 'package:mercantis_hub_app/team/team_sync_runner.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/books_harness.dart';

/// C3 on a REAL Atlas Team backend (PostgreSQL behind it): a Solo book that
/// has bought, sold and been paid moves into a new Team company once, is
/// reconciled to the cent, and carries on in Team: numbering continues after
/// the Solo numbers, stock costs from the Solo valuation, and a second
/// device joins the same books. Run with tool/team_e2e.sh.
void main() {
  sqfliteFfiInit();
  final baseUrl = Platform.environment['ATLAS_TEAM_E2E_URL'];
  final skip = baseUrl == null ? 'set ATLAS_TEAM_E2E_URL' : null;

  late Directory root;
  setUp(() async => root = await Directory.systemTemp.createTemp('solo-team'));
  tearDown(() async {
    if (root.existsSync()) await root.delete(recursive: true);
  });

  /// A Solo book with history: a stock purchase, two sales (one paid) and a
  /// service sale. Returns the harness, still open.
  Future<BooksHarness> soloBook(String path) async {
    final h = await BooksHarness.open(path, deviceId: 'solo-phone');
    await h.save(Document(id: 'C-1', docType: 'Customer', payload: {
      'customer_name': 'Harbour Bar',
      'customer_type': 'Company',
    }));
    await h.save(Document(id: 'S-1', docType: 'Supplier', payload: {
      'supplier_name': 'Glassworks',
    }));
    await h.save(Document(id: 'BOTTLE', docType: 'Item', payload: {
      'item_code': 'BOTTLE',
      'item_name': 'Bottle',
      'item_type': 'Stock',
      'stock_uom': 'Nos',
      'valuation_method': 'Moving Average',
    }));
    await h
        .saveAndSubmit(Document(id: '', docType: 'Purchase Invoice', payload: {
      'supplier': 'S-1',
      'posting_date': isoToday(),
      'due_date': isoToday(),
      'update_stock': 1,
      'set_warehouse': 'Main Store',
    })
          ..children['items'] = [
            itemLine('Purchase Invoice', {
              'item': 'BOTTLE',
              'qty': 24,
              'rate': 5,
              'warehouse': 'Main Store'
            }),
          ]);
    for (final qty in [3, 2]) {
      await h
          .saveAndSubmit(Document(id: '', docType: 'Sales Invoice', payload: {
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
                'rate': 12,
                'warehouse': 'Main Store'
              }),
            ]);
    }
    return h;
  }

  Future<Map<String, num>> balances(Database db) async {
    final figures = await SoloToTeamConversion(db).figures();
    return figures.trialBalance;
  }

  test(
      'connecting a Solo book with history directly splits the books '
      '(the C3 reproduction)', () async {
    final h = await soloBook(p.join(root.path, 'solo.db'));
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final account = TeamAccountClient(baseUrl: baseUrl!);
    final session = await account.createAndConnect(
      companyName: 'Split $stamp',
      ownerEmail: 'split-$stamp@e2e.test',
      ownerName: 'Owner',
      deviceName: 'Solo phone',
    );
    Future<TeamSyncResult> sync() => runTeamSync(
          session: session,
          database: h.db.db,
          registry: MetadataRegistry(h.db.db),
          localDeviceId: 'solo-phone',
          cursorStore: _MemCursor(),
        );
    // The first sync is refused: the Solo submits are official state.
    await expectLater(
        sync(),
        throwsA(isA<CloudHttpException>()
            .having((e) => e.statusCode, 'status', 422)));
    // The engine quarantines the refused submits and ships everything else,
    // so the next sync "succeeds"…
    await sync();
    final failed = await h.db.db.query('sync_queue',
        where: 'status = ? AND doctype = ?',
        whereArgs: [MutationStatus.failed.name, 'Sales Invoice']);
    expect(failed, isNotEmpty, reason: 'Solo submits are stuck as failed');

    // …and a teammate now sees the Solo invoices as unposted drafts, with no
    // ledger, while the phone keeps them posted: two different sets of books,
    // and drafts that the server would number a second time if submitted.
    final invite = await account.createInvitation(
      companyId: session.companyId,
      authToken: session.userToken,
      email: 'mate-$stamp@e2e.test',
      role: 'admin',
    );
    final mate = await BooksHarness.open(p.join(root.path, 'mate.db'),
        deviceId: 'mate', seed: false);
    await runTeamSync(
      session: await account.joinAndConnect(
          invitationToken: invite.token,
          displayName: 'Mate',
          deviceName: 'Mate'),
      database: mate.db.db,
      registry: MetadataRegistry(mate.db.db),
      localDeviceId: 'mate',
      cursorStore: _MemCursor(),
    );
    final mateInvoices = await mate.db.db
        .query('documents', where: 'doctype = ?', whereArgs: ['Sales Invoice']);
    expect(mateInvoices, isNotEmpty);
    expect(mateInvoices.every((r) => r['docstatus'] == 0), isTrue,
        reason: 'the teammate sees the issued invoices as drafts');
    expect(await mate.rowCount('GL Entry'), 0);
    expect(await h.rowCount('GL Entry'), greaterThan(0));

    // The fix: such a book is offered the conversion instead.
    expect(await soloHistoryCount(h.db.db), greaterThan(0));
    await mate.close();
    await h.close();
  }, skip: skip, timeout: const Timeout(Duration(minutes: 3)));

  test('a Solo book moves into Team once, reconciled, and carries on',
      () async {
    final livePath = p.join(root.path, 'mercantis.db');
    final solo = await soloBook(livePath);
    final soloBalances = await balances(solo.db.db);
    final soloBin = await solo.bin('BOTTLE', 'Main Store');
    final lastSoloInvoice =
        (await SoloToTeamConversion(solo.db.db).lastIssuedNumbers())
            .firstWhere((n) => n['doctype'] == 'Sales Invoice');
    final cutover = isoToday();

    final pre = await SoloToTeamConversion(solo.db.db)
        .preflight(cutoverDate: cutover, teamConnected: false);
    expect(pre.blockers.map((c) => c.message), isEmpty);

    final stamp = DateTime.now().microsecondsSinceEpoch;
    final account = TeamAccountClient(baseUrl: baseUrl!);
    final session = await account.createAndConnect(
      companyName: 'Moved $stamp',
      ownerEmail: 'moved-$stamp@e2e.test',
      ownerName: 'Owner',
      deviceName: 'Solo phone',
    );
    final cursor = _MemCursor();
    final runner = SoloToTeamRunner(
      solo: solo.db.db,
      localDeviceId: 'solo-phone',
      factory: databaseFactoryFfi,
      cursorStore: cursor,
    );
    final migrationId = 'mig-$stamp';
    final teamPath = p.join(root.path, 'team-staging', 'mercantis.db');
    final outcome = await runner.run(
      session: session,
      migrationId: migrationId,
      cutoverDate: cutover,
      teamBookPath: teamPath,
      source: const {'test': 'solo_to_team_e2e'},
    );
    expect(outcome.serverResponse['replayed'], false);
    final next = (lastSoloInvoice['last_value'] as int) + 1;
    final nextNumber = 'SINV-${next.toString().padLeft(5, '0')}';
    expect(outcome.numberingLines.join('\n'),
        contains('Team continues at $nextNumber'));

    // Repeating the whole run (a crash before the switch) is safe: the
    // server replays the same take-on and the Team book is rebuilt.
    final again = await runner.run(
      session: session,
      migrationId: migrationId,
      cutoverDate: cutover,
      teamBookPath: teamPath,
      source: const {'test': 'solo_to_team_e2e'},
    );
    expect(again.serverResponse['replayed'], true);

    // A second, different take-on into the same company is refused.
    await expectLater(
      SoloToTeamRunner(
        solo: solo.db.db,
        localDeviceId: 'solo-phone',
        factory: databaseFactoryFfi,
        cursorStore: _MemCursor(),
      ).run(
        session: session,
        migrationId: '$migrationId-b',
        cutoverDate: cutover,
        teamBookPath: p.join(root.path, 'other', 'mercantis.db'),
      ),
      throwsA(
          isA<CloudHttpException>().having((e) => e.statusCode, 'status', 409)),
    );

    // ---- Switch: the Solo book is archived, the Team book takes its place.
    await solo.close();
    final archived = await SoloToTeamRunner.switchToTeamBook(
      liveDatabasePath: livePath,
      teamBookPath: teamPath,
      archiveDirectory: p.join(root.path, 'solo-archive', migrationId),
      factory: databaseFactoryFfi,
    );
    final archive = await databaseFactoryFfi.openDatabase(archived);
    expect(await balances(archive), soloBalances,
        reason: 'the archive is the Solo book, unchanged');
    expect(await soloHistoryCount(archive), greaterThan(0));
    await archive.close();

    _Device? device;
    final team = await BooksHarness.open(
      livePath,
      deviceId: 'solo-phone',
      seed: false,
      interceptors: [TeamPostingAuthorityGuard(() => true), ...hubInterceptors],
      namingService: TeamScopedNamingService(
          () => device == null ? null : teamDeviceTag(session.deviceId)),
    );
    device = _Device('solo-phone', team, session, cursor);
    expect(await balances(team.db.db), soloBalances,
        reason: 'the Team book opens with the Solo position, to the cent');
    expect(await soloHistoryCount(team.db.db), 1,
        reason: 'only the opening entry is official in the Team book');
    final teamBin = await team.bin('BOTTLE', 'Main Store');
    expect(asNum(teamBin!.payload['actual_qty']),
        asNum(soloBin!.payload['actual_qty']));
    expect(round2(asNum(teamBin.payload['stock_value'])),
        round2(asNum(soloBin.payload['stock_value'])));

    // ---- Team carries on: the next invoice follows the Solo numbering and
    // costs from the opening stock.
    final sale = await device.serverSubmit(
        await team.save(Document(id: '', docType: 'Sales Invoice', payload: {
      'customer': 'C-1',
      'posting_date': isoToday(),
      'due_date': isoToday(),
      'update_stock': 1,
      'set_warehouse': 'Main Store',
    })
          ..children['items'] = [
            itemLine('Sales Invoice', {
              'item': 'BOTTLE',
              'qty': 4,
              'rate': 12,
              'warehouse': 'Main Store'
            }),
          ]));
    expect(sale['number'], nextNumber);
    expect(
        asNum((await team.bin('BOTTLE', 'Main Store'))!.payload['actual_qty']),
        asNum(soloBin.payload['actual_qty']) - 4);
    expect(await team.trialBalanceDifference(), 0);

    // ---- A second device joins and sees the same books.
    final invite = await account.createInvitation(
      companyId: session.companyId,
      authToken: session.userToken,
      email: 'laptop-$stamp@e2e.test',
      role: 'admin',
    );
    final laptop = await BooksHarness.open(p.join(root.path, 'laptop.db'),
        deviceId: 'laptop',
        seed: false,
        interceptors: [
          TeamPostingAuthorityGuard(() => true),
          ...hubInterceptors
        ]);
    final laptopSession = await account.joinAndConnect(
      invitationToken: invite.token,
      displayName: 'Laptop',
      deviceName: 'Laptop',
    );
    await runTeamSync(
      session: laptopSession,
      database: laptop.db.db,
      registry: MetadataRegistry(laptop.db.db),
      localDeviceId: 'laptop',
      cursorStore: _MemCursor(),
    );
    expect(await balances(laptop.db.db), await balances(team.db.db));
    await laptop.close();
    await device.close();
  }, skip: skip, timeout: const Timeout(Duration(minutes: 5)));
}

class _MemCursor implements TeamSyncCursorStore {
  int value = 0;
  @override
  Future<int> load(String companyId) async => value;
  @override
  Future<void> save(String companyId, int cursor) async => value = cursor;
}

class _Device {
  _Device(this.id, this.h, this.session, this.cursor);
  final String id;
  final BooksHarness h;
  final TeamSession session;
  final _MemCursor cursor;
  late final posting = TeamPostingClient(
    baseUrl: session.baseUrl,
    companyId: session.companyId,
    deviceToken: session.deviceToken,
  );

  Future<TeamSyncResult> sync() => runTeamSync(
        session: session,
        database: h.db.db,
        registry: MetadataRegistry(h.db.db),
        localDeviceId: id,
        cursorStore: cursor,
      );

  Future<Map<String, dynamic>> serverSubmit(Document draft) async {
    await sync();
    final result = await posting.submitDocument(
        buildSubmitCommand((await h.engine.fetch(draft.docType, draft.id))!));
    await sync();
    return result;
  }

  Future<void> close() async {
    posting.close();
    await h.close();
  }
}
