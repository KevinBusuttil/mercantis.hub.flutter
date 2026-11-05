import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_hub_app/reports/report_providers.dart';

/// After "Retry owed postings" writes ledger rows, the open reports must
/// recompute instead of showing the cached figures without them.
void main() {
  test('invalidating the ledger report roots recomputes a cached report',
      () async {
    var builds = 0;
    final c = ProviderContainer(overrides: [
      aggregatingReportsProvider.overrideWith((ref) async {
        builds++;
        throw StateError('no books in this test');
      }),
    ]);
    addTearDown(c.dispose);
    final sub = c.listen(trialBalanceProvider, (_, __) {});
    addTearDown(sub.close);
    await expectLater(c.read(trialBalanceProvider.future), throwsStateError);
    await expectLater(c.read(trialBalanceProvider.future), throwsStateError);
    expect(builds, 1, reason: 'cached until something invalidates it');

    invalidateLedgerReports(c.invalidate);
    await expectLater(c.read(trialBalanceProvider.future), throwsStateError);
    expect(builds, 2, reason: 'recomputed after the retry');
  });

  test('every report root is covered', () {
    expect(ledgerReportRoots, contains(aggregatingReportsProvider));
    expect(ledgerReportRoots, contains(reportEngineProvider));
    expect(ledgerReportRoots, contains(dashboardEngineProvider));
  });
}
