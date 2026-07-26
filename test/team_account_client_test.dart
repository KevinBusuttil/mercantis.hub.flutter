import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_hub_app/team/team_account_client.dart';
import 'package:mercantis_hub_app/team/team_session.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Team milestone 2 — the account plane: create/join a Team company,
/// register this device, invite teammates; and the session that persists it
/// all in the platform keychain (never in the synced store).
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

    test('rotateUserToken posts under the presented token and returns the '
        'replacement', () async {
      http.Request? seen;
      final client = MockClient((req) async {
        seen = req;
        return http.Response(
            jsonEncode(
                {'token': 'fresh-tok', 'expiresAt': '2026-08-11T00:00:00Z'}),
            200);
      });
      final rotated = await TeamAccountClient(baseUrl: base, client: client)
          .rotateUserToken(companyId: 'comp-1', authToken: 'old-tok');
      expect(seen!.url.path, '/companies/comp-1/tokens/rotate');
      expect(seen!.headers['Authorization'], 'Bearer old-tok');
      expect(rotated, 'fresh-tok');
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

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
    });

    test('save → load round-trips through the keychain; clear signs out',
        () async {
      final store = TeamSessionStore();
      expect(await store.load(), isNull);

      await store.save(session);

      final loaded = await store.load();
      expect(loaded!.companyId, 'comp-1');
      expect(loaded.deviceToken, 'dev-token-1');
      expect(loaded.baseUrl, base);
      // Nothing lands in plaintext preferences anymore.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('atlas_team_session'), isNull);

      await store.clear();
      expect(await store.load(), isNull);
    });

    test('a pre-keychain session migrates out of SharedPreferences once',
        () async {
      // A session persisted by an earlier build: plaintext in preferences.
      SharedPreferences.setMockInitialValues(
          {'atlas_team_session': jsonEncode(session.toJson())});

      final loaded = await TeamSessionStore().load();
      expect(loaded!.deviceToken, 'dev-token-1');

      // The plaintext copy is gone; the keychain now serves the session.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('atlas_team_session'), isNull);
      expect(
          await const FlutterSecureStorage()
              .read(key: 'atlas_team_session'),
          isNotNull);
      expect((await TeamSessionStore().load())!.companyId, 'comp-1');
    });

    test('a corrupt entry reads as signed out, not a crash', () async {
      FlutterSecureStorage.setMockInitialValues(
          {'atlas_team_session': '{not json'});
      expect(await TeamSessionStore().load(), isNull);
    });

    test('a corrupt LEGACY entry is discarded, not migrated', () async {
      SharedPreferences.setMockInitialValues(
          {'atlas_team_session': '{not json'});
      expect(await TeamSessionStore().load(), isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('atlas_team_session'), isNull);
    });
  });

  group('credential lifecycle endpoints (Phase 0.5)', () {
    test('listDevices parses the device list under the user token',
        () async {
      http.Request? seen;
      final client = MockClient((req) async {
        seen = req;
        return http.Response(
            jsonEncode({
              'devices': [
                {
                  'id': 'dev-1',
                  'userId': 'user-1',
                  'name': 'Laptop',
                  'createdAt': '2026-07-01T00:00:00Z',
                  'revokedAt': null,
                  'lastSeenAt': '2026-07-10T08:00:00Z',
                },
                {
                  'id': 'dev-2',
                  'userId': 'user-2',
                  'name': 'Old phone',
                  'createdAt': '2026-06-01T00:00:00Z',
                  'revokedAt': '2026-07-05T00:00:00Z',
                  'lastSeenAt': null,
                },
              ],
            }),
            200);
      });
      final devices = await TeamAccountClient(baseUrl: base, client: client)
          .listDevices(companyId: 'comp-1', authToken: 'user-token-1');
      expect(seen!.method, 'GET');
      expect(seen!.url.path, '/companies/comp-1/devices');
      expect(seen!.headers['Authorization'], 'Bearer user-token-1');
      expect(devices, hasLength(2));
      expect(devices.first.name, 'Laptop');
      expect(devices.first.revoked, isFalse);
      expect(devices.first.lastSeenAt, startsWith('2026-07-10'));
      expect(devices.last.revoked, isTrue);
    });

    test('revokeDevice posts to the revoke route', () async {
      http.Request? seen;
      final client = MockClient((req) async {
        seen = req;
        return http.Response(
            jsonEncode({'id': 'dev-2', 'revokedAt': '2026-07-10T09:00:00Z'}),
            200);
      });
      await TeamAccountClient(baseUrl: base, client: client).revokeDevice(
          companyId: 'comp-1', deviceId: 'dev-2', authToken: 'user-token-1');
      expect(seen!.method, 'POST');
      expect(seen!.url.path, '/companies/comp-1/devices/dev-2/revoke');
      expect(seen!.headers['Authorization'], 'Bearer user-token-1');
    });

    test('listMembers parses members with roles', () async {
      final client = MockClient((req) async {
        expect(req.url.path, '/companies/comp-1/members');
        return http.Response(
            jsonEncode({
              'members': [
                {
                  'userId': 'user-1',
                  'email': 'kevin@example.com',
                  'displayName': 'Kevin',
                  'role': 'owner',
                  'createdAt': '2026-06-01T00:00:00Z',
                },
              ],
            }),
            200);
      });
      final members = await TeamAccountClient(baseUrl: base, client: client)
          .listMembers(companyId: 'comp-1', authToken: 'user-token-1');
      expect(members.single.role, 'owner');
      expect(members.single.displayName, 'Kevin');
    });

    test('removeMember DELETEs; changeMemberRole posts the new role',
        () async {
      final calls = <http.Request>[];
      final client = MockClient((req) async {
        calls.add(req);
        return http.Response('{}', 200);
      });
      final api = TeamAccountClient(baseUrl: base, client: client);
      await api.removeMember(
          companyId: 'comp-1', userId: 'user-2', authToken: 't');
      await api.changeMemberRole(
          companyId: 'comp-1', userId: 'user-3', role: 'admin',
          authToken: 't');
      expect(calls[0].method, 'DELETE');
      expect(calls[0].url.path, '/companies/comp-1/members/user-2');
      expect(calls[1].method, 'POST');
      expect(calls[1].url.path, '/companies/comp-1/members/user-3/role');
      expect(jsonDecode(calls[1].body), {'role': 'admin'});
    });

    test('lifecycle errors surface as CloudHttpException (last-owner 409)',
        () async {
      final client = MockClient((_) async => http.Response(
          jsonEncode({'error': 'cannot remove the last owner'}), 409));
      await expectLater(
        TeamAccountClient(baseUrl: base, client: client).removeMember(
            companyId: 'comp-1', userId: 'user-1', authToken: 't'),
        throwsA(isA<CloudHttpException>()
            .having((e) => e.statusCode, 'statusCode', 409)
            .having((e) => e.message, 'message', contains('last owner'))),
      );
    });
  });
}
