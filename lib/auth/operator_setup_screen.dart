import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

import 'auth_store.dart';

/// Create an operator profile and its passcode. On first run this is the gate's
/// landing screen; it is also pushed from the lock screen to add more operators.
class OperatorSetupScreen extends ConsumerStatefulWidget {
  const OperatorSetupScreen({super.key, this.firstRun = false});

  /// True when no profiles exist yet (renders as a full landing page rather
  /// than a pushed route with a back button).
  final bool firstRun;

  @override
  ConsumerState<OperatorSetupScreen> createState() =>
      _OperatorSetupScreenState();
}

class _OperatorSetupScreenState extends ConsumerState<OperatorSetupScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _pass = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;

  static const _minLength = 4;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _pass.dispose();
    _confirm.dispose();
    super.dispose();
  }

  String? _validate() {
    if (_name.text.trim().isEmpty) return 'Enter a name.';
    if (_pass.text.length < _minLength) {
      return 'Passcode must be at least $_minLength digits.';
    }
    if (_pass.text != _confirm.text) return 'Passcodes do not match.';
    return null;
  }

  Future<void> _create() async {
    final problem = _validate();
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final engine = await ref.read(documentEngineProvider.future);
      final notifier = ref.read(authProvider.notifier);
      final profile = await notifier.createProfile(
        engine,
        name: _name.text.trim(),
        email: _email.text.trim(),
        passcode: _pass.text,
      );
      // Adding from the lock screen: sign straight into the new profile.
      if (!ref.read(authProvider).unlocked) {
        await notifier.unlock(
          engine,
          profileId: profile.id,
          passcode: _pass.text,
        );
      }
      if (!mounted) return;
      if (!widget.firstRun) Navigator.of(context).pop();
      // First run: the gate rebuilds on the now-unlocked state.
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final body = Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(24),
          children: [
            if (widget.firstRun) ...[
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.lock_outline, color: Colors.white),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text('Create your operator',
                        style: theme.textTheme.titleLarge),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Operators sign in on this device with a passcode. Add more '
                'later from the lock screen or Settings.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 24),
            ],
            TextField(
              controller: _name,
              enabled: !_busy,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _email,
              enabled: !_busy,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Email (optional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _pass,
              enabled: !_busy,
              obscureText: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Passcode',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _confirm,
              enabled: !_busy,
              obscureText: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onSubmitted: (_) => _busy ? null : _create(),
              decoration: const InputDecoration(
                labelText: 'Confirm passcode',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _busy ? null : _create,
              icon: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.person_add_alt),
              label: Text(widget.firstRun ? 'Create & sign in' : 'Add operator'),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child:
                    Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
              ),
          ],
        ),
      ),
    );

    if (widget.firstRun) return Scaffold(body: body);
    return Scaffold(
      appBar: AppBar(title: const Text('Add operator')),
      body: body,
    );
  }
}
