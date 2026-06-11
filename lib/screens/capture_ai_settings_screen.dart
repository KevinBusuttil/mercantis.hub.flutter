import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    return Scaffold(
      appBar: AppBar(title: const Text('Smart capture (AI)')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'When a receipt is hard to read on-device, the app can ask an '
                  'AI to read it. This sends the photo to the provider you choose, '
                  'using your own key. Off by default.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Use AI for hard-to-read receipts'),
                  value: _enabled,
                  onChanged: (v) => setState(() => _enabled = v),
                ),
                const Divider(),
                DropdownButtonFormField<LlmProvider>(
                  initialValue: _provider,
                  decoration: const InputDecoration(
                      labelText: 'Provider', border: OutlineInputBorder()),
                  items: const [
                    DropdownMenuItem(
                        value: LlmProvider.anthropic,
                        child: Text('Anthropic (Claude)')),
                    DropdownMenuItem(
                        value: LlmProvider.openAiCompatible,
                        child: Text('OpenAI-compatible')),
                  ],
                  onChanged: _onProviderChanged,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _endpoint,
                  decoration: const InputDecoration(
                      labelText: 'API base URL', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _model,
                  decoration: const InputDecoration(
                      labelText: 'Model',
                      border: OutlineInputBorder(),
                      helperText: 'e.g. claude-opus-4-8, or your provider\'s model id'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _apiKey,
                  obscureText: _obscureKey,
                  decoration: InputDecoration(
                    labelText: 'API key',
                    border: const OutlineInputBorder(),
                    helperText: 'Stored on this device. Use a scoped/limited key.',
                    suffixIcon: IconButton(
                      icon: Icon(_obscureKey
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined),
                      onPressed: () =>
                          setState(() => _obscureKey = !_obscureKey),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
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
                TextField(
                  controller: _monthlyLimit,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'Monthly AI limit (cost cap)',
                      border: OutlineInputBorder()),
                ),
                const SizedBox(height: 8),
                usage.maybeWhen(
                  data: (n) => Text('Used $n this month',
                      style: Theme.of(context).textTheme.bodySmall),
                  orElse: () => const SizedBox.shrink(),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _save,
                  icon: const Icon(Icons.save_outlined),
                  style:
                      FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                  label: const Text('Save'),
                ),
              ],
            ),
    );
  }
}
