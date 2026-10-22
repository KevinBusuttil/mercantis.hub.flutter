# Atlas Solo — Data-safety acceptance matrix and release-gate classification

Status: 22 October 2026. This covers the Solo data-safety increment (M1.3, M1.4 and M1.5 Solo scope).

Repositories and branches:

- `mercantis.core.flutter` and `mercantis.hub.flutter`, both on branch `claude/project-thread-499s2h`.
- Hub pins Core to the commit of the Core PR.

Every row names the test that proves it. "Automated" means it runs in `flutter test` on Linux through `sqflite_common_ffi` against real SQLite files. It does not mean a physical phone.

## How to run

```bash
# Core
cd mercantis.core.flutter/packages/mercantis_core && flutter test
# Hub (with Core pinned in pubspec.yaml, or a local pubspec_overrides.yaml)
cd mercantis.hub.flutter && flutter test
```

Results at hand-off:

| Suite | Result |
|---|---|
| Core `mercantis_core` | **306 passed**, 0 failed |
| Core `mercantis_core_ui` | **248 passed**, 0 failed |
| Hub | **741 passed**, 19 skipped, **1 failed**. The failure is `test/marketing/atlas_owner_dashboard_golden_test.dart`, which fails identically on `main` before this work: a font-rendering golden, unrelated. |
| Hub new or changed files only | **43 passed**: posting_outbox 6, opening_take_on 17, opening_data_screen 2, solo_acceptance 1, solo_fault 12, ledger_values 5 |
| `flutter analyze` (hub) | No issues |

## Section E — fault injection

The invariant checked after every scenario:

- The GL is balanced.
- Every submitted posting document has GL rows.
- The posting outbox owes nothing.
- Stock ledger quantity equals the Bin quantity.
- Stock ledger value equals the Stock account and the Bin value.

| # | Scenario | Mechanism | Outcome proved | Test |
|---|---|---|---|---|
| E1 | Offline creation | All Solo work is local. There is no server. | Documents save, submit and post with no network. Every change is queued for sync. | hub `solo_fault_test › long-term offline`, `solo_acceptance_test` |
| E2 | Process killed during save | SIGKILL of a child Dart process in a save loop | No partial document: every document has all its child rows | core `crash_safety_test › killing the process mid-write…` |
| E2b | Process killed after submit, before postings | Ledger not started, then restart | Recovery posts exactly once | hub `posting_outbox_test › app killed after submit…` |
| E3 | DB write failure | TEMP trigger `RAISE(ABORT)` on documents, sync queue or audit log | Save and submit are all-or-nothing. The previous version stays whole. The invoice stays a draft with no GL. A partial posting is repaired without duplicates. | core `crash_safety_test` (5 tests); hub `solo_fault_test › database write failure…`, `posting_outbox_test › a write failure part-way…` |
| E4 | Low storage | `PRAGMA max_page_count` (SQLITE_FULL) | The store refuses rather than truncates. `quick_check` passes. After restart the books are consistent. A posting interrupted by a full disk completes once space returns. | core `crash_safety_test › disk full…`; hub `solo_fault_test › low storage while trading…`, `posting_outbox_test › disk full during posting…` |
| E5 | Repeated restart | 6 close-and-reopen cycles with trading in between | Each boot (migrations, metadata sync, posting recovery) leaves the BusinessSummary identical. Nothing is re-posted. | hub `solo_fault_test › repeated restart` |
| E6 | Attachment interruption | A write failure, and leftover `.partial` files | No file under the real name. Partials are swept at start. A backup reports a missing or damaged attachment rather than dropping it. | core `crash_safety_test › attachment store` (2), `backup_restore_test › a missing attachment is reported…` |
| E7 | Interrupted backup | A fault at each backup stage; SIGKILL at each stage; disk full | No backup file appears. An older backup survives. The live books are untouched. | core `backup_restore_test › process killed during backup` (per stage); hub `solo_fault_test › disk full while writing a backup` |
| E8 | Interrupted restore | SIGKILL at each `RestoreStep` (core). An exception at each step, then startup recovery (hub). | Before commit, the previous books come back exactly. At commit, the restored books stand. Never a mix. | core `backup_restore_test › process killed during restore` (5); hub `solo_fault_test › restore failing at <step>` (5) |
| E8b | Restore that does not reproduce its totals | A GL row deleted from the staged DB | Refused with `RestoreVerificationException`. Live books unchanged. | hub `solo_fault_test › a backup whose books do not reproduce…`; core `› a host verification failure rolls the restore back` |
| E9 | Upgrade across DB versions | Build a v1 database, open with the current build | Upgraded to v8 with data intact. A half-applied step heals. A newer DB is refused untouched. | core `migration_safety_test` (4) |
| E10 | Migration rerun | Same take-on files imported twice; an interrupted import | The second run creates and posts nothing. An interrupted run's drafts are posted once. | hub `opening_take_on_test › re-importing…`, `› an interrupted import resumes…` |
| E11 | Repeated mutation / retry | The same draft and a refetched copy submitted again | The second submit is refused. GL rows and stock unchanged. | hub `solo_fault_test › repeated submit…`; core `crash_safety_test › submit is all-or-nothing…` |
| E12 | Long-term offline operation | 9 months of purchases and sales with no sync | Consistent books. Every change waits in the outbound queue. | hub `solo_fault_test › long-term offline` |
| E13 | Restore followed by normal use | A payment on the restored device | Posts, settles and numbers normally | hub `solo_acceptance_test`; core `backup_restore_test › … clean installation is identical` |

Solo keeps **local posting authority**. No change was made to Atlas Team's server-authoritative posting.

## Section F — financial acceptance fixture

`test/solo_acceptance_test.dart` runs one continuous journey on a production-shaped book (Hub manifest, all production interceptors, posting outbox, ledger service):

| Step | Asserted |
|---|---|
| Company setup | Seeded chart, VAT 18 %, financial year |
| Opening-data migration | Dry run clean. Import with no errors. Opening reconciliation agrees in every area. |
| Purchase order → receipt → supplier invoice → supplier payment | Receipt adds 10 to stock (40 → 50). Bill 60 + VAT 10.80 = 70.80. Payment settles it to 0. |
| Quotation → sales order → sales invoice (update stock) | 5 × 12 + 60 service, VAT 21.60, grand 141.60. COGS at moving average 5.20. |
| Signed invoice attached | 300 kB PDF stored with SHA-256 |
| Part payment, then final payment | Outstanding 41.60 exactly, then 0 |
| Return / credit note (1 unit) | −14.16. Stock back at cost 5.20. COGS reversed. |
| GL, account by account | Bank 12 570.80 · Debtors 575.84 · Creditors −236.00 · Stock 239.20 · GRNI 0 · VAT −418.64 · Sales −108.00 · COGS 20.80 · Retained Earnings −12 644.00 · Opening Balance Equity 0. TB difference 0. |
| Stock valuation | 46 units, 239.20, equal to the Stock account |
| VAT | Output 19.44 (21.60 − 2.16), input 10.80 |
| P&L | Net profit 87.20 |
| Backup | Encrypted. Neither the passphrase nor any company name appears in the file. |
| Clean restore (new empty data folder, different device id) | Wrong passphrase refused. **Every table** (except the app's own manifest tables, rewritten from the build on each start) identical row for row. BusinessSummary identical. TB, P&L, BS, stock valuation, stock↔GL reconciliation, AR and AP ageing identical. Attachment bytes identical and checksum-verified. No owed postings. The opening reconciliation still agrees. |
| Normal use after restore | Opening receivable settled. Bank 13 160.80. TB difference 0. |

## Sections C and D — opening data and reconciliation

The details are in [SOLO_OPENING_DATA_MIGRATION_GUIDE.md](SOLO_OPENING_DATA_MIGRATION_GUIDE.md). `test/opening_take_on_test.dart` covers:

- the templates round-trip and the dry run writes nothing;
- an exact import;
- re-import idempotency and resume;
- row-level rejection with reasons (duplicates, bad numbers, unknown references, dates);
- all-or-nothing posting sections;
- an unbalanced TB refused (0.01);
- control totals that must match;
- conflicts never overwritten;
- opening stock into an occupied position refused;
- money parsing;
- the financial year guard;
- reconciliation: clean, unaffected by later trading, differences reported and not absorbed, and rejected rows appearing as differences.

## Disaster-recovery claim

A clean-installation restore **has been executed and verified** in the automated suite: an empty data folder, the production schema and interceptors, and an identical-results check. It **has not** been executed on a physical Android or iOS device after an uninstall and reinstall. Until that drill is run and recorded below, disaster recovery on mobile is not claimed as proven.

| Drill | Platform | Date | Result | By |
|---|---|---|---|---|
| Automated clean-folder restore | Linux, sqflite_common_ffi | 2026-10-22 | Pass (`solo_acceptance_test`) | CI-style run |
| Physical device: uninstall → reinstall → restore from cloud file | Android | — | **not yet run** | — |
| Physical device: uninstall → reinstall → restore from cloud file | iOS | — | **not yet run** | — |
| Desktop: new user profile → restore | macOS / Windows | — | **not yet run** | — |

## Residual issues

| # | Issue | Class | Why / next step |
|---|---|---|---|
| R1 | Physical-device clean-install restore drill not executed (Android, iOS, desktop) | **BLOCKER-SOLO-RC** | M1.4 exit criterion. Run the drill from the backup doc §5 and record it in the table above. |
| R2 | No scheduled or automatic backup. The user must press **Back up now**. The screen flags a backup older than 7 days. | **BLOCKER-SOLO-GA** | A paying customer who forgets loses everything since the last backup. Add a reminder and a scheduled backup to a user-chosen folder. |
| R3 | Restoring an older backup resets document-number counters. Numbers issued after that backup can be issued again. The confirm dialog warns. | **BLOCKER-SOLO-GA** | Legally significant for invoices. Record the last-issued numbers outside the DB, or ask the user for the last number on restore. |
| R4 | The AI capture API key is stored in SharedPreferences in plaintext | **BLOCKER-SOLO-GA** | Move it to flutter_secure_storage. It is already excluded from backups. |
| R5 | The DB and attachments are not encrypted by Atlas at rest. Protection relies on a device PIN (Android FBE / iOS Data Protection) or desktop full-disk encryption. | **PILOT** (guidance) | The installation guide must require a device PIN or FileVault/BitLocker. App-level encryption (SQLCipher) is POST-GA and needs a tested key-custody and migration design. It was not attempted here, to avoid untested cryptography. |
| R6 | After a stock voucher's posting fails, later stock movements would be costed without it. **Mitigated:** stock-moving submits and cancels are refused while an earlier stock posting has failed, with a message to restart Atlas, which retries it (`posting_outbox_test › stock documents wait…`). | **PILOT** | The block is a UX cost: the user must restart to retry. A "Retry owed postings" button and friendlier copy are PILOT. |
| R7 | Low-storage errors show SQLite's message text | PILOT | Map SQLITE_FULL to plain language |
| R8 | Mobile "Save a copy" reads the whole backup into memory | PILOT | Stream it. Large backups should use desktop or USB meanwhile. |
| R9 | Opening migration brings open invoices over as balances, not as open sales or purchase documents (plan M1.3 item 11) | POST-GA | Balances reconcile and can be paid against |
| R10 | Pure-Dart AES-GCM, about 8 MB/s | POST-GA | `cryptography_flutter` uses platform AES as a drop-in |
| R11 | Restore is blocked while Team-connected. Folder sync is cleared on restore. | By design | Team books are restored server-side (M3.8) |
| R12 | `test/marketing/atlas_owner_dashboard_golden_test.dart` fails on `main` too | Out of scope | Unrelated golden |
| R13 | Core `tool/check_no_hub_leakage.sh` reports pre-existing hits on the base branch. This work adds none. | Out of scope | — |
| R14 | Bin ids are `BIN-<item>-<warehouse>` (pre-existing), so codes containing `-` can collide (item `A-B` in `C` and item `A` in `B-C`). One Bin then overwrites the other. **Verified (22 Oct 2026):** the stock valuation report then disagrees with the Stock GL with no warning (`bin_identity_test`). | **PILOT → guarded** | `BinIdentityGuardInterceptor` refuses a new item or warehouse code that would collide, naming both positions. The diagnostics report flags any existing collision. The id format is shared with the Team backend, so changing it is POST-GA with a migration. |

## Release-candidate increment (22 Oct 2026)

Gate-by-gate status, new residual issues (REL-1, A11Y-ANDROID, G-ICON, P-PERF-1, A11Y-FORMS, UX-BANKREC and others) and the RC verdict are in [release/SOLO_RELEASE_READINESS.md](release/SOLO_RELEASE_READINESS.md). This matrix keeps the data-safety evidence.

## Next incomplete commercial-release gate

**M1 gate, "Backup → clean install → restore succeeds"**, on a physical device (R1). After that, the remaining M1 gates are:

- M1.1 acceptance inventory;
- M1.2 accessibility and observed sessions;
- M1.6 platform matrix, release builds and support diagnostics.
