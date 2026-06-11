import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_hub_app/capture/capture_settings.dart';
import 'package:mercantis_hub_app/capture/llm_receipt_extractor.dart';

/// ADR-049: AI settings model. Off by default; round-trips through JSON.
void main() {
  test('defaults are safe: disabled, Anthropic, sensible cap', () {
    const s = CaptureAiSettings();
    expect(s.enabled, isFalse);
    expect(s.provider, LlmProvider.anthropic);
    expect(s.endpoint, LlmReceiptExtractor.anthropicBaseUrl);
    expect(s.model, 'claude-opus-4-8');
    expect(s.threshold, 0.6);
    expect(s.monthlyLimit, greaterThan(0));
  });

  test('round-trips through JSON', () {
    const s = CaptureAiSettings(
      enabled: true,
      provider: LlmProvider.openAiCompatible,
      endpoint: 'https://example.com/v1',
      model: 'gpt-4o-mini',
      threshold: 0.5,
      monthlyLimit: 50,
    );
    final back = CaptureAiSettings.fromJson(s.toJson());
    expect(back.enabled, isTrue);
    expect(back.provider, LlmProvider.openAiCompatible);
    expect(back.endpoint, 'https://example.com/v1');
    expect(back.model, 'gpt-4o-mini');
    expect(back.threshold, 0.5);
    expect(back.monthlyLimit, 50);
  });

  test('unknown/empty JSON falls back to defaults', () {
    final back = CaptureAiSettings.fromJson(const {});
    expect(back.enabled, isFalse);
    expect(back.provider, LlmProvider.anthropic);
  });
}
