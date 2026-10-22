import 'package:flutter/material.dart';

/// What to tell the user once the app is back after a restart.
class RestartNotice {
  const RestartNotice({
    required this.success,
    required this.title,
    required this.body,
  });
  final bool success;
  final String title;
  final String body;
}

/// Lets a restore stop the whole app (every provider, the open database,
/// timers), swap the data underneath, and start again from boot.
///
/// [AtlasRestartScope] sits above the root `ProviderScope`. [restart] first
/// removes that scope from the tree (disposing every provider), runs
/// `whileStopped` with nothing else touching the data, shows the notice it
/// returns, then mounts a fresh scope whose boot reopens the database,
/// re-runs startup recovery and reloads every setting.
class AtlasRestartScope extends StatefulWidget {
  const AtlasRestartScope({super.key, required this.builder});

  final Widget Function(BuildContext context) builder;

  static Future<void> restart(BuildContext context,
      {required Future<RestartNotice?> Function() whileStopped,
      String message = 'Restoring your books…'}) {
    final state = context.findAncestorStateOfType<_AtlasRestartScopeState>();
    if (state == null) {
      throw StateError('No AtlasRestartScope above this context');
    }
    return state._restart(whileStopped, message);
  }

  @override
  State<AtlasRestartScope> createState() => _AtlasRestartScopeState();
}

class _AtlasRestartScopeState extends State<AtlasRestartScope> {
  Key _generation = UniqueKey();
  String? _working;
  RestartNotice? _notice;

  Future<void> _restart(
      Future<RestartNotice?> Function() whileStopped, String message) async {
    setState(() => _working = message);
    // Let the frame that unmounts the old scope run, so its providers are
    // disposed before the data moves.
    await WidgetsBinding.instance.endOfFrame;
    RestartNotice? notice;
    try {
      notice = await whileStopped();
    } catch (e) {
      notice = RestartNotice(
          success: false,
          title: 'Something went wrong',
          body: 'Atlas restarted with the data it found. Details: $e');
    }
    if (!mounted) return;
    setState(() {
      _working = null;
      _notice = notice;
      _generation = UniqueKey();
    });
  }

  @override
  Widget build(BuildContext context) {
    final working = _working;
    if (working != null) {
      return _plain(Column(mainAxisSize: MainAxisSize.min, children: [
        const CircularProgressIndicator(),
        const SizedBox(height: 16),
        Text(working, textAlign: TextAlign.center),
        const SizedBox(height: 8),
        const Text('Keep Atlas open until this finishes.',
            textAlign: TextAlign.center),
      ]));
    }
    final notice = _notice;
    if (notice != null) {
      return _plain(Builder(
        builder: (context) => Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(
              notice.success
                  ? Icons.check_circle_outline
                  : Icons.error_outline,
              size: 48,
              color: notice.success ? Colors.green : Colors.orange),
          const SizedBox(height: 16),
          Text(notice.title,
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center),
          const SizedBox(height: 12),
          Text(notice.body, textAlign: TextAlign.center),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () => setState(() => _notice = null),
            child: const Text('Continue'),
          ),
        ]),
      ));
    }
    return KeyedSubtree(key: _generation, child: widget.builder(context));
  }

  Widget _plain(Widget child) => MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: child),
              ),
            ),
          ),
        ),
      );
}
