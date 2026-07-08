import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// This device's connection to an Atlas Team backend: where it is, which
/// company it belongs to, and the credentials issued at join time.
///
/// Deliberately stored in [SharedPreferences], NOT as an engine document:
/// engine documents ride the sync plane, and the device token is a
/// per-device secret that must never replicate to other devices.
class TeamSession {
  const TeamSession({
    required this.baseUrl,
    required this.companyId,
    required this.companyName,
    required this.userId,
    required this.userToken,
    required this.deviceId,
    required this.deviceToken,
    required this.deviceName,
  });

  /// e.g. `https://team.neuradix.app`
  final String baseUrl;
  final String companyId;
  final String companyName;
  final String userId;

  /// Account-level credential (invitations, settings, audit).
  final String userToken;
  final String deviceId;

  /// Sync-plane credential — what [HttpCloudAdapter] authenticates with.
  final String deviceToken;
  final String deviceName;

  Map<String, dynamic> toJson() => {
        'baseUrl': baseUrl,
        'companyId': companyId,
        'companyName': companyName,
        'userId': userId,
        'userToken': userToken,
        'deviceId': deviceId,
        'deviceToken': deviceToken,
        'deviceName': deviceName,
      };

  factory TeamSession.fromJson(Map<String, dynamic> json) => TeamSession(
        baseUrl: '${json['baseUrl'] ?? ''}',
        companyId: '${json['companyId'] ?? ''}',
        companyName: '${json['companyName'] ?? ''}',
        userId: '${json['userId'] ?? ''}',
        userToken: '${json['userToken'] ?? ''}',
        deviceId: '${json['deviceId'] ?? ''}',
        deviceToken: '${json['deviceToken'] ?? ''}',
        deviceName: '${json['deviceName'] ?? ''}',
      );
}

/// Loads/saves the [TeamSession] under a single preferences key.
class TeamSessionStore {
  static const _key = 'atlas_team_session';

  Future<TeamSession?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return null;
    try {
      return TeamSession.fromJson(
          jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null; // Corrupt entry — treat as signed out rather than wedging.
    }
  }

  Future<void> save(TeamSession session) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(session.toJson()));
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}

final teamSessionStoreProvider = Provider((_) => TeamSessionStore());

/// The current Team connection (null = Solo / not connected). Hydrated once
/// at boot; [connect]/[disconnect] persist and update in place.
class TeamSessionNotifier extends StateNotifier<TeamSession?> {
  TeamSessionNotifier(this._store) : super(null);

  final TeamSessionStore _store;

  Future<void> hydrate() async => state = await _store.load();

  Future<void> connect(TeamSession session) async {
    await _store.save(session);
    state = session;
  }

  Future<void> disconnect() async {
    await _store.clear();
    state = null;
  }
}

final teamSessionProvider =
    StateNotifierProvider<TeamSessionNotifier, TeamSession?>(
        (ref) => TeamSessionNotifier(ref.watch(teamSessionStoreProvider)));
