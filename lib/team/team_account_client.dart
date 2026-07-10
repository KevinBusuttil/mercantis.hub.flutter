import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:mercantis_core/mercantis_core.dart';

import 'team_session.dart';

/// A device registered to the Team company, as listed by the backend
/// (Phase 0.5 credential lifecycle). `revokedAt` non-null means its token
/// no longer authenticates anywhere.
class TeamDevice {
  const TeamDevice({
    required this.id,
    required this.userId,
    required this.name,
    required this.createdAt,
    this.revokedAt,
    this.lastSeenAt,
  });

  final String id;
  final String userId;
  final String name;
  final String createdAt;
  final String? revokedAt;
  final String? lastSeenAt;

  bool get revoked => revokedAt != null;

  factory TeamDevice.fromJson(Map<String, dynamic> json) => TeamDevice(
        id: '${json['id']}',
        userId: '${json['userId']}',
        name: '${json['name']}',
        createdAt: '${json['createdAt']}',
        revokedAt: json['revokedAt'] == null ? null : '${json['revokedAt']}',
        lastSeenAt:
            json['lastSeenAt'] == null ? null : '${json['lastSeenAt']}',
      );
}

/// A member of the Team company with their role.
class TeamMember {
  const TeamMember({
    required this.userId,
    required this.email,
    required this.displayName,
    required this.role,
    required this.createdAt,
  });

  final String userId;
  final String email;
  final String displayName;
  final String role;
  final String createdAt;

  factory TeamMember.fromJson(Map<String, dynamic> json) => TeamMember(
        userId: '${json['userId']}',
        email: '${json['email']}',
        displayName: '${json['displayName']}',
        role: '${json['role']}',
        createdAt: '${json['createdAt']}',
      );
}

/// Client for the Atlas Team backend's **account plane**: company bootstrap,
/// invitations, and device registration. (The sync plane is
/// [HttpCloudAdapter] in core; commands come later with backend-authoritative
/// posting.) Non-2xx responses raise the same [CloudHttpException] the sync
/// adapter uses, so callers have one error type to branch on.
class TeamAccountClient {
  TeamAccountClient({
    required String baseUrl,
    http.Client? client,
  })  : baseUrl = baseUrl.replaceAll(RegExp(r'/+$'), ''),
        _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;

  /// Bootstrap a new company; the caller becomes its owner. The returned
  /// user token is shown exactly once by the server — persist it.
  Future<({String companyId, String companyName, String userId, String userToken})>
      createCompany({
    required String name,
    required String ownerEmail,
    required String ownerName,
  }) async {
    final body = await _post('/companies', {
      'name': name,
      'owner_email': ownerEmail,
      'owner_name': ownerName,
    });
    final company = body['company'] as Map? ?? const {};
    return (
      companyId: '${company['id']}',
      companyName: '${company['name']}',
      userId: '${body['userId']}',
      userToken: '${body['token']}',
    );
  }

  /// Join an existing company with an invitation token (7-day expiry,
  /// single use). Returns the new member's user token.
  Future<({String companyId, String role, String userId, String userToken})>
      acceptInvitation({
    required String invitationToken,
    required String displayName,
  }) async {
    final body = await _post('/invitations/$invitationToken/accept', {
      'display_name': displayName,
    });
    return (
      companyId: '${body['companyId']}',
      role: '${body['role']}',
      userId: '${body['userId']}',
      userToken: '${body['token']}',
    );
  }

  /// Register this device for the authenticated member; the returned device
  /// token is what the sync plane authenticates with.
  Future<({String deviceId, String deviceToken})> registerDevice({
    required String companyId,
    required String userToken,
    required String deviceName,
  }) async {
    final body = await _post(
      '/companies/$companyId/devices',
      {'name': deviceName},
      authToken: userToken,
    );
    return (
      deviceId: '${body['deviceId']}',
      deviceToken: '${body['deviceToken']}',
    );
  }

  /// Owner/admin invites a teammate by email. Returns the invitation token
  /// to hand to them (and when it expires).
  Future<({String token, String expiresAt})> createInvitation({
    required String companyId,
    required String authToken,
    required String email,
    required String role,
  }) async {
    final body = await _post(
      '/companies/$companyId/invitations',
      {'email': email, 'role': role},
      authToken: authToken,
    );
    return (token: '${body['token']}', expiresAt: '${body['expiresAt']}');
  }

  /// Owner/admin mints a token-scoped portal link (customer: that party's
  /// quotes/invoices + quote accept/reject; accountant: company-wide
  /// read-only). The token is shown once — hand out the full URL.
  Future<({String token, String urlPath, String expiresAt})>
      createPortalLink({
    required String companyId,
    required String authToken,
    required String kind,
    String? party,
    String? label,
    int? expiresDays,
  }) async {
    final body = await _post(
      '/companies/$companyId/portal-links',
      {
        'kind': kind,
        if (party != null) 'party': party,
        if (label != null) 'label': label,
        if (expiresDays != null) 'expires_days': expiresDays,
      },
      authToken: authToken,
    );
    return (
      token: '${body['token']}',
      urlPath: '${body['url_path']}',
      expiresAt: '${body['expiresAt']}',
    );
  }

  /// Mints a payment link for a SUBMITTED Sales Invoice: a public, expiring
  /// pay page showing the live outstanding amount (card handoff when the
  /// company has a Stripe Payment Link configured; manual instructions
  /// otherwise).
  Future<({String token, String urlPath, String expiresAt})> createPayLink({
    required String companyId,
    required String authToken,
    required String invoiceId,
    int? expiresDays,
  }) async {
    final body = await _post(
      '/companies/$companyId/pay-links',
      {
        'invoice_id': invoiceId,
        if (expiresDays != null) 'expires_days': expiresDays,
      },
      authToken: authToken,
    );
    return (
      token: '${body['token']}',
      urlPath: '${body['url_path']}',
      expiresAt: '${body['expiresAt']}',
    );
  }

  // Credential lifecycle (Phase 0.5) — visibility and the kill switch for
  // every device token in the company.

  /// Devices visible to the caller: their own, or the whole company for
  /// owner/admin.
  Future<List<TeamDevice>> listDevices({
    required String companyId,
    required String authToken,
  }) async {
    final body =
        await _get('/companies/$companyId/devices', authToken: authToken);
    return [
      for (final d in body['devices'] as List? ?? const [])
        TeamDevice.fromJson((d as Map).cast<String, dynamic>()),
    ];
  }

  /// Revoke a device's token (idempotent). Own devices always; anyone's
  /// for owner/admin. The device stops syncing at its next request.
  Future<void> revokeDevice({
    required String companyId,
    required String deviceId,
    required String authToken,
  }) async {
    await _post('/companies/$companyId/devices/$deviceId/revoke', const {},
        authToken: authToken);
  }

  /// Everyone in the company and their role.
  Future<List<TeamMember>> listMembers({
    required String companyId,
    required String authToken,
  }) async {
    final body =
        await _get('/companies/$companyId/members', authToken: authToken);
    return [
      for (final m in body['members'] as List? ?? const [])
        TeamMember.fromJson((m as Map).cast<String, dynamic>()),
    ];
  }

  /// Remove a member (owner/admin, server enforces the role matrix). The
  /// server also revokes all their devices in this company.
  Future<void> removeMember({
    required String companyId,
    required String userId,
    required String authToken,
  }) async {
    await _delete('/companies/$companyId/members/$userId',
        authToken: authToken);
  }

  /// Change a member's role (owner only; the last owner cannot be demoted).
  Future<void> changeMemberRole({
    required String companyId,
    required String userId,
    required String role,
    required String authToken,
  }) async {
    await _post('/companies/$companyId/members/$userId/role', {'role': role},
        authToken: authToken);
  }

  // Composed flows — each ends with a device registration so the result is
  // a complete, sync-ready TeamSession.

  /// Create a company and register this device in one step.
  Future<TeamSession> createAndConnect({
    required String companyName,
    required String ownerEmail,
    required String ownerName,
    required String deviceName,
  }) async {
    final created = await createCompany(
        name: companyName, ownerEmail: ownerEmail, ownerName: ownerName);
    final device = await registerDevice(
      companyId: created.companyId,
      userToken: created.userToken,
      deviceName: deviceName,
    );
    return TeamSession(
      baseUrl: baseUrl,
      companyId: created.companyId,
      companyName: created.companyName,
      userId: created.userId,
      userToken: created.userToken,
      deviceId: device.deviceId,
      deviceToken: device.deviceToken,
      deviceName: deviceName,
    );
  }

  /// Accept an invitation and register this device in one step.
  Future<TeamSession> joinAndConnect({
    required String invitationToken,
    required String displayName,
    required String deviceName,
  }) async {
    final joined = await acceptInvitation(
        invitationToken: invitationToken, displayName: displayName);
    final device = await registerDevice(
      companyId: joined.companyId,
      userToken: joined.userToken,
      deviceName: deviceName,
    );
    return TeamSession(
      baseUrl: baseUrl,
      companyId: joined.companyId,
      companyName: '', // accept response carries no name; cosmetic only
      userId: joined.userId,
      userToken: joined.userToken,
      deviceId: device.deviceId,
      deviceToken: device.deviceToken,
      deviceName: deviceName,
    );
  }

  /// The [HttpCloudAdapter] for an established session — the handoff point
  /// from the account plane to the sync plane.
  static HttpCloudAdapter adapterFor(TeamSession session,
          {http.Client? client}) =>
      HttpCloudAdapter(
        baseUrl: session.baseUrl,
        companyId: session.companyId,
        deviceToken: session.deviceToken,
        client: client,
      );

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body, {
    String? authToken,
  }) async {
    final response = await _client.post(
      Uri.parse('$baseUrl$path'),
      headers: {
        'Content-Type': 'application/json',
        if (authToken != null) 'Authorization': 'Bearer $authToken',
      },
      body: jsonEncode(body),
    );
    return _decodeResponse(response);
  }

  Future<Map<String, dynamic>> _get(String path,
      {required String authToken}) async {
    final response = await _client.get(
      Uri.parse('$baseUrl$path'),
      headers: {'Authorization': 'Bearer $authToken'},
    );
    return _decodeResponse(response);
  }

  Future<Map<String, dynamic>> _delete(String path,
      {required String authToken}) async {
    final response = await _client.delete(
      Uri.parse('$baseUrl$path'),
      headers: {'Authorization': 'Bearer $authToken'},
    );
    return _decodeResponse(response);
  }

  Map<String, dynamic> _decodeResponse(http.Response response) {
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
    if (response.body.isEmpty) return const {};
    try {
      final decoded = jsonDecode(response.body);
      return decoded is Map<String, dynamic> ? decoded : const {};
    } catch (_) {
      return const {};
    }
  }
}
