@Tags(['team-e2e'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mercantis_hub_app/team/team_account_client.dart';
import 'package:mercantis_hub_app/team/team_protocol.dart';

/// C6 on a real backend: this app and the pinned server agree on the
/// protocol contract, and the server answers every app request with its own
/// level. (The refusal of an outdated app is pinned in the backend's
/// `tests/protocol.rs`, which raises the server's minimum; this server runs
/// with the default.) Skipped unless `ATLAS_TEAM_E2E_URL` is set.
void main() {
  final baseUrl = Platform.environment['ATLAS_TEAM_E2E_URL'];
  final skip = baseUrl == null
      ? 'set ATLAS_TEAM_E2E_URL to a running Atlas Team backend'
      : null;

  test('the app and the pinned server are compatible', () async {
    final server = await checkTeamServerProtocol(baseUrl!);
    expect(server.protocol, teamClientProtocol,
        reason: 'CI pins the server this app was built against');
    expect(server.minClientProtocol, lessThanOrEqualTo(teamClientProtocol));

    final contract =
        jsonDecode(File('test/fixtures/team_protocol.json').readAsStringSync())
            as Map<String, dynamic>;
    expect(server.protocol, contract['protocol']);
  }, skip: skip);

  test('app requests carry the header and get the server level back', () async {
    final seen = <http.BaseResponse>[];
    final recording = _Recording(http.Client(), seen);
    final client = TeamAccountClient(baseUrl: baseUrl!, client: recording);
    final created = await client.createCompany(
        name: 'Protocol Check Ltd',
        ownerEmail: 'protocol@example.com',
        ownerName: 'Pat');
    expect(created.companyId, isNotEmpty);
    expect(seen.single.request!.headers[teamProtocolHeader],
        '$teamClientProtocol');
    expect(seen.single.headers[teamProtocolHeader.toLowerCase()],
        '$teamClientProtocol');
    recording.close();
  }, skip: skip);
}

class _Recording extends http.BaseClient {
  _Recording(this.inner, this.seen);
  final http.Client inner;
  final List<http.BaseResponse> seen;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await inner.send(request);
    seen.add(response);
    return response;
  }

  @override
  void close() => inner.close();
}
