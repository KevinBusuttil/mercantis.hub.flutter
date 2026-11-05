import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_hub_app/team/team_account_client.dart';
import 'package:mercantis_hub_app/team/team_posting_service.dart';
import 'package:mercantis_hub_app/team/team_protocol.dart';
import 'package:mercantis_hub_app/team/team_session.dart';

/// C6: the app's half of the Team protocol contract.
void main() {
  test('the constants match the pinned contract file', () {
    final contract =
        jsonDecode(File('test/fixtures/team_protocol.json').readAsStringSync())
            as Map<String, dynamic>;
    expect(teamClientProtocol, contract['protocol'],
        reason: 'the app speaks the protocol of the pinned server');
    expect(teamMinServerProtocol, contract['clientMinServerProtocol']);
    expect(teamProtocolHeader, contract['header']);
  });

  MockClient server(int? protocol,
      {int minClient = 0, List<http.BaseRequest>? seen}) {
    return MockClient((request) async {
      seen?.add(request);
      if (request.url.path == '/protocol') {
        if (protocol == null) return http.Response('not found', 404);
        return http.Response(
            jsonEncode({
              'protocol': protocol,
              'minClientProtocol': minClient,
              'version': '0.1.0',
            }),
            200);
      }
      return http.Response('{}', 200);
    });
  }

  test('every Team client sends the protocol header', () async {
    final seen = <http.BaseRequest>[];
    final client = server(3, seen: seen);
    const session = TeamSession(
        baseUrl: 'https://team.example',
        companyId: 'c1',
        companyName: 'Co',
        userId: 'u1',
        userToken: 'usr',
        deviceId: 'd1',
        deviceToken: 'dev',
        deviceName: 'Till');
    await TeamAccountClient(baseUrl: session.baseUrl, client: client)
        .settings(companyId: 'c1', authToken: 'dev');
    await TeamPostingClient(
            baseUrl: session.baseUrl,
            companyId: 'c1',
            deviceToken: 'dev',
            client: client)
        .logHead()
        .catchError((_) => null);
    await TeamAccountClient.adapterFor(session, client: client)
        .pull(null)
        .catchError((_) => const <MutationRecord>[]);
    expect(seen, hasLength(3));
    for (final request in seen) {
      expect(request.headers[teamProtocolHeader], '$teamClientProtocol',
          reason: '${request.url}');
    }
  });

  test('a compatible server, and a newer one, pass', () async {
    expect(
        (await checkTeamServerProtocol('https://t', client: server(3)))
            .protocol,
        3);
    expect(
        (await checkTeamServerProtocol('https://t', client: server(4)))
            .protocol,
        4);
  });

  test('an older server is refused before anything is exchanged', () async {
    for (final protocol in [null, 2]) {
      final seen = <http.BaseRequest>[];
      await expectLater(
        checkTeamServerProtocol('https://t',
            client: server(protocol, seen: seen)),
        throwsA(isA<CloudHttpException>()
            .having((e) => e.statusCode, 'status', 426)
            .having((e) => e.message, 'message',
                contains('Ask whoever runs the server to update it'))),
      );
      expect(seen.map((r) => r.url.path), ['/protocol'],
          reason: 'only the protocol was asked for');
    }
  });

  test('a server that needs a newer app says to update the app', () async {
    await expectLater(
      checkTeamServerProtocol('https://t',
          client: server(5, minClient: teamClientProtocol + 1)),
      throwsA(isA<CloudHttpException>()
          .having((e) => e.statusCode, 'status', 426)
          .having((e) => e.message, 'message', contains('Update Atlas'))),
    );
  });

  test('an unreachable server is a transport error, not a mismatch', () async {
    final failing =
        MockClient((_) async => throw const SocketException('down'));
    await expectLater(
      checkTeamServerProtocol('https://t', client: failing),
      throwsA(
          isA<CloudHttpException>().having((e) => e.statusCode, 'status', 0)),
    );
  });
}
