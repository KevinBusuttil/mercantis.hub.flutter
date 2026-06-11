import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

/// The stored API key (null/empty when unset). Stored in app-private prefs —
/// it's the user's own key; recommend a scoped/limited key.
final captureAiApiKeyProvider = FutureProvider<String?>((ref) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kApiKey);
  } catch (_) {
    return null;
  }
});

/// Persist the API key. Caller invalidates [captureAiApiKeyProvider] after.
Future<void> setCaptureAiApiKey(String key) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kApiKey, key);
  } catch (_) {}
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
