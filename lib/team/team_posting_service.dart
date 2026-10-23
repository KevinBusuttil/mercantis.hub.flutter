import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';
import 'package:sqflite_common/sqlite_api.dart';

import 'team_account_client.dart';
import 'team_session.dart';
import 'team_sync_runner.dart';

/// The doctypes whose OFFICIAL lifecycle the Team backend owns. Everything
/// else — and every draft — stays local.
///
/// POS Invoice is a DELIBERATE carve-out (Phase-0 decision, gap analysis
/// §8-C5): a till must complete a sale with zero network, and a server
/// rejection hours after the customer left is unresolvable — so POS posts
/// through the local engine even in Team mode, with per-till receipt series
/// (`till_series` on the invoice) making cross-device id collisions
/// structurally impossible. The Z-report/session reconciliation is the
/// control point, matching retail practice. If a jurisdiction ever mandates
/// centrally issued receipt numbers, the upgrade path is a durable offline
/// submit queue — nothing here precludes it.
const teamPostedDocTypes = {
  'Sales Invoice',
  'Purchase Invoice',
  'Purchase Receipt',
  'Payment Entry',
  'Stock Entry',
  'Delivery Note',
};

/// The wire body for a submit-document command, built from a hydrated
/// draft: header payload, line items as plain maps, and every other child
/// table folded INTO the payload under its table name — that is where the
/// backend reads them: `taxes` (the VAT rows its totals and tax subledger
/// are validated against), Payment Entry `references` (settlements), POS
/// `tenders`. Pure — exposed for tests.
Map<String, dynamic> buildSubmitCommand(Document doc) {
  final payload = Map<String, dynamic>.from(doc.payload);
  final items = [
    for (final row in doc.children['items'] ?? const <ChildRow>[])
      Map<String, dynamic>.from(row.payload),
  ];
  for (final table in doc.children.entries) {
    if (table.key == 'items') continue;
    payload[table.key] = [
      for (final row in table.value) Map<String, dynamic>.from(row.payload),
    ];
  }
  if (doc.docType == 'Payment Entry') {
    payload.putIfAbsent('references', () => <Map<String, dynamic>>[]);
  }
  return {
    'doctype': doc.docType,
    'document_id': doc.id,
    'payload': payload,
    'items': items,
    // Deterministic: a retry after a dropped response replays instead of
    // double-posting (the backend stores the outcome under this key).
    'idempotency_key': 'submit-${doc.docType}-${doc.id}',
  };
}

/// Command-plane client: the backend's posting-authority endpoints.
/// Device-token auth (like sync); errors surface as [CloudHttpException].
class TeamPostingClient {
  TeamPostingClient({
    required String baseUrl,
    required this.companyId,
    required this.deviceToken,
    http.Client? client,
  })  : baseUrl = baseUrl.replaceAll(RegExp(r'/+$'), ''),
        _client = client ?? http.Client();

  final String baseUrl;
  final String companyId;
  final String deviceToken;
  final http.Client _client;

  Future<Map<String, dynamic>> submitDocument(Map<String, dynamic> command) =>
      _post('submit-document', command);

  Future<Map<String, dynamic>> cancelDocument({
    required String docType,
    required String documentId,
  }) =>
      _post('cancel-document', {
        'doctype': docType,
        'document_id': documentId,
        'idempotency_key': 'cancel-$docType-$documentId',
      });

  /// The newest sync version of the company log (`head` on a pull
  /// response), or null when the server predates it.
  Future<int?> logHead() async {
    final response = await _client.get(
      Uri.parse(
          '$baseUrl/companies/$companyId/sync/pull?after=$_beyond&limit=1'),
      headers: {'Authorization': 'Bearer $deviceToken'},
    );
    if (response.statusCode != 200) return null;
    final decoded = jsonDecode(response.body);
    final head = decoded is Map ? decoded['head'] : null;
    return head is int ? head : null;
  }

  /// A cursor past any real log, so the head probe transfers no mutations.
  static const _beyond = 9007199254740991;

  void close() => _client.close();

  Future<Map<String, dynamic>> _post(
      String command, Map<String, dynamic> body) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/companies/$companyId/commands/$command'),
      headers: {
        'Authorization': 'Bearer $deviceToken',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(body),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      String message = 'HTTP ${response.statusCode}';
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map && decoded['error'] is String) {
          message = decoded['error'] as String;
        }
      } catch (_) {}
      throw CloudHttpException(response.statusCode, message);
    }
    final decoded = jsonDecode(response.body);
    return decoded is Map<String, dynamic> ? decoded : const {};
  }
}

/// Team-mode official postings (the client half of Phase 3): Submit and
/// Cancel on the backend-posted doctypes route to the posting authority
/// instead of the local engine (see [teamPostedDocTypes] for the set and
/// the POS carve-out).
///
/// Submit sequence — order matters:
///  1. **Sync first.** The draft's history must reach the mutation log
///     BEFORE the document becomes officially posted there, because the
///     sync plane rejects (409) client mutations that touch posted
///     documents. Any local pending changes ship now.
///  2. **Command.** The backend validates, allocates the gap-free official
///     number, and posts GL/stock/settlements atomically. No local submit
///     happens — the backend is the single posting authority.
///  3. **Sync again.** The backend wrote the posted results (docstatus,
///     official number, GL/SLE/Bin rows) into the mutation log as the
///     system device; pulling applies them locally — and on every other
///     device on its next sync.
class TeamOfficialPosting implements OfficialPostingOverride {
  const TeamOfficialPosting();

  @override
  bool handles(String docType) => teamPostedDocTypes.contains(docType);

  @override
  Future<void> submit(WidgetRef ref, Document doc) async {
    final session = ref.read(teamSessionProvider);
    if (session == null) {
      throw StateError('Not connected to Atlas Team.');
    }
    if (doc.id.isEmpty) {
      throw StateError('Save the draft before submitting.');
    }
    final engine = await ref.read(documentEngineProvider.future);
    final hydrated = await engine.fetch(doc.docType, doc.id);
    if (hydrated == null) {
      throw StateError('${doc.docType} ${doc.id} not found locally.');
    }
    if (hydrated.docStatus != 0) {
      throw StateError('${doc.id} is not a draft.');
    }

    final client = TeamPostingClient(
      baseUrl: session.baseUrl,
      companyId: session.companyId,
      deviceToken: session.deviceToken,
    );
    try {
      await _exchange(ref, session); // 1. drafts into the log first
      await client.submitDocument(buildSubmitCommand(hydrated)); // 2. post
      await _exchange(ref, session); // 3. posted state comes home
    } finally {
      client.close();
    }
  }

  @override
  Future<void> cancel(WidgetRef ref, Document doc) async {
    final session = ref.read(teamSessionProvider);
    if (session == null) {
      throw StateError('Not connected to Atlas Team.');
    }
    final client = TeamPostingClient(
      baseUrl: session.baseUrl,
      companyId: session.companyId,
      deviceToken: session.deviceToken,
    );
    try {
      await client.cancelDocument(docType: doc.docType, documentId: doc.id);
      await _exchange(ref, session); // reversal rows + docstatus 2 come home
    } finally {
      client.close();
    }
  }

  Future<void> _exchange(WidgetRef ref, TeamSession session) async {
    final db = (await ref.read(mercantisDatabaseProvider.future)).db;
    final registry = await ref.read(metadataRegistryProvider.future);
    final deviceId = await ref.read(deviceIdProvider.future);
    await runTeamSync(
      session: session,
      database: db,
      registry: registry,
      localDeviceId: deviceId,
    );
  }
}

/// One complete Team sync exchange for [session]: the sync plane (pull,
/// push) plus the posting-authority duties every exchange has — confirming
/// this till's offline sales and detecting a server restored behind this
/// device's cursor. Every caller (Sync now, background sync, the posting
/// override, the joining device's first pull) goes through here.
Future<TeamSyncResult> runTeamSync({
  required TeamSession session,
  required Database database,
  required MetadataRegistry registry,
  required String localDeviceId,
  http.Client? client,
  TeamSyncCursorStore? cursorStore,
}) async {
  final adapter = TeamAccountClient.adapterFor(session, client: client);
  final posting = TeamPostingClient(
    baseUrl: session.baseUrl,
    companyId: session.companyId,
    deviceToken: session.deviceToken,
    client: client,
  );
  try {
    return await TeamSyncRunner(
      database: database,
      registry: registry,
      adapter: adapter,
      localDeviceId: localDeviceId,
      companyId: session.companyId,
      cursorStore: cursorStore,
      confirmTillSale: posting.submitDocument,
      logHead: () => posting.logHead(),
    ).run();
  } finally {
    adapter.close();
    posting.close();
  }
}

/// Wire into the core seam: active only while a Team session exists, so
/// Solo installs never route postings anywhere but the local engine.
final teamOfficialPostingOverride =
    officialPostingOverrideProvider.overrideWith((ref) {
  final session = ref.watch(teamSessionProvider);
  return session == null ? null : const TeamOfficialPosting();
});
