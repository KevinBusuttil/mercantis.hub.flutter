import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mercantis_hub_app/team/team_books_lock.dart';
import 'package:mercantis_hub_app/team/team_session.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/books_harness.dart';

/// C5.2, device side: the server's books lock lands on this device's
/// Company row as the server's value (no sync mutation is queued for it,
/// so a device never pushes the lock back), and blank and null agree. The
/// command, permissions and stale-view refusals run against a real backend
/// in test/team_e2e/team_authority_c5_e2e_test.dart.
void main() {
  setUpAll(sqfliteFfiInit);
  late Directory dir;
  late BooksHarness h;
  setUp(() async {
    dir = Directory.systemTemp.createTempSync('books_lock_');
    h = await BooksHarness.open(p.join(dir.path, 'b.db'));
  });
  tearDown(() async {
    await h.close();
    dir.deleteSync(recursive: true);
  });

  Future<int> queued() async => (await h.db.db
          .query('sync_queue', where: 'doctype = ?', whereArgs: ['Company']))
      .length;

  test('the server lock is copied onto the company without queueing it',
      () async {
    final before = await queued();
    expect(await applyServerBooksLock(h.db.db, '2026-06-30'), isTrue);
    final co = (await h.engine.list('Company', userRoles: systemRoles)).single;
    expect(co.payload['books_lock_date'], '2026-06-30');
    expect(await queued(), before, reason: 'the server value is not re-sent');
    expect(await applyServerBooksLock(h.db.db, '2026-06-30'), isFalse,
        reason: 'unchanged: no write');
    expect(await applyServerBooksLock(h.db.db, null), isTrue);
    expect(
        normalizeBooksLock(
            (await h.engine.list('Company', userRoles: systemRoles))
                .single
                .payload['books_lock_date']),
        isNull);
  });

  test('blank, null and timestamps normalise', () {
    expect(normalizeBooksLock(null), isNull);
    expect(normalizeBooksLock(''), isNull);
    expect(normalizeBooksLock('  '), isNull);
    expect(normalizeBooksLock('2026-06-30T00:00:00.000'), '2026-06-30');
  });

  test('clearing the lock sends no date and reopens this device too', () async {
    await applyServerBooksLock(h.db.db, '2026-06-30');
    Map<String, dynamic>? sent;
    final client = MockClient((req) async {
      sent = jsonDecode(req.body) as Map<String, dynamic>;
      return http.Response(
          jsonEncode({'books_lock_date': null, 'previous': '2026-06-30'}), 200,
          headers: {'content-type': 'application/json'});
    });
    const session = TeamSession(
        baseUrl: 'https://team.example',
        companyId: 'c1',
        companyName: 'Co',
        userId: 'u1',
        userToken: 'usr',
        deviceId: 'd1',
        deviceToken: 'dev',
        deviceName: 'Office');
    final lock = await setTeamBooksLock(
      session: session,
      database: h.db.db,
      lockDate: null,
      expectedCurrent: '2026-06-30',
      client: client,
    );
    expect(lock, isNull);
    expect(sent, containsPair('lock_date', null));
    expect(sent, containsPair('expected_current', '2026-06-30'));
    expect(
        normalizeBooksLock(
            (await h.engine.list('Company', userRoles: systemRoles))
                .single
                .payload['books_lock_date']),
        isNull);
  });

  test('the date picker range always contains the current lock', () {
    final now = DateTime(2026, 11, 5, 15);
    final none = booksLockPickerRange(now, null);
    expect(none.first, DateTime(2016));
    expect(none.last, DateTime(2026, 11, 5));
    expect(none.initial, DateTime(2026, 10, 31), reason: 'last month-end');

    // A lock older than ten years no longer crashes the picker.
    final old = booksLockPickerRange(now, '2012-12-31');
    expect(old.first, DateTime(2012, 12, 31));
    expect(old.initial, DateTime(2012, 12, 31));
    // Nor one a server set past today.
    final ahead = booksLockPickerRange(now, '2026-12-31');
    expect(ahead.last, DateTime(2026, 12, 31));
    for (final r in [none, old, ahead]) {
      expect(r.initial.isBefore(r.first), isFalse);
      expect(r.initial.isAfter(r.last), isFalse);
    }
  });
}
