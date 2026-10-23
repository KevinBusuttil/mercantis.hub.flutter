import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

/// Host side of integration_test/device_benchmark_test.dart: saves the
/// numbers reported by the device to build/perf/device_results.json.
Future<void> main() => integrationDriver(
      responseDataCallback: (data) async {
        final file = File('build/perf/device_results.json')
          ..createSync(recursive: true);
        file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert({
          'kind': 'device-benchmark',
          'generated_at': DateTime.now().toUtc().toIso8601String(),
          'warning': 'Fill in the device model, RAM and storage by hand: '
              'see docs/release/PERFORMANCE_BASELINES.md.',
          ...?data,
        }));
        stdout.writeln('Written to ${file.path}');
      },
    );
