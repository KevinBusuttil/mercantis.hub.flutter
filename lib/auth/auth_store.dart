import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mercantis_core/mercantis_core.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

import '../settings/hub_settings.dart';
import 'operator_profile.dart';

/// Auth snapshot driving the lock gate and the current-user override.
class AuthState {
  const AuthState({
    this.profiles = const [],
    this.activeId,
    this.unlocked = false,
    this.hydrated = false,
  });

  /// All on-device operator profiles, oldest first.
  final List<OperatorProfile> profiles;

  /// The profile whose session is active (signed in), even while locked.
  final String? activeId;

  /// Whether the active profile has passed the passcode this run.
  final bool unlocked;

  /// True once the singleton auth doc has been read at boot.
  final bool hydrated;

  bool get hasProfiles => profiles.isNotEmpty;

  OperatorProfile? get active {
    for (final p in profiles) {
      if (p.id == activeId) return p;
    }
    return null;
  }

  AuthState copyWith({
    List<OperatorProfile>? profiles,
    Object? activeId = _unset,
    bool? unlocked,
    bool? hydrated,
  }) =>
      AuthState(
        profiles: profiles ?? this.profiles,
        activeId: activeId == _unset ? this.activeId : activeId as String?,
        unlocked: unlocked ?? this.unlocked,
        hydrated: hydrated ?? this.hydrated,
      );

  static const _unset = Object();
}

/// Owns the operator profiles and the lock state. Profiles persist in a single
/// `Hub Auth` document (same pattern as [HubSettings]) so they ride the sync
/// engine and survive restarts; the active session is remembered but always
/// re-locked on a cold start.
class AuthNotifier extends Notifier<AuthState> {
  static const docType = 'Hub Auth';
  static const docId = 'hub-auth';
  static const _roles = {'System Manager'};

  @override
  AuthState build() => const AuthState();

  Future<void> hydrate(DocumentEngine engine) async {
    final doc = await engine.fetch(docType, docId);
    if (doc == null) {
      state = state.copyWith(hydrated: true);
      return;
    }
    final raw = doc.payload['profiles'];
    // Stored as a JSON string; tolerate a raw list too for forward safety.
    final list = raw is String && raw.isNotEmpty
        ? (jsonDecode(raw) as List)
        : (raw is List ? raw : const []);
    final profiles = <OperatorProfile>[
      for (final p in list)
        if (p is Map) OperatorProfile.fromJson(Map<String, dynamic>.from(p)),
    ];
    final active = doc.payload['active_id'];
    state = AuthState(
      profiles: profiles,
      activeId: active is String && active.isNotEmpty ? active : null,
      unlocked: false,
      hydrated: true,
    );
  }

  Future<void> _persist(DocumentEngine engine) async {
    await engine.save(
      Document(
        id: docId,
        docType: docType,
        payload: {
          'profiles':
              jsonEncode([for (final p in state.profiles) p.toJson()]),
          'active_id': state.activeId ?? '',
        },
      ),
      _roles,
    );
  }

  /// Create a profile. The first one created is signed in and unlocked
  /// immediately (you just proved you know its passcode by setting it).
  Future<OperatorProfile> createProfile(
    DocumentEngine engine, {
    required String name,
    required String email,
    required String passcode,
    Set<String> roles = const {'System Manager'},
  }) async {
    final profile = OperatorProfile.create(
      id: 'op-${DateTime.now().microsecondsSinceEpoch}',
      name: name,
      email: email,
      passcode: passcode,
      roles: roles,
    );
    final first = state.profiles.isEmpty;
    state = state.copyWith(
      profiles: [...state.profiles, profile],
      activeId: first ? profile.id : state.activeId,
      unlocked: first ? true : state.unlocked,
    );
    await _persist(engine);
    return profile;
  }

  /// Verify [passcode] for [profileId]; on success start an unlocked session.
  Future<bool> unlock(
    DocumentEngine engine, {
    required String profileId,
    required String passcode,
  }) async {
    final profile = state.profiles.firstWhere(
      (p) => p.id == profileId,
      orElse: () => throw StateError('Unknown profile'),
    );
    if (!profile.verify(passcode)) return false;
    state = state.copyWith(activeId: profileId, unlocked: true);
    await _persist(engine);
    return true;
  }

  /// Re-lock without forgetting who is signed in.
  void lock() => state = state.copyWith(unlocked: false);

  /// Forget the active session entirely (returns to the profile picker).
  Future<void> signOut(DocumentEngine engine) async {
    state = state.copyWith(activeId: null, unlocked: false);
    await _persist(engine);
  }

  Future<bool> changePasscode(
    DocumentEngine engine, {
    required String profileId,
    required String current,
    required String next,
  }) async {
    final idx = state.profiles.indexWhere((p) => p.id == profileId);
    if (idx < 0) return false;
    if (!state.profiles[idx].verify(current)) return false;
    final updated = [...state.profiles];
    updated[idx] = updated[idx].withPasscode(next);
    state = state.copyWith(profiles: updated);
    await _persist(engine);
    return true;
  }

  Future<void> removeProfile(DocumentEngine engine, String profileId) async {
    final remaining =
        state.profiles.where((p) => p.id != profileId).toList();
    final clearedActive = state.activeId == profileId;
    state = state.copyWith(
      profiles: remaining,
      activeId: clearedActive ? null : state.activeId,
      unlocked: clearedActive ? false : state.unlocked,
    );
    await _persist(engine);
  }
}

final authProvider =
    NotifierProvider<AuthNotifier, AuthState>(AuthNotifier.new);

/// The active operator drives the current user. While no profile is unlocked
/// (first run, or before the lock gate is passed) we fall back to the persisted
/// settings operator so providers still resolve to a sane identity.
final hubCurrentUserOverride = currentUserProvider.overrideWith((ref) {
  final auth = ref.watch(authProvider);
  final p = auth.active;
  if (p != null && auth.unlocked) {
    return CurrentUser(
      id: p.id,
      displayName: p.name,
      email: p.email,
      roles: p.roles,
    );
  }
  final s = ref.watch(hubSettingsProvider);
  return CurrentUser(
    id: 'operator',
    displayName: s.operatorName,
    email: s.operatorEmail,
    roles: const {'System Manager'},
  );
});
