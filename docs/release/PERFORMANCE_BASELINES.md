# Atlas Solo — performance baselines and budgets

Status: 22 October 2026.

- **Host measurements:** done.
- **Device measurements:** **PENDING** for every row. No phone, tablet or desktop app run has been measured. No number below may be quoted as device performance.

## 1. What exists

| Layer | Tool | Runs where | Status |
|---|---|---|---|
| Data-layer workload: the production engine, interceptors, ledger and real SQLite | `test/perf/solo_workload.dart` | Shared | Implemented |
| Host baseline | `test/perf/host_benchmark_test.dart` (`ATLAS_PERF=1`) | CI acceptance gate (artifact `host-perf-baseline`) and laptops | **Measured** (§3) |
| Device data layer + in-process boot | `integration_test/device_benchmark_test.dart`, driver `test_driver/perf_driver.dart` | Physical device, profile mode | Implemented, **not run** |
| Cold / warm process start (Android) | `tool/perf/android_startup.sh` (`am start -W`, 10 runs each) | Physical Android device | Implemented, **not run** |
| Cold / warm start (iOS) | Xcode Instruments › App Launch template | Physical iPhone | Procedure only, **not run** |
| Memory on device | Android Studio Profiler or `adb shell dumpsys meminfo com.neuradix.atlas`; Xcode Memory Report | Physical devices | Procedure only, **not run** |

## 2. Fixture (deterministic, synthetic)

The fixture contains no customer data. Every run builds the same book:

- a fresh install (migrate, install manifest, seed chart, VAT and fiscal year);
- 10,000 customers;
- 5,000 stock items with searchable names;
- 2 warehouses;
- 100 stock purchases of 4 lines (200 items × 100 units on hand);
- 50 sales invoices of 5 stock lines, each posting GL, stock ledger, COGS and receivables;
- the trial balance, P&L, balance sheet, AR ageing, stock valuation and stock-to-GL reports;
- 10 attachments of 2 MB;
- `PRAGMA quick_check`;
- an encrypted backup with the production Argon2id parameters;
- staged restore with to-the-cent verification, then commit and re-open.

Nothing is synced: every change waits in the outbound queue, which is the "long offline session" condition (18,529 queued changes).

## 3. Host results (measured 22 Oct 2026)

**Host:** Linux 6.18, 4 vCPU cloud container, Dart 3.12.0, Flutter 3.44.0 test runner, sqflite_common_ffi with the system libsqlite3. Raw file: [perf/host_baseline_2026-10-22_linux_4cpu.json](perf/host_baseline_2026-10-22_linux_4cpu.json). CI reruns this on every push (`host-perf-baseline` artifact) on a GitHub `ubuntu-latest` runner.

| Operation | Host result |
|---|---|
| Database initialisation, fresh install (migrate + manifest + seed + ledger wiring) | 1,234 ms |
| Database initialisation, existing book (normal start) | 333 ms |
| Create 1,000 customers (one save each) | 5.1 s (≈5 ms per save) |
| Load 1,000 customers (all) / first page of 50 | 25 ms / 2 ms |
| Load 10,000 customers (all) / first page of 50 | 100 ms / 6 ms |
| Search 10,000 customers by name (LIKE, 50 rows), p50 / p95 | 4.4 / 5.0 ms |
| Search 5,000-item catalogue by name, p50 / p95 | 4.1 / 5.0 ms |
| Post a 4-line stock purchase (100 in a row) | 155 ms each (15.5 s total) |
| **Create and post a 5-line stock invoice** (GL, stock, COGS, AR), p50 / p95 / max | **160 / 190 / 199 ms** |
| Stock availability, one item (Bin fetch), p50 / p95 | 0.5 / 0.6 ms |
| Stock availability, all positions | 3.5 ms |
| Trial balance / P&L / balance sheet | 20 / 16 / 19 ms |
| AR ageing / stock valuation / stock-to-GL reconciliation | 5 / 6 / 20 ms |
| Attach a 2 MB receipt (atomic write + SHA-256), p50 / p95 | 65 / 102 ms |
| Book size: 18,028 documents, DB file | 18.4 MB |
| Integrity quick check | 24 ms |
| **Encrypted backup** of 18.4 MB DB + 20 MB attachments (38.2 MB file) | **15.6 s** |
| Restore: decrypt, verify, stage | 6.7 s |
| Restore: atomic swap + to-the-cent verification | 0.6 s |
| Re-open restored book | 0.28 s |
| Test-process RSS growth over the run (Dart VM + test runner, **not the app**) | 122 MB |

**Reading the host results:**

- The data layer is not the bottleneck for daily work. List, search, stock and report queries are milliseconds at 10,000 customers and 5,000 items.
- Posting an invoice costs about 160 ms of pure data work on this host. Most of it is ledger derivation: GL, stock ledger, Bin recompute and outstanding amounts.
- **Backup is the slow path.** About 2.5 MB/s end to end, dominated by the pure-Dart AES-GCM and Argon2id already noted as R10. A phone is typically 2–5× slower than this host, so a 40 MB backup could take one minute or more on a low-end Android phone. This must be measured on a device before the pilot (P-PERF-1). The fix (`cryptography_flutter` platform AES) is a drop-in, but it is a change to the backup path and needs its own tests.
- Report timings are flat at this size. The reports load whole doctypes into memory (`engine.list`) and fold in Dart. Expect linear growth with GL rows. At about 20× this book (hundreds of thousands of GL rows) the reports and memory will need SQL aggregation. That is POST-GA unless a pilot customer is that large.

## 4. Device run procedure (PENDING)

Record for every run:

- device model;
- SoC;
- RAM;
- storage type;
- OS version and build;
- free storage;
- battery saver off;
- Atlas version, build and commit (from Settings › About);
- profile or release mode.

1. Use a **physical device**. Emulators and simulators are not accepted.
2. Data layer and boot:
   ```bash
   flutter drive --profile -d <device> \
     --driver=test_driver/perf_driver.dart \
     --target=integration_test/device_benchmark_test.dart
   ```
   This writes `build/perf/device_results.json`. Add the device details above.
3. Android cold and warm start:
   ```bash
   flutter build apk --profile
   adb install -r build/app/outputs/flutter-apk/app-profile.apk
   tool/perf/android_startup.sh 10
   ```
   Run it twice: once on a fresh install (onboarding), once with the 10,000-customer book restored from the benchmark backup.
4. iOS cold start: Xcode › Product › Profile › **App Launch** on a release build, 5 launches, median.
5. Memory:
   - after opening Customers (10,000) and the P&L, `adb shell dumpsys meminfo com.neuradix.atlas` (record TOTAL PSS);
   - on iOS, the Xcode memory gauge.
6. UI smoothness:
   - scroll the 10,000-customer list for 10 s with `flutter run --profile` and the performance overlay, or DevTools;
   - record jank, meaning frames over 16 ms.
7. Long offline session: use the device for a working week with networking off, then record the diagnostics report's change-log count and the boot time.
8. Attachments: photograph 10 receipts with the camera and record capture-to-saved time; then back up and record the time.

Commit the JSON and a row in §6 per device.

## 5. Proposed acceptance budgets (to be confirmed on devices)

These are **proposals**, derived from the host results with a 5× allowance for a low/mid Android phone (3–4 GB RAM, Android 11–13) and from usual mobile UX thresholds. They become release criteria only after the first device run confirms they are achievable, and the product owner accepts them.

| Measure (low/mid Android, release build) | Budget | Basis |
|---|---|---|
| Cold start to first frame (`am start -W` TotalTime) | ≤ 2.0 s | Android vitals "slow cold start" is ≥ 5 s; keep well clear |
| Cold start to usable screen (`boot_to_ready_ms`), 10k-customer book | ≤ 4.0 s | Host 0.33 s DB open × 5, plus engine and UI start |
| Warm start | ≤ 1.0 s | Android vitals "slow warm start" is ≥ 2 s |
| Open customer list (first page) at 10,000 customers | ≤ 300 ms | Host 6 ms |
| Customer or item search result | ≤ 300 ms | Host p95 5 ms |
| Create and post a 5-line invoice (tap Post → saved) | ≤ 1.5 s p95 | Host p95 190 ms × 5, plus UI |
| Stock availability on a line | ≤ 100 ms | Host 0.6 ms |
| Open P&L, balance sheet or AR ageing | ≤ 1.5 s | Host ≤ 20 ms; leaves room for growth |
| Attach a photographed receipt | ≤ 2 s after capture | Host 100 ms |
| Back up a 40 MB book | ≤ 120 s, with progress shown | Host 15.6 s × 5; the user is told to wait |
| Memory (TOTAL PSS) after customers + P&L at 10k customers | ≤ 350 MB | Typical Flutter app with a 20 MB SQLite book |
| Scroll jank in customer list | < 1 % frames over 16 ms | Smoothness |

**CI guard:** the host baseline is recorded on every push, but does not yet fail the build on a regression (host runner speed varies). Proposed next step: fail when a host metric is more than 3× the committed baseline.

## 6. Device results

| Date | Device (model, RAM, storage) | OS | Atlas build | Cold start | Warm start | Boot to ready | Invoice p95 | Backup 40 MB | PSS | By |
|---|---|---|---|---|---|---|---|---|---|---|
| — | Low/mid Android | — | — | **PENDING** | **PENDING** | **PENDING** | **PENDING** | **PENDING** | **PENDING** | — |
| — | Current Android | — | — | **PENDING** | **PENDING** | **PENDING** | **PENDING** | **PENDING** | **PENDING** | — |
| — | iPhone SE / current iPhone | — | — | **PENDING** | **PENDING** | **PENDING** | **PENDING** | **PENDING** | **PENDING** | — |
| — | iPad | — | — | **PENDING** | **PENDING** | **PENDING** | **PENDING** | **PENDING** | **PENDING** | — |
| — | Mac (Apple silicon) | — | — | **PENDING** | **PENDING** | **PENDING** | **PENDING** | **PENDING** | **PENDING** | — |
| — | Windows 11 PC | — | — | **PENDING** | **PENDING** | **PENDING** | **PENDING** | **PENDING** | **PENDING** | — |
