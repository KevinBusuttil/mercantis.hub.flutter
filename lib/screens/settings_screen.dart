import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

import '../auth/auth_store.dart';
import '../auth/operator_setup_screen.dart';
import '../settings/hub_settings.dart';

/// App preferences: the signed-in operator (passcode lock managed by the auth
/// gate), optional-module visibility, and the advanced toggle. Module/advanced
/// settings persist to the `Hub Settings` singleton; visibility changes apply
/// on next launch.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late HubSettings _draft;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _draft = ref.read(hubSettingsProvider);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final engine = await ref.read(documentEngineProvider.future);
    await ref.read(hubSettingsProvider.notifier).save(engine, _draft);
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Settings saved')));
  }

  void _lock() => ref.read(authProvider.notifier).lock();

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text(
            'You will need to pick an operator and enter a passcode to sign '
            'back in.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Sign out')),
        ],
      ),
    );
    if (confirmed != true) return;
    final engine = await ref.read(documentEngineProvider.future);
    await ref.read(authProvider.notifier).signOut(engine);
  }

  Future<void> _addOperator() {
    return Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => const OperatorSetupScreen(firstRun: false),
    ));
  }

  Future<void> _changePasscode() async {
    final auth = ref.read(authProvider);
    final active = auth.active;
    if (active == null) return;
    await showDialog<void>(
      context: context,
      builder: (_) => _ChangePasscodeDialog(profileId: active.id),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final auth = ref.watch(authProvider);
    final active = auth.active;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Signed in', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: CircleAvatar(
                  child: Text(_initials(active?.name ?? '?'))),
              title: Text(active?.name ?? 'No operator'),
              subtitle: Text([
                if ((active?.email ?? '').isNotEmpty) active!.email,
                active == null
                    ? ''
                    : active.roles.join(', '),
              ].where((s) => s.isNotEmpty).join('  ·  ')),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: active == null ? null : _changePasscode,
                icon: const Icon(Icons.password),
                label: const Text('Change passcode'),
              ),
              OutlinedButton.icon(
                onPressed: _addOperator,
                icon: const Icon(Icons.person_add_alt),
                label: const Text('Add operator'),
              ),
              OutlinedButton.icon(
                onPressed: _lock,
                icon: const Icon(Icons.lock_outline),
                label: const Text('Lock'),
              ),
              OutlinedButton.icon(
                onPressed: _signOut,
                icon: const Icon(Icons.logout),
                label: const Text('Sign out'),
              ),
            ],
          ),
          if (auth.profiles.length > 1)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('${auth.profiles.length} operators on this device',
                  style: theme.textTheme.bodySmall),
            ),
          const Divider(height: 32),
          Text('Optional modules', style: theme.textTheme.titleMedium),
          Text('Hidden modules apply on next launch.',
              style: theme.textTheme.bodySmall),
          SwitchListTile(
            title: const Text('Point of Sale'),
            value: _draft.posEnabled,
            onChanged: _saving
                ? null
                : (v) => setState(() => _draft = _draft.copyWith(posEnabled: v)),
          ),
          SwitchListTile(
            title: const Text('Manufacturing'),
            value: _draft.manufacturingEnabled,
            onChanged: _saving
                ? null
                : (v) => setState(
                    () => _draft = _draft.copyWith(manufacturingEnabled: v)),
          ),
          SwitchListTile(
            title: const Text('Deliveries (routes & fleet)'),
            value: _draft.deliveriesEnabled,
            onChanged: _saving
                ? null
                : (v) => setState(
                    () => _draft = _draft.copyWith(deliveriesEnabled: v)),
          ),
          const Divider(height: 32),
          SwitchListTile(
            title: const Text('Advanced mode'),
            subtitle: const Text('Show advanced fields and tracking surfaces'),
            value: _draft.advancedMode,
            onChanged: _saving
                ? null
                : (v) =>
                    setState(() => _draft = _draft.copyWith(advancedMode: v)),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.save_outlined),
            label: const Text('Save settings'),
          ),
        ],
      ),
    );
  }

  static String _initials(String name) {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }
}

/// Re-derive the active operator's passcode after verifying the current one.
class _ChangePasscodeDialog extends ConsumerStatefulWidget {
  const _ChangePasscodeDialog({required this.profileId});
  final String profileId;

  @override
  ConsumerState<_ChangePasscodeDialog> createState() =>
      _ChangePasscodeDialogState();
}

class _ChangePasscodeDialogState extends ConsumerState<_ChangePasscodeDialog> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_next.text.length < 4) {
      setState(() => _error = 'New passcode must be at least 4 digits.');
      return;
    }
    if (_next.text != _confirm.text) {
      setState(() => _error = 'New passcodes do not match.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final engine = await ref.read(documentEngineProvider.future);
    final ok = await ref.read(authProvider.notifier).changePasscode(
          engine,
          profileId: widget.profileId,
          current: _current.text,
          next: _next.text,
        );
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _busy = false;
        _error = 'Current passcode is incorrect.';
      });
      return;
    }
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Passcode updated')));
  }

  @override
  Widget build(BuildContext context) {
    InputDecoration deco(String label) =>
        InputDecoration(labelText: label, border: const OutlineInputBorder());
    final formatters = [FilteringTextInputFormatter.digitsOnly];
    return AlertDialog(
      title: const Text('Change passcode'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _current,
            obscureText: true,
            enabled: !_busy,
            keyboardType: TextInputType.number,
            inputFormatters: formatters,
            decoration: deco('Current passcode'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _next,
            obscureText: true,
            enabled: !_busy,
            keyboardType: TextInputType.number,
            inputFormatters: formatters,
            decoration: deco('New passcode'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _confirm,
            obscureText: true,
            enabled: !_busy,
            keyboardType: TextInputType.number,
            inputFormatters: formatters,
            decoration: deco('Confirm new passcode'),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel')),
        FilledButton(
            onPressed: _busy ? null : _submit, child: const Text('Update')),
      ],
    );
  }
}
