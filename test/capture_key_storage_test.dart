import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_hub_app/backup/hub_backup.dart';
import 'package:mercantis_hub_app/capture/capture_secret_store.dart';
import 'package:mercantis_hub_app/capture/capture_settings_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// R4: the AI capture API key lives in secure storage only. Older versions
/// kept it in SharedPreferences (`capture.ai.api_key`); it is moved once,
/// verified before the plaintext copy is deleted.
void main() {
  const secret = 'not-a-real-key';
  late MemoryCaptureSecretStore store;

  ProviderContainer container() {
    final c = ProviderContainer(overrides: [
      captureSecretStoreProvider.overrideWithValue(store),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  setUp(() => store = MemoryCaptureSecretStore());

  test('a legacy plaintext key moves to secure storage and is deleted',
      () async {
    SharedPreferences.setMockInitialValues(
        {CaptureKeyMigration.legacyKey: secret, 'capture.ai.settings': '{}'});
    expect(await container().read(captureAiApiKeyProvider.future), secret);
    expect(store.value, secret);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey(CaptureKeyMigration.legacyKey), isFalse);
    expect(prefs.getString('capture.ai.settings'), '{}',
        reason: 'ordinary settings untouched');
  });

  test('migration is idempotent and survives a restart', () async {
    SharedPreferences.setMockInitialValues(
        {CaptureKeyMigration.legacyKey: secret});
    expect(await CaptureKeyMigration.run(store), isTrue);
    expect(await CaptureKeyMigration.run(store), isTrue);
    // "Restart": a new container reads from secure storage.
    expect(await container().read(captureAiApiKeyProvider.future), secret);
  });

  test('a failed migration keeps the legacy key and leaves AI capture off',
      () async {
    SharedPreferences.setMockInitialValues(
        {CaptureKeyMigration.legacyKey: secret});
    store.failWrites = true;
    expect(await container().read(captureAiApiKeyProvider.future), isNull,
        reason: 'the plaintext value is never used');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(CaptureKeyMigration.legacyKey), secret,
        reason: 'not deleted before it is safely stored');
    // Secure storage comes back: the next start completes the move.
    store.failWrites = false;
    expect(await container().read(captureAiApiKeyProvider.future), secret);
    expect(prefs.containsKey(CaptureKeyMigration.legacyKey), isFalse);
  });

  test('an unreadable secure store disables AI capture safely', () async {
    SharedPreferences.setMockInitialValues({});
    store.value = secret;
    store.failReads = true;
    expect(await container().read(captureAiApiKeyProvider.future), isNull);
  });

  test('a stale legacy copy is removed when secure storage has a key',
      () async {
    SharedPreferences.setMockInitialValues(
        {CaptureKeyMigration.legacyKey: 'old-key'});
    store.value = secret;
    expect(await container().read(captureAiApiKeyProvider.future), secret);
    expect((await SharedPreferences.getInstance())
        .containsKey(CaptureKeyMigration.legacyKey), isFalse);
  });

  test('saving writes secure storage only; removing the key removes it',
      () async {
    SharedPreferences.setMockInitialValues({});
    await setCaptureAiApiKey(store, secret);
    expect(store.value, secret);
    final prefs = await SharedPreferences.getInstance();
    for (final k in prefs.getKeys()) {
      expect('${prefs.get(k)}', isNot(contains(secret)));
    }
    await setCaptureAiApiKey(store, '');
    expect(store.value, isNull);
    expect(await container().read(captureAiApiKeyProvider.future), isNull);
  });

  test('saving refuses (no plaintext fallback) when secure storage fails',
      () async {
    SharedPreferences.setMockInitialValues({});
    store.failWrites = true;
    await expectLater(setCaptureAiApiKey(store, secret), throwsStateError);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys(), isEmpty);
  });

  test('the key is never in backed-up preferences', () async {
    SharedPreferences.setMockInitialValues(
        {CaptureKeyMigration.legacyKey: secret, 'capture.ai.settings': '{}'});
    expect(backedUpPreferenceKeys, isNot(contains(CaptureKeyMigration.legacyKey)));
    final backed = await HubBackup.readPreferences();
    expect(backed.values.join(), isNot(contains(secret)));
  });
}
