# Atlas Solo — release-candidate package

Status: 22 October 2026. **Prepared, not yet produced.** This is the contents list and the device procedure for the first release candidate, `atlas-v1.0.0-rc1`. It cannot be produced until the product-owner prerequisites in [SOLO_RELEASE_READINESS.md](SOLO_RELEASE_READINESS.md) §5 are done. No RC has been tagged or distributed.

## 1. What an RC package contains

| # | Item | Source | Status |
|---|---|---|---|
| 1 | Signed Android AAB (Play upload) and APK (supervised install) | `Release builds › Android (signed upload build)` | **PENDING (REL-1)** |
| 2 | `SHA256SUMS.txt` and the upload-certificate SHA-256 | Same job | PENDING |
| 3 | Unsigned iOS, macOS and Windows builds, for internal checks only, **not for customers** | `Release builds` on the tag | Available on each run |
| 4 | Release record ([RELEASE_PROCESS.md](RELEASE_PROCESS.md) §5) | Filled in by the release manager | PENDING |
| 5 | Green CI run URLs for the tagged commit: CI (analyze, test, acceptance gate, security) and Release builds | GitHub Actions | PENDING (the tag) |
| 6 | Host performance artifact for the tagged commit | `host-perf-baseline` | Automatic |
| 7 | Device evidence: R1 drill, performance, TalkBack (§3) | This document §3, committed | **PENDING** |
| 8 | Known issues accepted for the RC, by id from the tracker §6 | Release record | PENDING |
| 9 | User guides 1–8 ([docs/solo/](../solo/README.md)) at the RC version | Repository | Drafts exist |
| 10 | Pilot agreement and policies, approved for the pilot | [policies/](policies/COMMERCIAL_POLICY_CHECKLIST.md) | Drafts, not approved |
| 11 | Pilot demo book `pilot-demo.atlasbackup` and its SHA-256 (for usability sessions and support training) | Built once on the RC | PENDING |

## 2. Producing the RC

Follow [RELEASE_PROCESS.md](RELEASE_PROCESS.md) §4, steps 1–8. In short:

1. Freeze and bump `version: 1.0.0+1` (already 1.0.0).
2. Green gates on `main`.
3. Signed Android run approved in `release`.
4. Device checks (§3 here).
5. Tag `atlas-v1.0.0-rc1`.
6. Product-owner decision to give it to the pilot.

## 3. Device checks on the signed build (record the results here)

Run these on the signed APK or AAB from step 3, on a **physical** low/mid Android phone (platform matrix §3). Record:

- the device model;
- Android version;
- the Atlas version and build from **Settings › About**;
- the date;
- who ran it;
- the result.

### 3.1 R1: clean-install restore drill (BLOCKER-SOLO-RC)

1. Install the signed build. Complete first run. Build a representative book: either restore the acceptance fixture, or enter 20 invoices, 5 bills, 5 payments, 1 credit note and 3 receipt photos.
2. Note these figures:
   - the trial-balance total;
   - the bank balance;
   - **Who owes you** total;
   - stock value;
   - the last invoice number.
3. **Back up now**, then **Save a copy to another place…** to a cloud drive (Google Drive).
4. **Uninstall Atlas.** Confirm the app data is gone. Reinstall the same signed build.
5. First screen: **Restore from a backup instead**. Fetch the file from the cloud drive and enter the passphrase. Check the summary, then type `REPLACE`.
6. Compare every figure from step 2. Open the 3 receipt photos. Check that **Help & diagnostics** shows integrity `ok` and postings owed `0`.
7. Post a new invoice. Check that its number follows the last one, and back up again.
8. Repeat steps 3–6, but **switch the phone off during the restore** (after typing REPLACE). On the next start Atlas must either finish or undo the restore, with the books intact.

| Drill | Device / OS | Build | Date | Result | By |
|---|---|---|---|---|---|
| R1 clean reinstall | — | — | — | **PENDING** | — |
| R1 interrupted restore | — | — | — | **PENDING** | — |
| Restore of a backup made on another device | — | — | — | **PENDING** | — |

### 3.2 Device performance

Follow [PERFORMANCE_BASELINES.md](PERFORMANCE_BASELINES.md) §4, and fill its §6 row. P-PERF-1: back up the benchmark book (about 40 MB) and time it.

### 3.3 TalkBack and large text (A11Y-ANDROID)

Rows A1–A11 of [ACCESSIBILITY_ACCEPTANCE.md](ACCESSIBILITY_ACCEPTANCE.md) §2, Android phone column.

### 3.4 Install, upgrade and uninstall facts

| Check | Expected | Result |
|---|---|---|
| Play install, or `adb install`, of the signed APK | Installs as **Neuradix Atlas**, package `com.neuradix.atlas` | PENDING |
| Permissions shown in system settings | Network only, no runtime permission prompts until the camera is used | PENDING |
| Android Settings › Google backup | Atlas data not included | PENDING |
| Install RC2 over RC1 (same key) with data | Books open; diagnostics show the same schema or a migrated one; trial balance unchanged | PENDING (at RC2) |
| Install a debug or other-key build over it | Refused by Android (signature mismatch) | PENDING |

## 4. RC exit decision

The product owner records one of these in the release record:

- **Distribute to pilot.** All `BLOCKER-SOLO-RC` items are closed, and the §3 tables are filled and passing.
- **Hold.** Give the reason and the issue ids.
