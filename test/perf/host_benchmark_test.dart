import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'solo_workload.dart';

/// Host performance baselines for the Solo data layer (plan M1.6, brief §C).
///
/// HOST NUMBERS, NOT DEVICE NUMBERS. This runs the production engine,
/// interceptors and ledger on real SQLite files through sqflite_common_ffi
/// on the machine running `flutter test` (a CI runner or a laptop). It
/// measures what the data layer costs, so regressions show up in CI, and it
/// gives the device runs a reference. It does not measure rendering, app
/// start-up, platform channels or a phone's storage and CPU. Device
/// procedures and budgets: docs/release/PERFORMANCE_BASELINES.md.
///
/// Skipped unless ATLAS_PERF=1 (it takes a few minutes):
///
///   ATLAS_PERF=1 flutter test test/perf --reporter expanded
///
/// Results are printed and written to build/perf/host_results.json.
void main() {
  final enabled = Platform.environment['ATLAS_PERF'] == '1';
  setUpAll(sqfliteFfiInit);

  test('Solo data-layer host baseline', skip: !enabled, () async {
    final root = Directory.systemTemp.createTempSync('atlas_perf_');
    final results =
        await runSoloWorkload(rootDir: root.path, factory: databaseFactoryFfi);
    final notes = [
      'RSS is the test process (Dart VM + flutter_test), not the app.',
    ];

    final report = {
      'kind': 'host-data-layer-baseline',
      'warning': 'Host machine numbers. Not a device measurement.',
      'generated_at': DateTime.now().toUtc().toIso8601String(),
      'host': {
        'os': Platform.operatingSystem,
        'os_version': Platform.operatingSystemVersion,
        'processors': Platform.numberOfProcessors,
        'dart': Platform.version.split(' ').first,
        'ci': Platform.environment['GITHUB_ACTIONS'] == 'true'
            ? 'GitHub Actions ${Platform.environment['RUNNER_OS'] ?? ''}'
            : 'local',
      },
      'results': results,
      'notes': notes,
    };
    final file = File(p.join('build', 'perf', 'host_results.json'))
      ..createSync(recursive: true)
      ..writeAsStringSync(const JsonEncoder.withIndent('  ').convert(report));
    // ignore: avoid_print
    print(const JsonEncoder.withIndent('  ').convert(report));
    // ignore: avoid_print
    print('Written to ${file.path}');
    root.deleteSync(recursive: true);
  }, timeout: const Timeout(Duration(minutes: 30)));
}
