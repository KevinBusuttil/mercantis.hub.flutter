import 'package:flutter/material.dart';
import 'package:mercantis_core/mercantis_core.dart'
    show UnsupportedSchemaVersionException;
import 'package:mercantis_core_ui/mercantis_core_ui.dart';

import '../support/diagnostic_log.dart';
import '../support/support_diagnostics.dart';
import 'support_screen.dart' show DiagnosticsReportView;

/// Shown when Atlas cannot start. Says in plain words what to do, never
/// suggests deleting data, and offers the support report even though the
/// rest of the app is unavailable.
class StartupErrorScreen extends StatefulWidget {
  const StartupErrorScreen({super.key, required this.error, this.stack});

  final Object error;
  final StackTrace? stack;

  @override
  State<StartupErrorScreen> createState() => _StartupErrorScreenState();
}

class _StartupErrorScreenState extends State<StartupErrorScreen> {
  late final Future<DiagnosticsReport> _report;

  @override
  void initState() {
    super.initState();
    DiagnosticLog.instance.record('boot', widget.error, widget.stack);
    _report = SupportDiagnostics.collect(
      bootError: '${widget.error}',
      events: DiagnosticLog.instance.events,
    );
  }

  bool get _newerData => widget.error is UnsupportedSchemaVersionException;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(MercantisSpacing.lg),
          children: [
            Icon(_newerData ? Icons.system_update : Icons.error_outline,
                size: 48, color: theme.colorScheme.error),
            const SizedBox(height: 12),
            Text(
              _newerData
                  ? 'Update Atlas to open your books'
                  : 'Atlas could not start',
              style: theme.textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              _newerData
                  ? '${widget.error} Your data has not been changed.'
                  : 'Your business data has not been deleted. Close Atlas '
                      'completely and open it again. If this screen comes '
                      'back, save the report below and send it to Atlas '
                      'support. Do not uninstall Atlas: on a phone that '
                      'removes the books stored on it.',
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: MercantisSpacing.lg),
            FutureBuilder<DiagnosticsReport>(
              future: _report,
              builder: (context, snap) {
                final report = snap.data;
                if (report == null) {
                  return const Center(child: CircularProgressIndicator());
                }
                return SizedBox(
                  height: 520,
                  child: DiagnosticsReportView(report: report),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
