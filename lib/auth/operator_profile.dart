import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// A local operator identity. The Hub has no backend, so "logging in" means
/// unlocking one of these on-device profiles with a passcode. The passcode is
/// never stored — only a salted, stretched SHA-256 digest of it.
class OperatorProfile {
  const OperatorProfile({
    required this.id,
    required this.name,
    required this.email,
    required this.roles,
    required this.salt,
    required this.passcodeHash,
    required this.createdAt,
  });

  final String id;
  final String name;
  final String email;
  final Set<String> roles;

  /// Base64 random salt mixed into the passcode digest.
  final String salt;

  /// Base64 stretched SHA-256 digest of `salt + passcode`.
  final String passcodeHash;
  final String createdAt;

  /// Number of SHA-256 rounds. Cheap enough to stay imperceptible on unlock,
  /// high enough to slow brute force against a stolen database.
  static const _rounds = 100000;

  /// True when [passcode] reproduces this profile's stored digest.
  bool verify(String passcode) =>
      _digest(passcode, base64Decode(salt)) == passcodeHash;

  OperatorProfile copyWith({
    String? name,
    String? email,
    Set<String>? roles,
    String? salt,
    String? passcodeHash,
  }) =>
      OperatorProfile(
        id: id,
        name: name ?? this.name,
        email: email ?? this.email,
        roles: roles ?? this.roles,
        salt: salt ?? this.salt,
        passcodeHash: passcodeHash ?? this.passcodeHash,
        createdAt: createdAt,
      );

  /// Build a profile with a freshly salted digest for [passcode].
  factory OperatorProfile.create({
    required String id,
    required String name,
    required String email,
    required String passcode,
    Set<String> roles = const {'System Manager'},
  }) {
    final salt = _randomSalt();
    return OperatorProfile(
      id: id,
      name: name,
      email: email,
      roles: roles,
      salt: base64Encode(salt),
      passcodeHash: _digest(passcode, salt),
      createdAt: DateTime.now().toIso8601String(),
    );
  }

  /// Re-derive the digest for a new [passcode] under a fresh salt.
  OperatorProfile withPasscode(String passcode) {
    final salt = _randomSalt();
    return copyWith(
      salt: base64Encode(salt),
      passcodeHash: _digest(passcode, salt),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'email': email,
        'roles': roles.toList(),
        'salt': salt,
        'passcode_hash': passcodeHash,
        'created_at': createdAt,
      };

  factory OperatorProfile.fromJson(Map<String, dynamic> j) => OperatorProfile(
        id: '${j['id']}',
        name: '${j['name'] ?? ''}',
        email: '${j['email'] ?? ''}',
        roles: {
          for (final r in (j['roles'] as List? ?? const ['System Manager']))
            '$r',
        },
        salt: '${j['salt'] ?? ''}',
        passcodeHash: '${j['passcode_hash'] ?? ''}',
        createdAt: '${j['created_at'] ?? ''}',
      );

  static List<int> _randomSalt() {
    final rng = Random.secure();
    return List<int>.generate(16, (_) => rng.nextInt(256));
  }

  static String _digest(String passcode, List<int> salt) {
    var bytes = <int>[...salt, ...utf8.encode(passcode)];
    for (var i = 0; i < _rounds; i++) {
      bytes = sha256.convert(bytes).bytes;
    }
    return base64Encode(bytes);
  }
}
