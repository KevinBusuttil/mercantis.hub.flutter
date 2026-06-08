import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

import '../settings/hub_settings.dart';

/// App preferences: the operator identity (replacing the old hardcoded user),
/// optional-module visibility, and the advanced toggle. Persisted to the
/// `Hub Settings` singleton; module-visibility changes apply on next launch.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late HubSettings _draft;
  late final TextEditingController _name;
  late final TextEditingController _email;
  bool _saving = false;
  String? _saved;

  @override
  void initState() {
    super.initState();
    _draft = ref.read(hubSettingsProvider);
    _name = TextEditingController(text: _draft.operatorName);
    _email = TextEditingController(text: _draft.operatorEmail);
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _saved = null;
    });
    final next = _draft.copyWith(
      operatorName: _name.text.trim().isEmpty ? 'Operator' : _name.text.trim(),
      operatorEmail: _email.text.trim(),
    );
    final engine = await ref.read(documentEngineProvider.future);
    await ref.read(hubSettingsProvider.notifier).save(engine, next);
    if (!mounted) return;
    setState(() {
      _draft = next;
      _saving = false;
      _saved = 'Saved';
    });
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Settings saved')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Operator', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          TextField(
            controller: _name,
            enabled: !_saving,
            decoration: const InputDecoration(labelText: 'Name', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _email,
            enabled: !_saving,
            decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder()),
          ),
          const Divider(height: 32),
          Text('Optional modules', style: Theme.of(context).textTheme.titleMedium),
          Text('Hidden modules apply on next launch.',
              style: Theme.of(context).textTheme.bodySmall),
          SwitchListTile(
            title: const Text('Point of Sale'),
            value: _draft.posEnabled,
            onChanged: _saving ? null : (v) => setState(() => _draft = _draft.copyWith(posEnabled: v)),
          ),
          SwitchListTile(
            title: const Text('Manufacturing'),
            value: _draft.manufacturingEnabled,
            onChanged: _saving ? null : (v) => setState(() => _draft = _draft.copyWith(manufacturingEnabled: v)),
          ),
          SwitchListTile(
            title: const Text('Deliveries (routes & fleet)'),
            value: _draft.deliveriesEnabled,
            onChanged: _saving ? null : (v) => setState(() => _draft = _draft.copyWith(deliveriesEnabled: v)),
          ),
          const Divider(height: 32),
          SwitchListTile(
            title: const Text('Advanced mode'),
            subtitle: const Text('Show advanced fields and tracking surfaces'),
            value: _draft.advancedMode,
            onChanged: _saving ? null : (v) => setState(() => _draft = _draft.copyWith(advancedMode: v)),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.save_outlined),
            label: const Text('Save settings'),
          ),
          if (_saved != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_saved!, style: TextStyle(color: Theme.of(context).colorScheme.primary)),
            ),
        ],
      ),
    );
  }
}
