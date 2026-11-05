import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:mercantis_core/mercantis_core.dart';
import 'package:sqflite_common/sqlite_api.dart';

import '../ledger/ledger_values.dart';
import 'team_account_client.dart';
import 'team_session.dart';

/// C5.2: in Atlas Team the books lock (period close) belongs to the server.
///
/// * It moves only through the server's `set-books-lock` command
///   ([TeamAccountClient.setBooksLock]): Owner, Admin or Accountant to lock,
///   Owner or Admin to reopen, refused when this device's view is stale.
/// * Every Team sync copies the server's lock onto this device's Company
///   row ([refreshTeamBooksLock]), so the local guard and the screens show
///   what the server enforces. The copy is written straight to the local
///   store: it is the server's value, not a local edit to sync back.
/// * A local edit of the lock on the Company form is refused while
///   connected (`TeamPostingAuthorityGuard`), and the server puts a stale
///   lock in a pushed Company row back to its own value.
/// * A submit is always checked against the server's lock at the moment it
///   commits, so a device that has not synced since the lock moved cannot
///   post into the closed period.

/// The lock as a comparable value: blank and null both mean "no lock".
String? normalizeBooksLock(Object? raw) {
  return asNonEmpty(raw)?.split('T').first;
}

/// The date picker's range for moving the books lock: from ten years back
/// (or the current lock, if older) to today (or the current lock, if a
/// server set it later), starting at the current lock or last month-end.
/// A lock outside the default range would otherwise crash the picker.
({DateTime first, DateTime last, DateTime initial}) booksLockPickerRange(
    DateTime now, String? current) {
  final today = DateTime(now.year, now.month, now.day);
  final lock = DateTime.tryParse(current ?? '');
  var first = DateTime(now.year - 10);
  var last = today;
  if (lock != null && lock.isBefore(first)) first = lock;
  if (lock != null && lock.isAfter(last)) last = lock;
  final initial = lock ?? DateTime(now.year, now.month, 0);
  return (first: first, last: last, initial: initial);
}

/// Writes [lock] onto every Company row of this book, without queueing a
/// sync mutation (it is the server's value). Returns whether a row changed.
Future<bool> applyServerBooksLock(DatabaseExecutor db, String? lock) async {
  final rows = await db.query('documents',
      columns: ['id', 'payload'], where: 'doctype = ?', whereArgs: ['Company']);
  var changed = false;
  for (final row in rows) {
    final payload =
        Map<String, dynamic>.from(jsonDecode('${row['payload']}') as Map);
    if (normalizeBooksLock(payload['books_lock_date']) == lock) continue;
    payload['books_lock_date'] = lock;
    await db.update('documents', {'payload': jsonEncode(payload)},
        where: 'id = ? AND doctype = ?', whereArgs: [row['id'], 'Company']);
    changed = true;
  }
  return changed;
}

/// The server's current lock for [session]'s company.
Future<String?> fetchTeamBooksLock(TeamSession session,
    {http.Client? client}) async {
  final httpClient = client ?? http.Client();
  try {
    final settings = await TeamAccountClient(
            baseUrl: session.baseUrl, client: httpClient)
        .settings(companyId: session.companyId, authToken: session.deviceToken);
    return normalizeBooksLock(settings['books_lock_date']);
  } finally {
    if (client == null) httpClient.close();
  }
}

/// Copies the server's lock onto this device (see the library comment).
/// Returns the server's lock.
Future<String?> refreshTeamBooksLock({
  required TeamSession session,
  required DatabaseExecutor database,
  http.Client? client,
}) async {
  final lock = await fetchTeamBooksLock(session, client: client);
  await applyServerBooksLock(database, lock);
  return lock;
}

/// Why a local save of [doc] may not go ahead in a Team company, or null.
/// Only the books lock is guarded: the rest of the Company row is ordinary
/// synced data.
Future<String?> teamCompanyLockEditRefusal(
    DocumentEngine engine, Document doc) async {
  if (doc.docType != 'Company') return null;
  final stored = await engine.fetch('Company', doc.id);
  final before = normalizeBooksLock(stored?.payload['books_lock_date']);
  final after = normalizeBooksLock(doc.payload['books_lock_date']);
  if (before == after) return null;
  return 'In Atlas Team the books lock is kept by the Team server, so every '
      'device closes the same period. Change it from Settings › Lock books '
      'while connected.';
}

/// Moves the Team books lock from this device: the server command, then the
/// local copy. Throws [CloudHttpException] (409 when another device moved
/// it first, 403 when this user may not reopen a period).
Future<String?> setTeamBooksLock({
  required TeamSession session,
  required DatabaseExecutor database,
  required String? lockDate,
  required String? expectedCurrent,
  String? reason,
  http.Client? client,
}) async {
  final httpClient = client ?? http.Client();
  final Map<String, dynamic> result;
  try {
    result =
        await TeamAccountClient(baseUrl: session.baseUrl, client: httpClient)
            .setBooksLock(
      companyId: session.companyId,
      authToken: session.deviceToken,
      lockDate: lockDate,
      expectedCurrent: expectedCurrent,
      reason: reason,
    );
  } finally {
    if (client == null) httpClient.close();
  }
  final lock = normalizeBooksLock(result['books_lock_date']);
  await applyServerBooksLock(database, lock);
  return lock;
}
