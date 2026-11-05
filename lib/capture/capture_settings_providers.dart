import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'capture_secret_store.dart';
import 'capture_settings.dart';

const _kSettings = 'capture.ai.settings';
const _kApiKey = 'capture.ai.api_key';
const _kQuotaMonth = 'capture.ai.quota_month';
const _kQuotaCount = 'capture.ai.quota_count';

/// User-controlled AI fallback settings, persisted locally. Off by default.
final captureAiSettingsProvider =
    AsyncNotifierProvider<CaptureAiSettingsController, CaptureAiSettings>(
        CaptureAiSettingsController.new);

class CaptureAiSettingsController extends AsyncNotifier<CaptureAiSettings> {
  @override
  Future<CaptureAiSettings> build() => _load();

  Future<CaptureAiSettings> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kSettings);
      if (raw == null) return const CaptureAiSettings();
      return CaptureAiSettings.fromJson(
          jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const CaptureAiSettings();
    }
  }

  Future<void> save(CaptureAiSettings settings) async {
    state = AsyncData(settings);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kSettings, jsonEncode(settings.toJson()));
    } catch (_) {
      // No prefs platform (tests): keep the in-memory state.
    }
  }
}

/// The secure store the key lives in. Overridden in tests.
final captureSecretStoreProvider =
    Provider<CaptureSecretStore>((ref) => SecureCaptureSecretStore());

/// The API key, from secure storage (null when unset, or when it cannot be
/// read safely: AI capture then stays off). Moves a key left in plaintext
/// preferences by older versions on first read (R4).
final captureAiApiKeyProvider = FutureProvider<String?>((ref) async {
  final store = ref.watch(captureSecretStoreProvider);
  await CaptureKeyMigration.run(store);
  try {
    final v = await store.read();
    return (v == null || v.isEmpty) ? null : v;
  } catch (_) {
    return null;
  }
});

/// Persist the API key in secure storage, verified, and remove any legacy
/// plaintext copy. An empty [key] removes it. Throws when secure storage
/// cannot hold it: nothing falls back to plaintext. Caller invalidates
/// [captureAiApiKeyProvider] after.
Future<void> setCaptureAiApiKey(CaptureSecretStore store, String key) async {
  if (key.isEmpty) {
    await store.delete();
  } else {
    await store.write(key);
    if (await store.read() != key) {
      throw StateError('secure storage did not keep the key');
    }
  }
  await CaptureKeyMigration.removeLegacy();
}

/// One-time move of `capture.ai.api_key` out of SharedPreferences.
///
/// Idempotent: write to secure storage, read it back, and only then delete
/// the plaintext copy. A failure leaves the legacy value where it was (so no
/// key is lost) and the key unused (so nothing runs on a plaintext secret);
/// the next start tries again. If secure storage already holds a key, the
/// legacy copy is stale and is simply removed.
abstract final class CaptureKeyMigration {
  static const legacyKey = _kApiKey;

  static Future<bool> run(CaptureSecretStore store) async {
    SharedPreferences prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (_) {
      return false;
    }
    final legacy = prefs.getString(_kApiKey);
    if (legacy == null) return true;
    try {
      final current = await store.read();
      if (current == null || current.isEmpty) {
        if (legacy.isNotEmpty) {
          await store.write(legacy);
          if (await store.read() != legacy) return false;
        }
      }
      await prefs.remove(_kApiKey);
      return !prefs.containsKey(_kApiKey);
    } catch (_) {
      return false;
    }
  }

  static Future<void> removeLegacy() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kApiKey);
    } catch (_) {}
  }
}

/// AI calls already made this calendar month (for the settings display).
final captureAiUsageThisMonthProvider = FutureProvider<int>((ref) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kQuotaMonth) == _currentMonth()
        ? (prefs.getInt(_kQuotaCount) ?? 0)
        : 0;
  } catch (_) {
    return 0;
  }
});

/// Atomically consume one unit of the monthly AI quota. Returns true if a call
/// was permitted (and recorded); false when the cap is reached or unavailable.
/// Resets automatically at the start of each calendar month.
Future<bool> consumeMonthlyCaptureQuota(int limit) async {
  if (limit <= 0) return false;
  try {
    final prefs = await SharedPreferences.getInstance();
    final month = _currentMonth();
    final used = prefs.getString(_kQuotaMonth) == month
        ? (prefs.getInt(_kQuotaCount) ?? 0)
        : 0;
    if (used >= limit) return false;
    await prefs.setString(_kQuotaMonth, month);
    await prefs.setInt(_kQuotaCount, used + 1);
    return true;
  } catch (_) {
    // No prefs platform: allow the call rather than block the feature.
    return true;
  }
}

String _currentMonth() {
  final now = DateTime.now();
  return '${now.year}-${now.month.toString().padLeft(2, '0')}';
}
