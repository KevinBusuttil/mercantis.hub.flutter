# Atlas Solo — reproducible release process

Status: 22 October 2026. This is how a build becomes a release candidate. Nothing here publishes to a store or creates a public GitHub release: those need the product owner's written authorisation for that version.

## 1. What makes a build reproducible

| Input | Pinned by |
|---|---|
| Flutter SDK | `FLUTTER_VERSION: "3.44.0"` in both workflows |
| Dart and pub dependencies | **`pubspec.lock` is committed.** CI runs `flutter pub get --enforce-lockfile`, so a build fails rather than silently resolving other versions. Before this increment the lockfile was git-ignored and two builds of one commit could differ. |
| Atlas Core | Exact commit in `pubspec.yaml` (`ref:`) and `resolved-ref` in the lockfile |
| Android toolchain | Gradle wrapper 9.1, AGP 9.0.1, Kotlin 2.3.20, Java 17 (Temurin in CI) |
| Apple toolchain | GitHub `macos-latest` image. **Not pinned:** record the Xcode version from the job log in the release record, and pin `xcode-select` when Apple signing is added |
| Windows toolchain | GitHub `windows-latest` image (Visual Studio 2022). Record from the log |
| Version | `version:` in `pubspec.yaml` gives the marketing version. The build number is `1000 + GitHub run number` (monotonic). Commit, ref and UTC build time are stamped with `--dart-define`, and appear in Settings › About and the diagnostics report |

## 2. Versioning

- `pubspec.yaml` `version: X.Y.Z+N`. The pipeline uses `X.Y.Z` as the build name and **replaces** `N` with its own build number.
- Bump `X.Y.Z` in a pull request before a release candidate:
  - patch for fixes;
  - minor for features;
  - major for a backup-format or schema change that older builds cannot read.
- Tag the release commit `atlas-vX.Y.Z-rcN` (candidate) or `atlas-vX.Y.Z` (final) **only after** the gates in §4 pass. Pushing an `atlas-v*` tag runs **Release builds** (unsigned) on that exact commit.
- Artifact names carry the full identity: `atlas-<X.Y.Z>+<build>-<sha10>-<platform>`, each with `SHA256SUMS.txt`.

## 3. Pipeline overview

| Workflow / job | Trigger | Proves |
|---|---|---|
| `CI › flutter analyze` | every push and PR | Static analysis clean |
| `CI › flutter test` | every push and PR | All unit, widget and DB tests |
| `CI › Solo commercial acceptance gate` | every push and PR | Canonical journey and clean-folder restore; opening migration; fault injection and posting outbox; R14 guard; stock/COGS and financial reports; diagnostics privacy; accessibility guidelines and responsive layouts; golden; host performance baseline (artifact `host-perf-baseline`) |
| `CI › Secret and dependency scan` | every push and PR | No signing material committed; gitleaks over full history; OSV scan of `pubspec.lock`; outdated report |
| `Release builds › Android/iOS/macOS/Windows` | PRs touching platform files or the lockfile, `main`, `atlas-v*` tags, manual | Release-mode compilation on each platform with stamped version and checksums. iOS is `--no-codesign`, macOS ad-hoc, Windows and Android unsigned |
| `Release builds › Android (signed upload build)` | manual run with **signed**, approved in the `release` environment | Signed AAB and APK, signature verified, checksums |
| `Marketing screenshots` | existing | Unchanged |

Database migration from the previous release is covered by Core `migration_safety_test` (every schema version from v1 up) and Hub `solo_fault_test › repeated restart`. Backup/restore regression is `solo_acceptance_test` plus Core `backup_restore_test`.

## 4. Release-candidate procedure

1. **Freeze.** Merge only fixes. Bump `version:` and merge.
2. **Green gates** on the release commit on `main`. Every job above must be green. Save the run URLs in the release record (§5).
3. **Build unsigned** happens automatically on `main`. Download the artifacts and check that `SHA256SUMS.txt` matches.
4. **Build signed Android:** **Actions › Release builds › Run workflow**, tick **signed**, approve in the `release` environment. Record the certificate SHA-256 printed by `apksigner`. It must be the same upload certificate as every previous release.
5. **Install the signed build** on the reference devices (platform matrix §3) from a clean state:
   - first run;
   - the restore drill (R1);
   - the device performance run;
   - the TalkBack pass.
   Record each in [SOLO_RELEASE_READINESS.md](SOLO_RELEASE_READINESS.md).
6. **Upgrade check.** Install the **previous** signed release with a representative book, then install the candidate over it (same id and key). Confirm:
   - the books open;
   - the diagnostics report shows the new schema version and `postings owed (failed): 0`;
   - the trial balance is unchanged.
7. **Tag** `atlas-vX.Y.Z-rcN` on that commit.
8. **Product-owner decision:** distribute to pilot devices (Play internal testing, or a supervised APK install) or stop. Store publication is a separate, explicit decision.

## 5. Release record (copy per candidate)

```text
Version / build:            X.Y.Z (NNNN), commit <sha>, tag atlas-vX.Y.Z-rcN
CI runs:                    CI <url>   Release builds <url>   Signed Android <url>
Flutter / Xcode / VS:       3.44.0 / <from log> / <from log>
Artifacts + SHA-256:        <paste SHA256SUMS.txt>
Android upload cert SHA-256: <from apksigner>  (same as previous: yes/no)
Device checks:              <device, OS, result, date, by> ...
Upgrade from:               <previous version> -> result
Known issues accepted:      <ids from SOLO_RELEASE_READINESS.md>
Decision:                   distribute to pilot / hold   — by <name>, <date>
```

## 6. Rollback

- **Store builds cannot be downgraded in place.** The fix is a new build with a higher build number that reverts the change.
- **A database already migrated** to a newer schema is refused by the older build. That is deliberate: it can never be silently corrupted. Users roll back by restoring the backup made **before** the upgrade (the upgrade guide requires one) into the older build, or by staying on the new build until a fix ships.
- **A pilot rollback** follows [FIRST_CUSTOMER_PILOT.md](FIRST_CUSTOMER_PILOT.md) §9.
