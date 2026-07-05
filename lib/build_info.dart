/// Build provenance surfaced in **Settings → About**, so you can confirm a
/// running build matches the commit you intended to ship.
///
/// Values are injected at build time via `--dart-define`. Without them (a plain
/// `flutter run` / `flutter build`) they fall back to placeholders and the
/// commit reads as a "dev build". Inject the real values with, e.g.:
///
/// ```sh
/// flutter build apk \
///   --dart-define=GIT_COMMIT=$(git rev-parse --short HEAD) \
///   --dart-define=GIT_REF=$(git rev-parse --abbrev-ref HEAD) \
///   --dart-define=BUILD_TIME=$(date -u +%Y-%m-%dT%H:%MZ)
/// ```
///
/// (`--dart-define` values are compile-time constants, so `BuildInfo` stays
/// dependency-free — no plugin, no generated file to keep in sync.)
class BuildInfo {
  const BuildInfo._();

  /// Marketing version. Defaults to the `pubspec.yaml` version; override with
  /// `--dart-define=APP_VERSION=...` if a pipeline stamps it separately.
  static const appVersion =
      String.fromEnvironment('APP_VERSION', defaultValue: '1.0.0');

  /// Short git SHA of the built commit, or `dev` when not injected.
  static const commit = String.fromEnvironment('GIT_COMMIT', defaultValue: 'dev');

  /// Branch / ref the build came from (empty when not injected).
  static const ref = String.fromEnvironment('GIT_REF', defaultValue: '');

  /// UTC build timestamp (empty when not injected).
  static const buildTime =
      String.fromEnvironment('BUILD_TIME', defaultValue: '');

  /// True when a real commit SHA was injected at build time (i.e. not a plain
  /// local build).
  static bool get hasCommit => commit != 'dev';

  /// The commit shown in the UI — the SHA, or a clear "dev build" marker so an
  /// un-stamped build never masquerades as a real release.
  static String get commitLabel => hasCommit ? commit : 'dev build (not stamped)';

  /// One-line summary, e.g. `v1.0.0 · a1b2c3d`.
  static String get summary => 'v$appVersion · $commitLabel';
}
