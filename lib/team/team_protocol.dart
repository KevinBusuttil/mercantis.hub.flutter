import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:mercantis_core/mercantis_core.dart';

/// C6: the app's half of the Team client/server protocol contract.
///
/// The backend owns the contract (`contract/team_protocol.json`; the copy in
/// `test/fixtures/team_protocol.json` is checked against it in CI):
///
/// * every request to the Team server carries [teamProtocolHeader] with
///   [teamClientProtocol] ([TeamProtocolClient]), and the server refuses an
///   app below its minimum with 426 before anything is written;
/// * before each sync the app asks the server for its protocol
///   ([checkTeamServerProtocol]) and will not exchange anything with a
///   server below [teamMinServerProtocol], one that does not have the
///   commands this app relies on (for this release, the C5 postings and the
///   books-lock command). Nothing on the device is lost: the sync waits.

/// The protocol this app speaks.
const teamClientProtocol = 3;

/// The oldest Team server this app syncs with.
const teamMinServerProtocol = 3;

/// The header both sides use for their protocol level.
const teamProtocolHeader = 'X-Atlas-Protocol';

/// Adds [teamProtocolHeader] to every request. Closing it closes [inner],
/// as the Team clients already close the client they are given.
class TeamProtocolClient extends http.BaseClient {
  TeamProtocolClient(this.inner);

  final http.Client inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers[teamProtocolHeader] = '$teamClientProtocol';
    return inner.send(request);
  }

  @override
  void close() => inner.close();
}

/// Wraps [client] (or a new client) in [TeamProtocolClient], once.
http.Client teamHttpClient([http.Client? client]) {
  final inner = client ?? http.Client();
  return inner is TeamProtocolClient ? inner : TeamProtocolClient(inner);
}

/// The server's side of the contract, from `GET /protocol`.
class TeamServerProtocol {
  const TeamServerProtocol(
      {required this.protocol, required this.minClientProtocol, this.version});

  /// Null when the server predates the contract (no `/protocol`).
  final int? protocol;
  final int minClientProtocol;
  final String? version;
}

/// Why this app may not sync with [server], or null when it may. Pure.
String? teamProtocolRefusal(TeamServerProtocol server) {
  final protocol = server.protocol;
  if (protocol == null || protocol < teamMinServerProtocol) {
    return 'This Team server is older than this version of Atlas needs '
        '(it speaks protocol ${protocol ?? 'below 3'}, Atlas needs '
        '$teamMinServerProtocol or later). Ask whoever runs the server to '
        'update it, then sync again. Nothing on this device was changed or '
        'lost.';
  }
  if (teamClientProtocol < server.minClientProtocol) {
    return 'This version of Atlas is too old for this Team server (it speaks '
        'protocol $teamClientProtocol, the server needs '
        '${server.minClientProtocol} or later). Update Atlas on this device, '
        'then sync again. Nothing was changed.';
  }
  return null;
}

/// Reads the server's protocol. A server without `/protocol` (404) predates
/// the contract. Other failures surface as [CloudHttpException] like any
/// other Team call (status 0 for transport errors).
Future<TeamServerProtocol> fetchTeamServerProtocol(String baseUrl,
    {http.Client? client}) async {
  final httpClient = teamHttpClient(client);
  final base = baseUrl.replaceAll(RegExp(r'/+$'), '');
  try {
    final http.Response response;
    try {
      response = await httpClient.get(Uri.parse('$base/protocol'));
    } catch (e) {
      throw CloudHttpException(0, '$e');
    }
    if (response.statusCode == 404) {
      return const TeamServerProtocol(protocol: null, minClientProtocol: 0);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw CloudHttpException(response.statusCode, response.body);
    }
    final body = jsonDecode(response.body);
    if (body is! Map) {
      throw const CloudHttpException(0, 'unexpected /protocol response');
    }
    return TeamServerProtocol(
      protocol: (body['protocol'] as num?)?.toInt(),
      minClientProtocol: (body['minClientProtocol'] as num?)?.toInt() ?? 0,
      version: body['version']?.toString(),
    );
  } finally {
    if (client == null) httpClient.close();
  }
}

/// Throws [CloudHttpException] 426 with a message a person can act on when
/// this app and the server at [baseUrl] are not compatible.
Future<TeamServerProtocol> checkTeamServerProtocol(String baseUrl,
    {http.Client? client}) async {
  final server = await fetchTeamServerProtocol(baseUrl, client: client);
  final refusal = teamProtocolRefusal(server);
  if (refusal != null) throw CloudHttpException(426, refusal);
  return server;
}
