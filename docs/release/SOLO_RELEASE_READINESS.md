# Atlas Solo — release-readiness tracker (M1 and M2 gates)

Status: 22 October 2026. Branch `claude/project-thread-xlz943` (hub PR #194). Owner of acceptance: **product owner (Kevin Busuttil)**.

**Rule for this document:** a gate is **met** only when every column that applies has evidence, and the product owner has accepted it. A screen existing, or a test existing, is not enough. "Automated" means it ran in CI or `flutter test` against real SQLite files on Linux. It never means a phone. Nothing in the "Accepted" column has been accepted yet.

## 1. Verdict

| Level | Ready? | Why (details in §2–§6) |
|---|---|---|
| **Release candidate (M1)** | **No** | 1. **R1:** the restore drill has not been run on a physical device. 2. **REL-1:** there is no production upload key, so no signed build exists. 3. Nothing has been installed or exercised on real hardware: no device performance run, no TalkBack pass. 4. Two M1 gates are only partly met: critical tasks on every form factor, and accessibility. |
| **Pilot-ready (first customer)** | **No** | It needs an accepted RC first. The procedure is ready ([FIRST_CUSTOMER_PILOT.md](FIRST_CUSTOMER_PILOT.md)), and the product-owner prerequisites are listed in §5. |
| **Commercially GA (M2)** | **No** | No customer has been migrated, nor has one operated an accounting period. No usability session has been run. Four BLOCKER-SOLO-GA defects are open (R2, R3, R4, G-ICON), and the legal items are drafts. |

What **is** in place is the engineering for an RC:

- the Android app id and signing configuration are production-grade;
- the iOS and macOS projects are committed;
- the build is reproducible (lockfile);
- release builds run on four platforms in CI;
- an acceptance gate and secret and dependency scans run on every push;
- a privacy-filtered support diagnostics report is available in the app;
- a host performance baseline has been measured;
- one verified data defect (R14) is now guarded.

## 2. M1 gate — Atlas Solo RC (plan §6)

| # | Gate | Implemented | Automated evidence | Manual / device evidence | Residual risk | Responsible | Accepted |
|---|---|---|---|---|---|---|---|
| M1-1 | Solo 1.0 scope is frozen | Scope defined in plan §3.1. This increment added no feature, vertical, Team or AI work (diff of PR #194). | — | — | No recorded freeze decision. Optional modules still ship in the binary (hidden by business type). | Product owner | **No.** Record the freeze date. |
| M1-2 | Canonical commercial acceptance journey passes | Yes | `test/solo_acceptance_test.dart` runs setup → migration → purchase → sale → part and final payment → credit note → VAT, TB, P&L, BS and stock → encrypted backup → **clean-folder restore → identical books**. Steps outside that test have their own tests in the same CI gate or the main suite: expense (`expense_test`), bank statement import and reconcile (`bank_import_service_test`, `bank_matching_service_test`), AR/AP ageing and stock valuation (`financial_reports_test`, `aggregating_reports_test`), customer statement (`customer_statement_test`). | Not run by a person on a device | The journey is split across files, not one script. | Engineering | **No** |
| M1-3 | No reachable mock/demo data required for a core workflow | Dashboards use the real `DashboardEngine` (earlier increment). Setup packs are opt-in. | A grep of `lib/` for mock, fake, lorem and sample data finds only comments recording the mocks' removal. | No route-by-route walk-through | The check is a text search, not an audit of every route. | Engineering | **No** |
| M1-4 | First-run setup reaches an explicit "ready to trade" state | Yes. Setup checklist `readyToInvoice` (company, tax, fiscal year, customer, item). | `setup_checklist_test`, `test/ux/*` onboarding | Observed sessions PENDING ([USABILITY_TEST_PROTOCOL.md](USABILITY_TEST_PROTOCOL.md)) | Not seen with a real user. | Engineering / product owner | **No** |
| M1-5 | Critical tasks usable on supported phone, tablet and desktop | **Partly.** Phone bar, summary-first reports, confirmations (M1.2). | No overflow at 360–1440 px; 200 % text; tap-target, label and contrast guidelines on 15 screens (`test/accessibility`, `test/ux`) | **None.** No device has run Atlas. | **Bank reconciliation is not phone-ready** (UX-BANKREC). The ten critical forms have had no field-layout review. | Engineering | **No** |
| M1-6 | Opening-data migration produces a reconciled opening position | Yes. Setup › Move from another system (nine templates, dry run, reconcile). | `opening_take_on_test` (17), `opening_data_screen_test`, `solo_acceptance_test` | Real dataset is M2-2 | Open invoices come over as balances (R9). | Engineering | **No** |
| M1-7 | Backup → clean install → restore succeeds | Yes. Encrypted backup, staged and journalled restore, to-the-cent verification. | `solo_acceptance_test` (clean folder), Core `backup_restore_test`, `solo_fault_test` (interrupted backup and restore) | **R1: not run on any physical device.** | **BLOCKER-SOLO-RC** | Product owner (device) + engineering | **No** |
| M1-8 | Offline/adversarial matrix has no unresolved data-loss/accounting blocker | Yes. Transactional saves, posting outbox, atomic attachments, **R14 guard (this increment)**. | `solo_fault_test` (12), `posting_outbox_test`, `bin_identity_test` (6), Core `migration_safety_test` | Long offline week on a device PENDING ([PERFORMANCE_BASELINES.md](PERFORMANCE_BASELINES.md) §4.7) | R6 (UX of the retry), R7 and R8 are PILOT. | Engineering | **No** |
| M1-9 | Accessibility checks complete for critical workflows | **Partly** | 58 guideline checks pass ([ACCESSIBILITY_ACCEPTANCE.md](ACCESSIBILITY_ACCEPTANCE.md) §1). Form screens are not covered (A11Y-FORMS). | **TalkBack, VoiceOver, keyboard and large-text matrix: all PENDING** | Unknown until the manual pass | Product owner / tester | **No** |
| M1-10 | Platform support matrix is explicit | Yes. [PLATFORM_MATRIX.md](PLATFORM_MATRIX.md), four levels per platform. | `Release builds` jobs prove "buildable" | No platform is "Tested" | Recommends Android-phone-only for the pilot (decision pending). | Product owner | **No** |
| M1-11 | Release builds and upgrade/migration checks are repeatable | Yes. Committed lockfile and `--enforce-lockfile`, pinned Flutter, stamped build number, checksums, a signed-build job behind the `release` environment ([RELEASE_PROCESS.md](RELEASE_PROCESS.md)). | `Release builds` (Android/iOS/macOS/Windows) on PR #194 (§7); `migration_safety_test` (v1 → latest); `solo_fault_test › repeated restart` | **The signed job has never run (REL-1).** There is no previous signed release to upgrade from, so the first upgrade drill is at RC2. | Xcode and Windows images are not pinned. | Engineering / product owner (key) | **No** |
| M1-12 | Support diagnostics are available | Yes. Settings › Help & diagnostics, and on the start-up error screen: version/build/commit, OS, schema, integrity, postings owed, modules, backup, sync and recent errors, privacy-filtered and exportable. | `support_diagnostics_test` (10), including a populated book whose report contains no company, customer, email, amount, path or device id | Support process not yet exercised. A report must be read by support in the pilot. | Redaction is pattern-based; free-text errors could carry an unforeseen format. | Engineering / support | **No** |
| M1-13 | No known `BLOCKER-SOLO-RC` issue | — | — | — | **Open:** R1, REL-1, A11Y-ANDROID (§6) | Product owner | **No** |

## 3. M2 gate — Atlas Solo 1.0 (plan §9)

| # | Gate | Implemented | Automated evidence | Manual / customer evidence | Residual risk | Responsible | Accepted |
|---|---|---|---|---|---|---|---|
| M2-1 | Real customer migrated without manual DB edits | Tooling yes (M1-6) | Fixture only | **None. No pilot has taken place.** | Customer data formats unknown | Product owner + pilot customer | No |
| M2-2 | Opening TB/AR/AP/stock/bank reconciled | Reconciliation screen | Fixture only | **None** | — | Accountant of pilot customer | No |
| M2-3 | Representative operating period completed | — | — | **None** | — | Pilot customer | No |
| M2-4 | No unexplained accounting differences remain | Reconciliation and difference reporting | Stock ↔ GL and TB tests | **None** | — | Product owner | No |
| M2-5 | Backup and clean restore completed with customer-representative data | Yes | Fixture of 18,028 documents, 38 MB backup restored (host perf run) | **None on a device** (R1, P-PERF-1) | Backup speed on low-end phones unmeasured | Product owner | No |
| M2-6 | Installation/update proven outside a development checkout | Pipeline and guides 1 and 7 | CI artifacts | **None.** No signed build has been installed. | — | Product owner | No |
| M2-7 | Critical UX tasks need no developer coaching | Protocol ready | — | **0 of 10 journeys observed** | J6 expected to fail on phone | Product owner / facilitator | No |
| M2-8 | Support and diagnostics process is operational | Diagnostics, severity policy draft | `support_diagnostics_test` | Not exercised | Support channel and hours not set (policy P-4) | Product owner | No |
| M2-9 | Essential user/admin documentation exists | **Drafts:** [docs/solo/](../solo/README.md) guides 1–8 | — | Not read by a customer | Drafts may not match a non-technical reader | Product owner | No |
| M2-10 | No known critical data-loss, posting or recovery defect | Outbox, journalled restore, R14 guard | §2 M1-7 and M1-8 | — | R2 and R3 are BLOCKER-SOLO-GA | Engineering | No |
| M2-11 | No known `BLOCKER-SOLO-GA` issue | — | — | — | **Open:** R2, R3, R4, G-ICON, UX-OBSERVED, LEGAL (§6) | Product owner | No |

## 4. Solo 1.0 scope inventory (plan §3.1)

Each core scope item mapped to its strongest automated evidence. ✅ means a test exercises it against the real engine. Nothing here is device-tested.

| Scope item | Evidence |
|---|---|
| Company/setup | ✅ `hub_seeder_test`, `setup_checklist_test`, `coa_repair_test` |
| Customers, suppliers, items/services | ✅ `solo_acceptance_test`, `opening_take_on_test`, `bin_identity_test` (codes) |
| Quotations, sales orders, sales invoices | ✅ `solo_acceptance_test`, `quotation_status_test`, `hub_document_conversion_test`, `invoice_status_service_test` |
| Credit notes / returns | ✅ `solo_acceptance_test`, `ledger_returns_stock_test` |
| Purchase orders, receipts, purchase invoices | ✅ `solo_acceptance_test`, `stock_cogs_acceptance_test`, `duplicate_supplier_bill_test` |
| Payments, expenses | ✅ `solo_acceptance_test`, `guided_payment_test`, `expense_test` |
| Banking / reconciliation | ✅ `bank_statement_csv_importer_test`, `bank_matching_service_test`, `bank_matcher_test`. Phone UX ⛔ (UX-BANKREC) |
| Stock, COGS | ✅ `stock_cogs_acceptance_test`, `stock_costing_test`, `ledger_valuation_test`, `stock_count_test`, `bin_identity_test` |
| VAT/tax | ✅ `hub_tax_engine_test`, `tax_inclusive_test`, `tax_return_builder_test` |
| GL / AR / AP | ✅ `ledger_derivation_test`, `journal_balance_guard_test`, `posting_outbox_test` |
| P&L, Balance Sheet, Cash Flow, ageing, stock valuation, gross margin | ✅ `financial_reports_test`, `aggregating_reports_test`, `hub_reports_test` |
| Customer statements, payment reminders | ✅ `customer_statement_test`, `payment_reminder_test` |
| Attachments | ✅ Core attachment tests, `solo_fault_test › attachment interruption`, backup restore of attachments |
| Import/export | ✅ `opening_take_on_test`, `accountant_export_test` |
| Opening data / migration | ✅ M1-6 |
| Backup/restore | ✅ M1-7 (device ⛔ R1) |
| Offline operation | ✅ All of the above run with no network. Long offline session on a device PENDING. |

## 5. Release-candidate and pilot prerequisites owned by the product owner

These cannot be done by engineering in this repository, and none has been done.

1. **P-1:** confirm the legal entity. It is needed for the Google Play developer account and the pilot agreement.
2. **REL-1:** create the Play developer account and the app `com.neuradix.atlas` (Play App Signing), generate the upload key, and create the GitHub `release` environment with its secrets ([RELEASE_SIGNING_AND_SECRETS.md](RELEASE_SIGNING_AND_SECRETS.md)).
3. Approve the first signed run of **Release builds** (tick **signed**).
4. Provide the reference devices: a low/mid Android phone, plus an Android tablet if offered.
5. Run or witness **R1**, the device performance run and the TalkBack pass ([SOLO_RC_PACKAGE.md](SOLO_RC_PACKAGE.md) §3).
6. Accept or change the platform recommendation (Android phone only) and the proposed performance budgets.
7. Choose the pilot customer (plan M2.1) and agree terms (drafts in [policies/](policies/COMMERCIAL_POLICY_CHECKLIST.md)).

## 6. Residual issue register

Classes:

- `BLOCKER-SOLO-RC`: no release candidate until fixed.
- `BLOCKER-SOLO-GA`: no Solo 1.0 until fixed.
- `PILOT`: fix or work around during the pilot.
- `POST-GA`: later.

Issues R1–R13 come from [SOLO_ACCEPTANCE_MATRIX.md](../SOLO_ACCEPTANCE_MATRIX.md).

| Id | Issue | Class | Status / next step | Owner |
|---|---|---|---|---|
| **R1** | Physical-device clean-install restore drill not run | **BLOCKER-SOLO-RC** | Open. Drill in [SOLO_RC_PACKAGE.md](SOLO_RC_PACKAGE.md) §3. | Product owner + engineering |
| **REL-1** | No production upload key or signed build. Release signing is configured but has never run with a real key. | **BLOCKER-SOLO-RC** | Open. §5 steps 1–3. | Product owner |
| **A11Y-ANDROID** | No screen-reader (TalkBack) or large-text pass on the pilot platform | **BLOCKER-SOLO-RC** | Open. Matrix rows A1–A11, Android column. | Tester |
| R2 | No scheduled or automatic backup | BLOCKER-SOLO-GA | Open | Engineering |
| R3 | Restoring an older backup resets numbering, so numbers can be issued twice | BLOCKER-SOLO-GA | Open. Guide 6 tells the user to reset numbering. | Engineering |
| R4 | AI capture key stored in plaintext preferences | BLOCKER-SOLO-GA | Open | Engineering |
| **G-ICON** | App ships the Flutter default icon. Branding is needed before any store listing. | BLOCKER-SOLO-GA | Open. Needs brand assets (policy P-11). | Product owner |
| **UX-OBSERVED** | No observed usability sessions (plan M2.4) | BLOCKER-SOLO-GA | Protocol ready | Product owner |
| **LEGAL** | EULA, privacy notice, backup statement and support terms are drafts. P-1 and P-7 are open. | BLOCKER-SOLO-GA | Drafts in `policies/` | Product owner + lawyer |
| R5 | No app-level encryption at rest. Relies on the device lock. | PILOT | Guide 1 requires a screen lock | — |
| R6 | Retry of owed postings needs a restart | PILOT | Open | Engineering |
| R7 | Low-storage errors show SQLite text | PILOT | Open | Engineering |
| R8 | Mobile "Save a copy" reads the whole backup into memory | PILOT | Open | Engineering |
| **R14** | Item or warehouse codes containing `-` could make two stock positions share one Bin (`BIN-<item>-<warehouse>`). The stock valuation then silently disagrees with the Stock GL. | PILOT → **guarded** | **Verified and guarded in this increment.** New colliding codes are refused (`BinIdentityGuardInterceptor`, `bin_identity_test`). Existing books are checked by the diagnostics report ("stock positions sharing one balance record"). An unambiguous id needs a Team-backend migration: POST-GA. | Engineering |
| **P-PERF-1** | Backup about 2.5 MB/s on host, so possibly ≥ 1 min on a low-end phone | PILOT | Measure on device before the pilot. The fix is `cryptography_flutter` (R10). | Engineering |
| **A11Y-FORMS** | Form and list screens are not covered by automated accessibility checks | PILOT | Manual pass, or device integration tests | Engineering |
| **UX-BANKREC** | Bank reconciliation not designed for phones | PILOT | Use a tablet or desktop meanwhile (guide 4) | Engineering |
| **R-iOS-BACKUP** | iCloud device backup includes the books and the device id | PILOT (only if iOS is offered) | Decide whether to exclude | Product owner |
| **SIGN-APPLE / SIGN-WIN** | No Apple or Windows signing, notarisation or installer | BLOCKER for offering those platforms; not for an Android-only RC | Procedures in the signing doc | Product owner |
| **P-12** | No third-party licences page | BLOCKER-SOLO-GA | One-line addition under About | Engineering |
| R9 | Opening invoices come over as balances | POST-GA | — | — |
| R10 | Pure-Dart AES | POST-GA (PILOT if P-PERF-1 fails its budget) | — | — |
| **PERF-REPORTS** | Reports fold whole doctypes in memory | POST-GA | SQL aggregation if a pilot is ~20× the fixture | — |
| R11 | Restore blocked while Team-connected | By design | — | — |
| R12 | Owner dashboard golden failed on `main` | Resolved | `test/marketing` passes in the CI acceptance gate (run 39866746810), and the committed failure images were removed | — |
| R13 | Core leakage-check hits on base | Out of scope | — | — |

## 7. Evidence log

| Date | What | Where | Result |
|---|---|---|---|
| 2026-10-22 | Host performance baseline | [perf/host_baseline_2026-10-22_linux_4cpu.json](perf/host_baseline_2026-10-22_linux_4cpu.json) | Measured ([PERFORMANCE_BASELINES.md](PERFORMANCE_BASELINES.md) §3) |
| 2026-10-22 | Full hub suite (local, Linux) | `flutter test` | See PR #194 description |
| 2026-10-22 | CI on commit `1a3ab3c`: analyze, test, Solo acceptance gate (including accessibility, golden and host perf), secret and dependency scan | [run 39866746810](https://github.com/KevinBusuttil/mercantis.hub.flutter/actions/runs/39866746810) | All green |
| 2026-10-22 | Release builds on commit `1a3ab3c`: Android unsigned AAB, iOS no-codesign, macOS ad-hoc, Windows unsigned | [run 39866746736](https://github.com/KevinBusuttil/mercantis.hub.flutter/actions/runs/39866746736) | All four green. Signed job skipped, as designed (REL-1). |
| — | Device drills (R1, performance, TalkBack) | — | **PENDING** |
| — | Signed Android build | — | **PENDING (REL-1)** |
| — | Pilot | — | **Not started. No customer has used Atlas.** |

## 8. How to update this tracker

- Change a cell only with evidence: a CI run URL, a committed results file, or a dated device or pilot record with the name of the person who did it.
- The product owner fills **Accepted** with name and date.
- Re-issue §1's verdict whenever a gate changes.
