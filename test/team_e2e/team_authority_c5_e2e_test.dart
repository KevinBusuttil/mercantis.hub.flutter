@Tags(['team-e2e'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_hub_app/ledger/hub_interceptors.dart';
import 'package:mercantis_hub_app/ledger/ledger_values.dart' show asNum, round2;
import 'package:mercantis_hub_app/team/team_account_client.dart';
import 'package:mercantis_hub_app/team/team_books_lock.dart';
import 'package:mercantis_hub_app/team/team_history.dart';
import 'package:mercantis_hub_app/team/team_naming.dart';
import 'package:mercantis_hub_app/team/team_posting_guard.dart';
import 'package:mercantis_hub_app/team/team_posting_service.dart';
import 'package:mercantis_hub_app/team/team_session.dart';
import 'package:mercantis_hub_app/team/team_sync_runner.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/books_harness.dart';

/// C5 on a real backend: Journal Entry, Expense and Customer Deposit are
/// posted by the Team server from real hub drafts, every device converges,
/// deposit application is atomic across devices, and the books lock is the
/// server's (permissions, stale devices, backdated offline drafts).
///
/// Devices: A (owner), B (accountant), S (sales). Skipped unless
/// `ATLAS_TEAM_E2E_URL` is set (`tool/team_e2e.sh`).
void main() {
  sqfliteFfiInit();
  final baseUrl = Platform.environment['ATLAS_TEAM_E2E_URL'];
  final skip = baseUrl == null
      ? 'set ATLAS_TEAM_E2E_URL to a running Atlas Team backend'
      : null;

  late Directory root;
  final devices = <_Device>[];
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    root = await Directory.systemTemp.createTemp('team-c5');
  });
  tearDown(() async {
    for (final d in devices) {
      await d.close();
    }
    devices.clear();
    if (root.existsSync()) await root.delete(recursive: true);
  });

  test('journals, expenses, deposits and the books lock are the server\'s',
      () async {
    final account = TeamAccountClient(baseUrl: baseUrl!);
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final today = isoToday();
    final yesterday = DateTime.now()
        .subtract(const Duration(days: 1))
        .toIso8601String()
        .split('T')
        .first;

    final a = await _Device.open(root, 'device-a', seed: true);
    devices.add(a);
    a.session = await account.createAndConnect(
      companyName: 'C5 Trading $stamp',
      ownerEmail: 'owner-$stamp@e2e.test',
      ownerName: 'Owner',
      deviceName: 'Office PC',
    );
    await a.sync();
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
          invitationToken: invite.token, displayName: id, deviceName: id);
      await d.sync();
      return d;
    }

    final b = await join('device-b', 'accountant');
    final s = await join('device-s', 'sales');

    await a.h.save(Document(id: 'C-1', docType: 'Customer', payload: {
      'customer_name': 'Harbour Bar',
      'customer_type': 'Company',
    }));
    await a.h.save(Document(id: 'Office Costs', docType: 'Account', payload: {
      'account_name': 'Office Costs',
      'root_type': 'Expense',
      'parent_account': 'Expenses',
      'is_group': '0',
    }));
    for (final d in [a, b, s]) {
      await d.sync();
    }

    // ---- A local submit of the three is still refused: the server posts.
    final local = await b.h.save(_journal(today, 40, customer: 'C-1'));
    await expectLater(
      b.h.submit(local),
      throwsA(isA<DocumentEngineError>().having((e) => e.humanMessage,
          'message', contains('posted by the Team server'))),
    );

    // ---- Journal Entry from the accountant: numbered, same everywhere.
    final je = await b.serverSubmit(local);
    expect('${je['number']}', startsWith('JV-'));
    for (final d in [a, b, s]) {
      await d.sync();
    }
    for (final d in [a, b, s]) {
      expect((await d.h.engine.fetch('Journal Entry', local.id))!.docStatus, 1,
          reason: d.id);
      final ct =
          await d.h.engine.fetch('Customer Transaction', 'CT-${local.id}-0');
      expect(asNum(ct?.payload['amount']), 40,
          reason: '${d.id}: customer owes');
    }
    // Sales may not post a journal.
    final salesJe = await s.h.save(_journal(today, 5));
    await s.sync();
    await expectLater(
        s.postNow(salesJe),
        throwsA(isA<CloudHttpException>()
            .having((e) => e.statusCode, 'status', 403)));

    // ---- Expense: paid from Bank with VAT. Solo fills gross and the VAT
    // account on save; the server posts the same legs.
    final exp = await a.h.save(Document(id: '', docType: 'Expense', payload: {
      'posting_date': today,
      'description': 'Printer paper',
      'expense_account': 'Office Costs',
      'net_amount': 100,
      'tax_amount': 18,
      'is_paid': 1,
    }));
    expect(exp.payload['gross_amount'], 118);
    final expRes = await a.serverSubmit(exp);
    expect('${expRes['number']}', startsWith('EXP-'));
    // Against a group account: refused by the server (the synced chart says
    // `Expenses` is a group), nothing posted.
    final toGroup =
        await a.h.save(Document(id: '', docType: 'Expense', payload: {
      'posting_date': today,
      'description': 'Misc',
      'expense_account': 'Expenses',
      'net_amount': 10,
      'tax_amount': 0,
      'is_paid': 1,
    }));
    await a.sync();
    await expectLater(
        a.postNow(toGroup),
        throwsA(isA<CloudHttpException>()
            .having((e) => e.message, 'message', contains('group'))));

    // ---- Customer Deposit from sales, then applications.
    final dep =
        await s.h.save(Document(id: '', docType: 'Customer Deposit', payload: {
      'customer': 'C-1',
      'posting_date': today,
      'amount': 500,
    }));
    final depRes = await s.serverSubmit(dep);
    expect('${depRes['number']}', startsWith('DEP-'));
    for (final d in [a, b]) {
      await d.sync();
    }
    Future<Document> applying(_Device d, num amount) =>
        d.h.save(Document(id: '', docType: 'Payment Entry', payload: {
          'payment_type': 'Receive',
          'posting_date': today,
          'deposit': dep.id,
          'paid_amount': amount,
        }));
    final first = await applying(b, 300);
    expect(first.payload['paid_to'], 'Customer Deposits',
        reason: 'the draft takes the deposit liability');
    await b.serverSubmit(first);
    // Two devices race for the 200 left: exactly one wins.
    final fromA = await applying(a, 150);
    final fromB = await applying(b, 150);
    await Future.wait([a.sync(), b.sync()]);
    final outcomes = await Future.wait([
      a.postNow(fromA).then((_) => true, onError: (_) => false),
      b.postNow(fromB).then((_) => true, onError: (_) => false),
    ]);
    expect(outcomes.where((ok) => ok), hasLength(1), reason: '$outcomes');
    // The deposit cannot be cancelled while applied.
    await expectLater(
      s.posting.cancelDocument(docType: 'Customer Deposit', documentId: dep.id),
      throwsA(
          isA<CloudHttpException>().having((e) => e.statusCode, 'status', 409)),
    );
    for (final d in [a, b, s]) {
      await d.sync();
    }
    await _sameBooks([a, b, s]);
    expect((await a.balances())['Customer Deposits'], -50,
        reason: '500 received, 450 applied');

    // ---- The books lock. A drafts a journal dated yesterday while offline.
    final offline = await a.h.save(_journal(yesterday, 7));
    // B (accountant) locks through yesterday on the server.
    final lock = await setTeamBooksLock(
      session: b.session,
      database: b.h.db.db,
      lockDate: yesterday,
      expectedCurrent: null,
    );
    expect(lock, yesterday);
    expect(await b.localLock(), yesterday, reason: 'B has it at once');
    expect(await a.localLock(), isNull, reason: 'A has not synced yet');
    // A's stale submit is refused by the server's lock, not A's copy.
    await expectLater(
      a.postNow(offline),
      throwsA(isA<CloudHttpException>()
          .having((e) => e.message, 'message', contains('locked'))),
    );
    // The next sync brings the lock to A and S.
    await a.sync();
    await s.sync();
    expect(await a.localLock(), yesterday);
    expect(await s.localLock(), yesterday);
    // A cannot change it from the Company form while connected.
    final company =
        (await a.h.engine.list('Company', userRoles: systemRoles)).single;
    company.payload['books_lock_date'] = null;
    await expectLater(
        a.h.save(company),
        throwsA(isA<DocumentEngineError>().having(
            (e) => e.humanMessage, 'message', contains('Team server'))));
    // B may lock, not reopen.
    await expectLater(
      setTeamBooksLock(
          session: b.session,
          database: b.h.db.db,
          lockDate: null,
          expectedCurrent: yesterday),
      throwsA(
          isA<CloudHttpException>().having((e) => e.statusCode, 'status', 403)),
    );
    // A (owner) with a stale view is refused; from the current one it reopens.
    await expectLater(
      setTeamBooksLock(
          session: a.session,
          database: a.h.db.db,
          lockDate: null,
          expectedCurrent: null),
      throwsA(
          isA<CloudHttpException>().having((e) => e.statusCode, 'status', 409)),
    );
    // A retried command whose response was lost is a no-op, not an error.
    await setTeamBooksLock(
        session: b.session,
        database: b.h.db.db,
        lockDate: yesterday,
        expectedCurrent: null);
    await setTeamBooksLock(
        session: a.session,
        database: a.h.db.db,
        lockDate: null,
        expectedCurrent: yesterday);
    await a.postNow(offline);
    for (final d in [a, b, s]) {
      await d.sync();
    }
    for (final d in [a, b, s]) {
      expect(await d.localLock(), isNull, reason: '${d.id} sees the reopen');
      expect(await d.h.trialBalanceDifference(), 0, reason: d.id);
    }
    await _sameBooks([a, b, s]);
  }, skip: skip, timeout: const Timeout(Duration(minutes: 3)));
}

Document _journal(String date, num amount, {String? customer}) =>
    Document(id: '', docType: 'Journal Entry', payload: {'posting_date': date})
      ..children['accounts'] = [
        itemLine(
            'Journal Entry',
            {
              'account': 'Debtors',
              'debit': amount,
              'credit': 0,
              if (customer != null) 'party_type': 'Customer',
              if (customer != null) 'party': customer,
            },
            0,
            'accounts'),
        itemLine('Journal Entry',
            {'account': 'Sales', 'debit': 0, 'credit': amount}, 1, 'accounts'),
      ];

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
  final history = MemoryTeamHistoryStore();
  TeamSession? _session;
  TeamSession get session => _session!;
  set session(TeamSession s) => _session = s;
  late final registry = MetadataRegistry(h.db.db);
  late final posting = TeamPostingClient(
    baseUrl: session.baseUrl,
    companyId: session.companyId,
    deviceToken: session.deviceToken,
    history: history,
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
        historyStore: history,
      );

  Future<Map<String, dynamic>> serverSubmit(Document draft) async {
    await sync();
    final result = await postNow(draft);
    await sync();
    return result;
  }

  Future<Map<String, dynamic>> postNow(Document draft) async =>
      posting.submitDocument(
          buildSubmitCommand((await h.engine.fetch(draft.docType, draft.id))!));

  Future<String?> localLock() async => normalizeBooksLock(
      (await h.engine.list('Company', userRoles: systemRoles))
          .single
          .payload['books_lock_date']);

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
