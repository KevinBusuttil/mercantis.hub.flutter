import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

import 'auth_store.dart';
import 'operator_profile.dart';
import 'operator_setup_screen.dart';

/// The passcode gate shown on a locked cold start: pick an operator, enter the
/// passcode. Pre-selects the last active profile so the common case is a single
/// passcode entry.
class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key});

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  final _pass = TextEditingController();
  String? _selectedId;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final auth = ref.read(authProvider);
    _selectedId = auth.activeId ??
        (auth.profiles.isNotEmpty ? auth.profiles.first.id : null);
  }

  @override
  void dispose() {
    _pass.dispose();
    super.dispose();
  }

  Future<void> _unlock() async {
    final id = _selectedId;
    if (id == null || _pass.text.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final engine = await ref.read(documentEngineProvider.future);
    final ok = await ref.read(authProvider.notifier).unlock(
          engine,
          profileId: id,
          passcode: _pass.text,
        );
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _busy = false;
        _error = 'Incorrect passcode.';
        _pass.clear();
      });
    }
    // On success the gate rebuilds into the shell.
  }

  void _select(OperatorProfile p) {
    setState(() {
      _selectedId = p.id;
      _pass.clear();
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final profiles = ref.watch(authProvider).profiles;

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(24),
            children: [
              Column(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child:
                        const Icon(Icons.lock_outline, color: Colors.white, size: 30),
                  ),
                  const SizedBox(height: 12),
                  Text('Neuradix Atlas', style: theme.textTheme.titleLarge),
                  Text('Choose an operator to sign in',
                      style: theme.textTheme.bodySmall),
                ],
              ),
              const SizedBox(height: 24),
              for (final p in profiles)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    selected: p.id == _selectedId,
                    leading: CircleAvatar(child: Text(_initials(p.name))),
                    title: Text(p.name),
                    subtitle: p.email.isEmpty ? null : Text(p.email),
                    trailing: p.id == _selectedId
                        ? const Icon(Icons.radio_button_checked)
                        : const Icon(Icons.radio_button_unchecked),
                    onTap: _busy ? null : () => _select(p),
                  ),
                ),
              const SizedBox(height: 8),
              TextField(
                controller: _pass,
                enabled: !_busy && _selectedId != null,
                obscureText: true,
                autofocus: true,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onSubmitted: (_) => _busy ? null : _unlock(),
                decoration: const InputDecoration(
                  labelText: 'Passcode',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.password),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _busy || _selectedId == null ? null : _unlock,
                icon: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.login),
                label: const Text('Unlock'),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(_error!,
                      style: TextStyle(color: theme.colorScheme.error)),
                ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: _busy
                    ? null
                    : () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) =>
                              const OperatorSetupScreen(firstRun: false),
                        )),
                icon: const Icon(Icons.person_add_alt),
                label: const Text('Add operator'),
              ),
            ],
          ),
        ),
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
