import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_hub_app/team/team_account_client.dart';
import 'package:mercantis_hub_app/team/team_session.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Team milestone 2 — the account plane: create/join a Team company,
/// register this device, invite teammates; and the session that persists it
/// all in preferences (never in the synced store).
void main() {
  const base = 'https://team.neuradix.app';

  group('TeamAccountClient', () {
    test('createAndConnect: bootstrap then device registration in one step',
        () async {
      final requests = <http.Request>[];
      final client = MockClient((req) async {
        requests.add(req);
        if (req.url.path == '/companies') {
          expect(jsonDecode(req.body), {
            'name': 'Busuttil Technologies Limited',
            'owner_email': 'kevin@busuttil-technologies.com',
            'owner_name': 'Kevin',
          });
          return http.Response(
              jsonEncode({
                'company': {'id': 'comp-1', 'name': 'Busuttil Technologies Limited'},
                'token': 'user-token-1',
                'userId': 'user-1',
              }),
              201);
        }
        if (req.url.path == '/companies/comp-1/devices') {
          // Device registration authenticates with the freshly issued
          // USER token — the device token doesn't exist yet.
          expect(req.headers['Authorization'], 'Bearer user-token-1');
          expect(jsonDecode(req.body), {'name': 'Front desk laptop'});
          return http.Response(
              jsonEncode({'deviceId': 'dev-1', 'deviceToken': 'dev-token-1'}),
              201);
        }
        fail('unexpected request: ${req.url}');
      });

      final session =
          await TeamAccountClient(baseUrl: '$base/', client: client)
              .createAndConnect(
        companyName: 'Busuttil Technologies Limited',
        ownerEmail: 'kevin@busuttil-technologies.com',
        ownerName: 'Kevin',
        deviceName: 'Front desk laptop',
      );

      expect(requests, hasLength(2));
      expect(session.baseUrl, base); // trailing slash normalised away
      expect(session.companyId, 'comp-1');
      expect(session.companyName, 'Busuttil Technologies Limited');
      expect(session.userToken, 'user-token-1');
      expect(session.deviceToken, 'dev-token-1');
      expect(session.deviceName, 'Front desk laptop');
    });

    test('joinAndConnect: invitation accept then device registration',
        () async {
      final client = MockClient((req) async {
        if (req.url.path == '/invitations/inv-tok-9/accept') {
          expect(req.headers.containsKey('Authorization'), isFalse);
          expect(jsonDecode(req.body), {'display_name': 'Maria'});
          return http.Response(
              jsonEncode({
                'userId': 'user-2',
                'companyId': 'comp-1',
                'role': 'accountant',
                'token': 'user-token-2',
              }),
              201);
        }
        if (req.url.path == '/companies/comp-1/devices') {
          expect(req.headers['Authorization'], 'Bearer user-token-2');
          return http.Response(
              jsonEncode({'deviceId': 'dev-2', 'deviceToken': 'dev-token-2'}),
              201);
        }
        fail('unexpected request: ${req.url}');
      });

      final session = await TeamAccountClient(baseUrl: base, client: client)
          .joinAndConnect(
        invitationToken: 'inv-tok-9',
        displayName: 'Maria',
        deviceName: 'Maria\'s tablet',
      );
      expect(session.companyId, 'comp-1');
      expect(session.userId, 'user-2');
      expect(session.deviceToken, 'dev-token-2');
    });

    test('createInvitation posts email + role under the user token',
        () async {
      http.Request? seen;
      final client = MockClient((req) async {
        seen = req;
        return http.Response(
            jsonEncode(
                {'token': 'inv-tok-1', 'expiresAt': '2026-07-15T00:00:00Z'}),
            201);
      });
      final invitation = await TeamAccountClient(baseUrl: base, client: client)
          .createInvitation(
        companyId: 'comp-1',
        authToken: 'user-token-1',
        email: 'maria@example.com',
        role: 'accountant',
      );
      expect(seen!.url.path, '/companies/comp-1/invitations');
      expect(seen!.headers['Authorization'], 'Bearer user-token-1');
      expect(jsonDecode(seen!.body),
          {'email': 'maria@example.com', 'role': 'accountant'});
      expect(invitation.token, 'inv-tok-1');
    });

    test('createPortalLink posts kind + party under the user token',
        () async {
      http.Request? seen;
      final client = MockClient((req) async {
        seen = req;
        return http.Response(
            jsonEncode({
              'token': 'portal-tok-1',
              'url_path': '/portal/portal-tok-1',
              'expiresAt': '2026-10-06T00:00:00Z',
            }),
            201);
      });
      final link = await TeamAccountClient(baseUrl: base, client: client)
          .createPortalLink(
        companyId: 'comp-1',
        authToken: 'user-token-1',
        kind: 'customer',
        party: 'CUST-1',
        label: 'Portal for Jane',
      );
      expect(seen!.url.path, '/companies/comp-1/portal-links');
      expect(seen!.headers['Authorization'], 'Bearer user-token-1');
      expect(jsonDecode(seen!.body), {
        'kind': 'customer',
        'party': 'CUST-1',
        'label': 'Portal for Jane',
      });
      expect(link.urlPath, '/portal/portal-tok-1');
      expect(link.expiresAt, startsWith('2026-10-06'));
    });

    test('createPayLink posts the invoice id under the user token', () async {
      http.Request? seen;
      final client = MockClient((req) async {
        seen = req;
        return http.Response(
            jsonEncode({
              'id': 'pl-1',
              'token': 'pay-tok-1',
              'url_path': '/pay/pay-tok-1',
              'expiresAt': '2026-09-06T00:00:00Z',
            }),
            201);
      });
      final link = await TeamAccountClient(baseUrl: base, client: client)
          .createPayLink(
        companyId: 'comp-1',
        authToken: 'user-token-1',
        invoiceId: 'SINV-7',
      );
      expect(seen!.url.path, '/companies/comp-1/pay-links');
      expect(seen!.headers['Authorization'], 'Bearer user-token-1');
      expect(jsonDecode(seen!.body), {'invoice_id': 'SINV-7'});
      expect(link.urlPath, '/pay/pay-tok-1');
    });

    test('server errors surface as CloudHttpException with the reason',
        () async {
      final client = MockClient((_) async => http.Response(
          jsonEncode({'error': 'invitation already accepted'}), 409));
      await expectLater(
        TeamAccountClient(baseUrl: base, client: client).acceptInvitation(
            invitationToken: 'used', displayName: 'X'),
        throwsA(isA<CloudHttpException>()
            .having((e) => e.statusCode, 'statusCode', 409)
            .having((e) => e.message, 'message',
                contains('already accepted'))),
      );
    });

    test('adapterFor hands the session to the sync plane', () {
      const session = TeamSession(
        baseUrl: base,
        companyId: 'comp-1',
        companyName: 'Acme',
        userId: 'user-1',
        userToken: 'user-token-1',
        deviceId: 'dev-1',
        deviceToken: 'dev-token-1',
        deviceName: 'Laptop',
      );
      final adapter = TeamAccountClient.adapterFor(session);
      expect(adapter.companyId, 'comp-1');
      expect(adapter.deviceToken, 'dev-token-1'); // sync uses the DEVICE token
    });
  });

  group('TeamSessionStore', () {
    test('save → load round-trips; clear signs out', () async {
      SharedPreferences.setMockInitialValues({});
      final store = TeamSessionStore();
      expect(await store.load(), isNull);

      const session = TeamSession(
        baseUrl: base,
        companyId: 'comp-1',
        companyName: 'Acme',
        userId: 'user-1',
        userToken: 'user-token-1',
        deviceId: 'dev-1',
        deviceToken: 'dev-token-1',
        deviceName: 'Laptop',
      );
      await store.save(session);

      final loaded = await store.load();
      expect(loaded!.companyId, 'comp-1');
      expect(loaded.deviceToken, 'dev-token-1');
      expect(loaded.baseUrl, base);

      await store.clear();
      expect(await store.load(), isNull);
    });

    test('a corrupt entry reads as signed out, not a crash', () async {
      SharedPreferences.setMockInitialValues(
          {'atlas_team_session': '{not json'});
      expect(await TeamSessionStore().load(), isNull);
    });
  });
}
