import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Where the AI capture API key lives: the platform's secure storage
/// (Android Keystore-backed, iOS/macOS Keychain, Windows Credential Manager,
/// libsecret). Never SharedPreferences, backups or diagnostics (R4).
abstract class CaptureSecretStore {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> delete();
}

class SecureCaptureSecretStore implements CaptureSecretStore {
  SecureCaptureSecretStore([FlutterSecureStorage? storage])
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  static const key = 'atlas.capture.ai.api_key.v1';
  final FlutterSecureStorage _storage;

  @override
  Future<String?> read() => _storage.read(key: key);

  @override
  Future<void> write(String value) => _storage.write(key: key, value: value);

  @override
  Future<void> delete() => _storage.delete(key: key);
}

/// Tests, and a device whose secure storage fails.
class MemoryCaptureSecretStore implements CaptureSecretStore {
  String? value;
  bool failWrites = false;
  bool failReads = false;

  @override
  Future<String?> read() async {
    if (failReads) throw StateError('secure storage unavailable');
    return value;
  }

  @override
  Future<void> write(String v) async {
    if (failWrites) throw StateError('secure storage unavailable');
    value = v;
  }

  @override
  Future<void> delete() async => value = null;
}
