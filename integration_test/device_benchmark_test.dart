import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mercantis_hub_app/main.dart' as app;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as sqflite;

import '../test/perf/solo_workload.dart';

/// On-device performance run (brief §C). Run it in PROFILE mode on a
/// physical device, never an emulator or simulator, and never in debug:
///
///   flutter drive --profile \
///     --driver=test_driver/perf_driver.dart \
///     --target=integration_test/device_benchmark_test.dart \
///     -d <device-id> \
///     --dart-define=ATLAS_PERF_CUSTOMERS=10000
///
/// The driver writes build/perf/device_results.json. Record the device and
/// OS (docs/release/PERFORMANCE_BASELINES.md §4) next to the numbers. Cold and
/// warm process start are measured separately by tool/perf/android_startup.sh
/// (am start -W) or Xcode Instruments, because an integration test runs
/// inside an already-started process.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const customers =
      int.fromEnvironment('ATLAS_PERF_CUSTOMERS', defaultValue: 10000);
  const items = int.fromEnvironment('ATLAS_PERF_ITEMS', defaultValue: 5000);

  testWidgets('in-process boot to first usable screen', (tester) async {
    final sw = Stopwatch()..start();
    await tester.pumpWidget(app.buildAtlasApp());
    // Boot shows a progress indicator until the books are open, migrated
    // and the ledger is wired; then onboarding, the lock screen or the
    // shell appears.
    while (find.byType(CircularProgressIndicator).evaluate().isNotEmpty &&
        sw.elapsed < const Duration(seconds: 120)) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    sw.stop();
    (binding.reportData ??= {})['boot_to_ready_ms'] =
        sw.elapsedMicroseconds / 1000.0;
  });

  testWidgets('Solo data-layer workload on this device', (tester) async {
    final results = await tester.runAsync(() async {
      final base = await getTemporaryDirectory();
      final root = Directory('${base.path}/atlas_perf')
        ..createSync(recursive: true);
      for (final e in root.listSync()) {
        e.deleteSync(recursive: true);
      }
      try {
        return await runSoloWorkload(
          rootDir: root.path,
          factory: sqflite.databaseFactory,
          customers: customers,
          itemCount: items,
        );
      } finally {
        root.deleteSync(recursive: true);
      }
    });
    (binding.reportData ??= {})['workload'] = results;
    binding.reportData!['device'] = {
      'os': Platform.operatingSystem,
      'os_version': Platform.operatingSystemVersion,
      'processors': Platform.numberOfProcessors,
      'customers': customers,
      'items': items,
    };
  }, timeout: const Timeout(Duration(minutes: 60)));
}
