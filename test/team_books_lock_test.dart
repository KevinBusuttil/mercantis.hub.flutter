import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_hub_app/team/team_books_lock.dart';
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
}
