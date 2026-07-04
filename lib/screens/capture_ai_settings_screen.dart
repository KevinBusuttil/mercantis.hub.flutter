import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

import '../capture/capture_providers.dart';
import '../capture/capture_settings.dart';
import '../capture/capture_settings_providers.dart';
import '../capture/llm_receipt_extractor.dart';

/// Settings for the opt-in AI fallback (ADR-049). Lets the user connect their
/// preferred LLM (Anthropic or any OpenAI-compatible endpoint) with their own
/// key, gated by a confidence threshold and a monthly cap.
class CaptureAiSettingsScreen extends ConsumerStatefulWidget {
  const CaptureAiSettingsScreen({super.key});

  @override
  ConsumerState<CaptureAiSettingsScreen> createState() =>
      _CaptureAiSettingsScreenState();
}

class _CaptureAiSettingsScreenState
    extends ConsumerState<CaptureAiSettingsScreen> {
  final _endpoint = TextEditingController();
  final _model = TextEditingController();
  final _apiKey = TextEditingController();
  final _monthlyLimit = TextEditingController();

  bool _enabled = false;
  LlmProvider _provider = LlmProvider.anthropic;
  double _threshold = 0.6;
  bool _loading = true;
  bool _obscureKey = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_endpoint, _model, _apiKey, _monthlyLimit]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final settings = await ref.read(captureAiSettingsProvider.future);
    final key = await ref.read(captureAiApiKeyProvider.future);
    if (!mounted) return;
    setState(() {
      _enabled = settings.enabled;
      _provider = settings.provider;
      _endpoint.text = settings.endpoint;
      _model.text = settings.model;
      _threshold = settings.threshold;
      _monthlyLimit.text = settings.monthlyLimit.toString();
      _apiKey.text = key ?? '';
      _loading = false;
    });
  }

  void _onProviderChanged(LlmProvider? p) {
    if (p == null) return;
    setState(() {
      // Swap to the provider's default base URL if the field still holds the
      // other provider's default.
      if (_endpoint.text.trim().isEmpty ||
          _endpoint.text == LlmReceiptExtractor.anthropicBaseUrl ||
          _endpoint.text == LlmReceiptExtractor.openAiBaseUrl) {
        _endpoint.text = p == LlmProvider.anthropic
            ? LlmReceiptExtractor.anthropicBaseUrl
            : LlmReceiptExtractor.openAiBaseUrl;
      }
      _provider = p;
    });
  }

  String _providerLabel(LlmProvider p) =>
      p == LlmProvider.anthropic ? 'Anthropic (Claude)' : 'OpenAI-compatible';

  LlmProvider _providerFromLabel(String label) => label == 'Anthropic (Claude)'
      ? LlmProvider.anthropic
      : LlmProvider.openAiCompatible;

  Future<void> _save() async {
    final settings = CaptureAiSettings(
      enabled: _enabled,
      provider: _provider,
      endpoint: _endpoint.text.trim(),
      model: _model.text.trim(),
      threshold: _threshold,
      monthlyLimit: int.tryParse(_monthlyLimit.text.trim()) ?? 100,
    );
    await ref.read(captureAiSettingsProvider.notifier).save(settings);
    await setCaptureAiApiKey(_apiKey.text.trim());
    ref.invalidate(captureAiApiKeyProvider);
    ref.invalidate(captureServiceProvider);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('AI settings saved.')));
  }

  @override
  Widget build(BuildContext context) {
    final usage = ref.watch(captureAiUsageThisMonthProvider);
    return ResponsiveScaffold(
      title: 'Smart capture (AI)',
      padBody: false,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(MercantisSpacing.lg),
              children: [
                Text(
                  'When a receipt is hard to read on-device, the app can ask an '
                  'AI to read it. This sends the photo to the provider you choose, '
                  'using your own key. Off by default.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: MercantisSpacing.md),
                AtlasSectionCard(
                  name: 'Provider',
                  child: Column(
                    children: [
                      AtlasFieldRow(
                        label: 'Use AI for hard-to-read receipts',
                        onTap: () => setState(() => _enabled = !_enabled),
                        trailing: Switch(
                          value: _enabled,
                          onChanged: (v) => setState(() => _enabled = v),
                        ),
                      ),
                      AtlasSelectorRow(
                        label: 'Provider',
                        value: _providerLabel(_provider),
                        options: const [
                          'Anthropic (Claude)',
                          'OpenAI-compatible',
                        ],
                        onChanged: (label) =>
                            _onProviderChanged(_providerFromLabel(label)),
                      ),
                      AtlasTextInputRow(
                        label: 'API base URL',
                        value: _endpoint.text,
                        onChanged: (v) => _endpoint.text = v,
                      ),
                      AtlasTextInputRow(
                        label: 'Model',
                        value: _model.text,
                        onChanged: (v) => _model.text = v,
                      ),
                      // The API key keeps a raw obscured field with a reveal
                      // toggle — Atlas rows have no obscure/suffix slot.
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            vertical: MercantisSpacing.sm),
                        child: TextField(
                          controller: _apiKey,
                          obscureText: _obscureKey,
                          decoration: InputDecoration(
                            labelText: 'API key',
                            border: const OutlineInputBorder(),
                            helperText:
                                'Stored on this device. Use a scoped/limited key.',
                            suffixIcon: IconButton(
                              icon: Icon(_obscureKey
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined),
                              onPressed: () =>
                                  setState(() => _obscureKey = !_obscureKey),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: MercantisSpacing.lg),
                AtlasSectionCard(
                  name: 'Limits',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Ask AI when confidence is below '
                          '${(_threshold * 100).round()}%'),
                      Slider(
                        value: _threshold,
                        min: 0.3,
                        max: 0.9,
                        divisions: 6,
                        label: '${(_threshold * 100).round()}%',
                        onChanged: (v) => setState(() => _threshold = v),
                      ),
                      AtlasTextInputRow(
                        label: 'Monthly AI limit (cost cap)',
                        value: _monthlyLimit.text,
                        keyboardType: TextInputType.number,
                        onChanged: (v) => _monthlyLimit.text = v,
                      ),
                      const SizedBox(height: MercantisSpacing.sm),
                      usage.maybeWhen(
                        data: (n) => Text('Used $n this month',
                            style: Theme.of(context).textTheme.bodySmall),
                        orElse: () => const SizedBox.shrink(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: MercantisSpacing.xl),
                FilledButton.icon(
                  onPressed: _save,
                  icon: const Icon(Icons.save_outlined),
                  style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52)),
                  label: const Text('Save'),
                ),
              ],
            ),
    );
  }
}
