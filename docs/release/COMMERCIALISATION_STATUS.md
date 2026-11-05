# Commercialisation corrections C1–C7: status, pending protocols, owner actions

Status: 5 November 2026. Owner of acceptance: **product owner (Kevin
Busuttil)**.

**Update, 5 November 2026:** at the product owner's request, every PR below
was merged into `main` in the order in §1 (core #129–#130, hub #196–#202,
backend #2–#5). The hub now pins core `3cb2683` and backend `e950747`, the
merged commits. Merging changes no release gate: the evidence is still
container-only.

**Review follow-ups, 5 November 2026:** the automated reviewer posted 12
findings on the merged PRs. They are fixed, with tests, in one follow-up PR
per repository (backend #6, core #131, and the hub PR on the same branch),
none merged yet. The hub PR pins core and the backend to those PRs' commits.

| Finding (PR) | Fix | Test |
|---|---|---|
| Padded deposit reference not counted (backend #4) | stored and matched trimmed, server and Solo | backend `a_padded_deposit_reference_…`; hub `deposit_test` |
| Foreign-rate deposit application (backend #4) | refused on the server and in Solo | same two tests |
| Stale cached chain tip after a binary rollback (backend #3) | cached tip trusted only when the head row carries it; unlinked rows linked from the last linked row | backend `rows_appended_by_an_older_binary_…` (PostgreSQL) |
| Lost-history lookup outside the posting lock; audit row in a separate step (backend #3) | lookup, floors, record and audit row in one transaction under the company lock | backend `tests/history.rs` |
| Cursor-only divergence lost on restart (hub #199) | divergence marker may be cursor-only; still never a checkpoint | `team_history_test` |
| History anchored only after a full exchange (hub #199) | each pull page is anchored as a pending checkpoint before it is applied | `team_history_test` (interrupted paged sync) |
| Confirmed till receipt overwritten by its provisional copy (hub #199) | the server's confirmed receipt is kept | E2E `team_restore_e2e_test` 7b (fails without the fix) |
| No way to clear the books lock; picker crash on old locks (hub #200) | "Clear the lock" action (Team: server command with no date); picker range covers the lock | `team_books_lock_test` |
| Drift script masked an accounting diff (hub #201) | each comparison fails on its own | run by hand with each drift |
| Legacy AI key deleted after a failed migration (hub #197) | the key is saved only when the operator changed it | `capture_key_storage_test` |
| Reports stale after Retry owed postings (hub #197) | report providers invalidated after the retry | `report_refresh_test` |
| Storage messages promised nothing was saved (core #130) | each message asks the operator to check the record | core `storage_error_text_test` |

This page lists what the seven correction increments changed, how they must
be merged, what still has to be done on real devices and with a real
customer, and what only the product owner can do. Nothing here is accepted
yet. Every result below came from Linux containers: SQLite files and
PostgreSQL 16, over HTTP, in CI or in a development container. **None of it
is device evidence or pilot evidence.** No release gate changes state
because of this work.

## 1. What C1–C7 changed

| Inc. | What | PRs (all merged 5 Nov 2026) | Automated evidence |
|---|---|---|---|
| C1 | Solo automatic Backup Protection (R2), recovery-safe numbering after a restore (R3), streamed "Save a copy" (R8) | core #129, hub #196 | `backup_protection_test`, `numbering_recovery_test`, core `backup_restore_test`, `naming_series_policy_test` |
| C2 | AI key in the platform secure store (R4), Retry owed postings (R6), plain-language storage errors (R7), phone bank reconciliation and statements (UX-BANKREC), accessibility tests | core #130, hub #197 | `capture_key_storage_test`, `retry_owed_postings_test`, `phone_layout_test`, core `storage_error_text_test` |
| C3 | One-time move of a Solo book into a new Team company: server take-on, reconciliation, crash-safe switch | backend #2, hub #198 | backend `tests/solo_migration.rs`; hub `solo_to_team_test`, E2E `solo_to_team_e2e_test` |
| C4 | Detecting a restored Team server by its history chain; device recovery without a wipe; lost-records report | backend #3, hub #199 | backend `tests/history.rs`; hub `team_history_test`, E2E `team_restore_e2e_test` (8 scenarios) |
| C5 | Server posting of Journal Entry, Expense and Customer Deposit; one server-held books lock through an audited command | backend #4, hub #200 | backend `tests/c5_authority.rs` (11), fixtures 0013–0016 on both engines; hub E2E `team_authority_c5_e2e_test` |
| C6 | App/server protocol contract; the hub's CI runs the whole Team E2E and the contract drift check against a pinned backend commit | backend #5, hub #201 | backend `tests/protocol.rs`, `src/protocol.rs`; hub `team_protocol_test`, E2E `team_protocol_e2e_test`; CI job `team-e2e` |
| C7 | This page, tracker updates, scope review | hub (C7 PR) | — |

Totals at C6, on Linux:

- backend: 155 tests, passing on both the in-memory store and PostgreSQL;
- hub: 936 unit tests;
- 16 shared accounting fixtures, passing on both engines;
- full Team E2E.

### Merge order

The PRs are stacked, and each one is based on the branch of the one before.

1. **Core:** merge core #129, then #130.
2. **Hub C1 and C2:** re-pin the hub to the merged core commit in `pubspec.yaml` and `pubspec.lock`. Then merge hub #196 and #197.
3. **C3 to C6, in increment order:** merge backend #2 → #3 → #4 → #5, and hub #198 → #199 → #200 → #201. Retarget each PR to `main` once the PR below it has merged.
4. **Backend before hub.** For C3 to C6, the backend PR of an increment must be deployed before that increment's hub release (`TEAM_PROTOCOL_CONTRACT.md`).
5. **Re-pin after the backend merges.** After backend #5 merges, set `tool/team_backend.pin` to the merged commit and let `team-e2e` pass on `main`.

These are high-risk financial and recovery changes. None is merged
automatically.

## 2. Physical-device and real-world protocols (all PENDING)

| # | Protocol | Where it is written | Blocks | Status |
|---|---|---|---|---|
| D1 | R1 clean-install restore drill, including an interrupted restore and a restore of a backup from another device | `SOLO_RC_PACKAGE.md` §3.1 steps 1–8 | Solo RC | **PENDING** |
| D2 | R2 automatic backup to `Documents/Atlas Backups`, then a restore after reinstall using only the recovery passphrase | `SOLO_RC_PACKAGE.md` §3.1 step 9 | Solo GA (R2) | **PENDING** |
| D3 | R3 numbering after restoring an older backup, on the same device and after a reinstall | `SOLO_RC_PACKAGE.md` §3.1 steps 7 and 10 | Solo GA | **PENDING** |
| D4 | R4 AI key survives a restart and is gone from preferences; UX-BANKREC month reconciled on a phone with large text and TalkBack; statement shared from a phone | `SOLO_RC_PACKAGE.md` §3.3a | Solo GA / pilot | **PENDING** |
| D5 | Device performance run, including P-PERF-1 (backup time of a 40 MB book) | `PERFORMANCE_BASELINES.md` §4 | Solo RC | **PENDING** |
| D6 | TalkBack and large-text matrix, rows A1–A11 (A12–A15 for other platforms) | `ACCESSIBILITY_ACCEPTANCE.md` §2 | Solo RC (A11Y-ANDROID) | **PENDING** |
| D7 | Install, upgrade and uninstall facts on the signed build | `SOLO_RC_PACKAGE.md` §3.4 | Solo RC (needs REL-1) | **PENDING** |
| D8 | Observed usability sessions, 10 journeys | `USABILITY_TEST_PROTOCOL.md` | Solo GA (UX-OBSERVED) | **PENDING**, 0 of 10 |
| D9 | Solo → Team move of a real book on a phone and a desktop: kill Atlas mid-move, then resume | `team/SOLO_TO_TEAM_MIGRATION.md` | Team 1.0 | **PENDING** |
| D10 | Team device recovery on a real phone and desktop after a production-style server restore | `team/TEAM_RESTORE_RECOVERY.md` | Team 1.0 | **PENDING** |
| D11 | Team books lock across devices: lock on one phone; a second device that was offline tries a backdated post and is refused; an accountant tries to reopen and is refused | Pilot P10, `team/TEAM_1_0_SCOPE_AND_PILOT.md` §4 | Team 1.0 | **PENDING** |
| D12 | Protocol mismatch seen by a person: a current app against an older server stops with the "server needs updating" message, and nothing is lost | `team/TEAM_PROTOCOL_CONTRACT.md` | Team 1.0 | **PENDING** |
| D13 | Two-user, two-device Team acceptance with forced concurrency and intermittent connectivity | Plan §12, pilot P1–P3 | Team RC | **PENDING** |
| D14 | Solo first-customer pilot | `FIRST_CUSTOMER_PILOT.md` | Solo GA (M2) | **Not started** |
| D15 | Team pilot, P1–P10, with external evidence | `team/TEAM_1_0_SCOPE_AND_PILOT.md` §4 | Team 1.0 (M4) | **Not started** |
| D16 | Monthly restore drill on a production Team backup; external uptime check and alert shown to fire | backend `docs/OPERATIONS.md`, Team blockers 2 and 3 | Team 1.0 | **PENDING** |

Recording rules:

- Record each result where its row points: device model and OS, build, date, the person who ran it, and the result.
- Steps 9 and 10 of D2 and D3 may use a development build while REL-1 is open. Record the build type.

## 3. Actions only the product owner can take

1. **Review and merge** the stacked PRs in the order in §1. Request changes where needed.
2. **REL-1 (signing).** Create the Play developer account and the app `com.neuradix.atlas`, generate the upload key, create the GitHub `release` environment, then approve the first signed run. Engineering has not set up and will not set up signing credentials (`RELEASE_SIGNING_AND_SECRETS.md`).
3. **P-1:** confirm the legal entity.
4. **Provide reference devices and run, or witness, D1–D7.**
5. **Accept or change** the platform recommendation (Android phone only) and the performance budgets.
6. **Team RPO.** Decide on the 24-hour RPO: accept it in the service terms, or ask for WAL archiving (Team blocker 4).
7. **Recovery series (R3).** Decide whether a recovery numbering series is acceptable in each market you sell into, with advice (LEGAL).
8. **R14.** Decide when to schedule the migration that gives stock positions an unambiguous id. Today new colliding codes are refused and existing books are flagged, but the id itself is still ambiguous.
9. **G-ICON.** Provide brand assets for the icon and store listing (policy P-11).
10. **Legal documents.** Finalise the EULA, privacy notice, backup statement and support terms with a lawyer (LEGAL, P-7), and set support channel and hours (P-4).
11. **Pilots.** Choose the Solo pilot customer and the Team pilot customer, and agree terms.
12. **Team operations.** Configure production Team operations: the nightly encrypted backup, the monitor, the external uptime check and the alert channel. Set `ATLAS_MIN_CLIENT_PROTOCOL=3` once every device runs a C6 app.
13. **Commercial claims.** Decide which of these, if any, will be marketed. Each stays unclaimed until it is verified end to end (`team/TEAM_1_0_SCOPE_AND_PILOT.md` §2):
    - Team flows that still submit on the device: depreciation, payout import, year-end close, recurring invoices, channel import, construction, rental and booking;
    - partial deposit refunds;
    - foreign-currency Expense and Deposit;
    - email;
    - Stripe;
    - portals.

## 4. Scope review

I checked the full diff of the stack against `main`:

- **Hub:** 36 files under `lib/`.
- **Backend:** new modules `history`, `posting/solo_migration`, `protocol` and migrations 0012–0014.
- **Core:** the two C1/C2 PRs.

Every change maps to an item in the brief. Findings:

- **No new verticals, AI features, dashboards or integrations.** The AI change in C2 moves where the existing key is stored and adds nothing. The one new dependency is `share_plus`, used for streamed "Save a copy" (R8) and for sharing statements.
- **Signing pipeline untouched.** The stack has no changes under `android/`, `ios/`, `macos/` or `windows/`, and `release-build.yml` is unchanged. REL-1 stays open.
- **Engines preserved.**
  - The accounting, stock, VAT, pricing, lifecycle and audit engines are preserved.
  - The Solo engine changed in two places, both found by the shared fixtures and both making Solo stricter, never looser:
    - a payment applying a deposit now credits the deposit liability;
    - a deposit cannot be cancelled while it is applied.
  - C1's numbering hold is new behaviour after a restore. It never renumbers an issued document.
- **Solo stays local-first and serverless.** Every Team behaviour is a no-op without a Team session.
- **Team guards kept.**
  - The Team posting guards were kept and extended, not removed. The three newly server-posted doctypes are routed to their forms.
  - Flows that still submit on the device remain refused, and they are listed in `TEAM_1_0_SCOPE_AND_PILOT.md` §2.
  - The offline POS policy is unchanged.
- **Data and upgrade compatibility.**
  - Every migration is additive.
  - Pre-C6 apps keep working against a C6 server, because the default minimum protocol is 0.
  - A C6 app refuses an older server instead of half-working against it.
- **Not complete financial support.** These are not claimed:
  - foreign-currency Expense and Customer Deposit;
  - partial deposit refunds;
  - the device-side automated flows above.

  Each is documented with what the product does today.

## 5. Verdict

| Level | Ready? | What is missing |
|---|---|---|
| Solo RC (M1) | **No** | REL-1. D1, D5, D6 and D7 |
| Solo 1.0 (M2) | **No** | The RC, D2–D4, D8, D14, G-ICON, P-12, LEGAL |
| Team RC (M3) | **No** | D13 |
| Team 1.0 (M4) | **No** | The Team RC, D9–D12, D15, D16, the RPO decision, release pairing (Team blocker 7) |

The trackers are updated: `SOLO_RELEASE_READINESS.md`,
`team/TEAM_1_0_SCOPE_AND_PILOT.md`, and the plan's M3 status. A gate
changes only with evidence recorded as each tracker's update rules require.
