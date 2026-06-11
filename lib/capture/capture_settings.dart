import 'llm_receipt_extractor.dart';

/// User-controlled configuration for the opt-in AI fallback (ADR-049). The API
/// key is stored separately (not in this model). Off by default — the app is
/// local-first; turning this on is a deliberate choice to send receipt images
/// to the user's chosen LLM when the on-device read is weak.
class CaptureAiSettings {
  const CaptureAiSettings({
    this.enabled = false,
    this.provider = LlmProvider.anthropic,
    this.endpoint = LlmReceiptExtractor.anthropicBaseUrl,
    this.model = 'claude-opus-4-8',
    this.threshold = 0.6,
    this.monthlyLimit = 100,
  });

  /// Master switch. When false the AI fallback never runs.
  final bool enabled;
  final LlmProvider provider;

  /// API base URL for the chosen provider.
  final String endpoint;
  final String model;

  /// Call the LLM only when the local read's confidence is below this.
  final double threshold;

  /// Safety cap on AI calls per calendar month (cost guard).
  final int monthlyLimit;

  CaptureAiSettings copyWith({
    bool? enabled,
    LlmProvider? provider,
    String? endpoint,
    String? model,
    double? threshold,
    int? monthlyLimit,
  }) =>
      CaptureAiSettings(
        enabled: enabled ?? this.enabled,
        provider: provider ?? this.provider,
        endpoint: endpoint ?? this.endpoint,
        model: model ?? this.model,
        threshold: threshold ?? this.threshold,
        monthlyLimit: monthlyLimit ?? this.monthlyLimit,
      );

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'provider': provider.name,
        'endpoint': endpoint,
        'model': model,
        'threshold': threshold,
        'monthlyLimit': monthlyLimit,
      };

  factory CaptureAiSettings.fromJson(Map<String, dynamic> json) {
    const defaults = CaptureAiSettings();
    return CaptureAiSettings(
      enabled: json['enabled'] as bool? ?? defaults.enabled,
      provider: LlmProvider.values.firstWhere(
        (p) => p.name == json['provider'],
        orElse: () => defaults.provider,
      ),
      endpoint: (json['endpoint'] as String?) ?? defaults.endpoint,
      model: (json['model'] as String?) ?? defaults.model,
      threshold: (json['threshold'] as num?)?.toDouble() ?? defaults.threshold,
      monthlyLimit: (json['monthlyLimit'] as num?)?.toInt() ?? defaults.monthlyLimit,
    );
  }
}
