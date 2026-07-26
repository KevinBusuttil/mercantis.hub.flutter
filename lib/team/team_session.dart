import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// This device's connection to an Atlas Team backend: where it is, which
/// company it belongs to, and the credentials issued at join time.
///
/// Stored in the platform keychain (never as an engine document: engine
/// documents ride the sync plane, and the device token is a per-device
/// secret that must never replicate to other devices).
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

  /// Same connection with a replaced account credential (token rotation).
  TeamSession withUserToken(String newToken) => TeamSession(
        baseUrl: baseUrl,
        companyId: companyId,
        companyName: companyName,
        userId: userId,
        userToken: newToken,
        deviceId: deviceId,
        deviceToken: deviceToken,
        deviceName: deviceName,
      );

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

/// Loads/saves the [TeamSession] in the platform keychain (Phase 0.5,
/// gap analysis §8-C8). Earlier builds kept it in [SharedPreferences] —
/// plaintext on disk; [load] migrates such an entry into the keychain once
/// and deletes the plaintext copy.
class TeamSessionStore {
  TeamSessionStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'atlas_team_session';
  final FlutterSecureStorage _storage;

  Future<TeamSession?> load() async {
    final raw = await _storage.read(key: _key);
    if (raw != null && raw.isNotEmpty) return _decode(raw);
    return _migrateLegacy();
  }

  /// One-time move of a pre-keychain session out of plaintext preferences.
  Future<TeamSession?> _migrateLegacy() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return null;
    final session = _decode(raw);
    if (session != null) {
      await _storage.write(key: _key, value: raw);
    }
    await prefs.remove(_key); // plaintext copy goes either way
    return session;
  }

  TeamSession? _decode(String raw) {
    try {
      return TeamSession.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null; // Corrupt entry — treat as signed out rather than wedging.
    }
  }

  Future<void> save(TeamSession session) async {
    await _storage.write(key: _key, value: jsonEncode(session.toJson()));
  }

  Future<void> clear() async {
    await _storage.delete(key: _key);
    // Also drop any lingering pre-migration copy.
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
