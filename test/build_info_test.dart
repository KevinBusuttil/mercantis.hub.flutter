import 'package:flutter_test/flutter_test.dart';
import 'package:mercantis_hub_app/build_info.dart';

/// Under `flutter test` no `--dart-define`s are passed, so BuildInfo shows its
/// fallbacks — and an un-stamped build must never masquerade as a real release.
void main() {
  test('unstamped build is clearly marked as a dev build', () {
    expect(BuildInfo.commit, 'dev');
    expect(BuildInfo.hasCommit, isFalse);
    expect(BuildInfo.commitLabel, 'dev build (not stamped)');
    expect(BuildInfo.ref, isEmpty);
    expect(BuildInfo.buildTime, isEmpty);
    expect(BuildInfo.appVersion, '1.0.0');
    expect(BuildInfo.summary, 'v1.0.0 · dev build (not stamped)');
  });
}
