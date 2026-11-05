# Atlas Team 1.0 — scope freeze and pilot plan

Status: frozen 23 October 2026. Changes to this scope need a written
decision from Kevin. A capability is **in scope** only if it has passed end
to end against the real backend. Everything else is **not advertised**:
it is hidden, or it is labelled as not available in Team.

Solo is not affected by anything here. It stays local-first and complete on
its own.

## 1. In scope (verified)

| Capability | Evidence |
|---|---|
| Create a Team company, invite members, assign roles (owner, admin, accountant, sales, purchasing, stock, pos, advisor), revoke members and devices | Backend `tests/api.rs`, `tests/tenant_isolation.rs`. Hub E2E: invitation join, till revocation |
| Device bootstrap: a new device pulls the whole company | Hub E2E: two devices join and match the owner's chart |
| Masters and drafts sync with conflict detection (never silent last-write-wins) | `test/team_two_device_conflict_test.dart`, hub E2E master data |
| Server-posted Sales Invoice, Purchase Invoice, Purchase Receipt, Delivery Note, Payment Entry, Stock Entry, including returns, VAT rows, UOM conversion, service items, FIFO and Moving Average, multi-currency base stamping | Backend posting suites, 12 shared fixtures on both engines, hub E2E |
| Server-posted Journal Entry (party lines, cost centre, multi-currency), Expense (paid or owed, input VAT) and Customer Deposit (receipt, partial application through a Receive payment, refund by cancelling, no double application, no cancel while applied), from their forms | Backend `tests/c5_authority.rs`, fixtures 0013–0016 on both engines, hub E2E `team_authority_c5_e2e_test.dart`. See `TEAM_POSTING_AUTHORITY.md` |
| One authoritative period lock: set on the server by an authorised command, refused from a stale view, re-checked inside every posting commit, copied to every device on sync, not editable on a device | Backend `tests/c5_authority.rs`, fixtures 0006 and 0016, hub E2E `team_authority_c5_e2e_test.dart` |
| Gap-free official numbering under concurrency, idempotent retry | Backend `tests/posting.rs`. Hub E2E: two devices post at once, lost-response retry |
| Server-side immutability; corrections by cancel/reversal only | Backend `tests/authority_guard.rs`, `tests/posting.rs` |
| Offline POS under a per-till series, confirmed by the server, convergent stock | Backend `tests/authority_guard.rs`. Hub E2E: offline till |
| Tenant isolation (Company A cannot read or change Company B) | Backend `tests/tenant_isolation.rs` (all 25 company routes). Hub E2E cross-company probes |
| One-time move of a Solo book into a new Team company (server take-on, reconciliation, crash-safe switch). Device run PENDING | Backend `tests/solo_migration.rs`. Hub `test/solo_to_team_test.dart`, hub E2E `solo_to_team_e2e_test.dart`. See `SOLO_TO_TEAM_MIGRATION.md` |
| Backup, encrypted off-site copy, restore drill into a clean isolated cluster, client resync after restore | Backend `scripts/restore_drill.sh`, CI `restore-drill` job, `docs/evidence/restore-drill-2026-10-23-local.md`. Hub E2E: cursor ahead of the server's head triggers a full re-pull. C4: a changed server history is detected by hash chain even after the log grows past the device; devices recover without a wipe. `docs/team/TEAM_RESTORE_RECOVERY.md`, 8 restore scenarios on PostgreSQL. Device run PENDING |
| Health and readiness, structured logs with request ids, backup-age monitor | Backend `/ready`, `scripts/monitor.sh`, `docs/OPERATIONS.md` |

## 2. Not in Team 1.0 (not advertised until verified end to end)

| Capability | Why not | What the product does now |
|---|---|---|
| Flows that create and submit Journal Entries, Expenses or Customer Deposits automatically: depreciation runs, payout import, year-end close, booking/rental/lease deposits | They submit on the device. They are not yet routed to the server | The generated document is refused at submit with an explanation. The user submits it from its form while connected |
| Partial refund of a Customer Deposit | Neither engine models it (a refund is a cancellation of the whole unapplied deposit) | Cancel the applications, cancel the deposit, take a new deposit for the part kept |
| Expense or Customer Deposit in a foreign currency | Solo posts them unconverted, so Team refuses a rate other than 1 rather than post a different figure | Record it as a Purchase Invoice or a Journal Entry, which are base-stamped |
| Recurring invoices, channel (commerce) import, construction valuations, rental/booking invoicing, work-order completion | These flows submit on the device. They are not yet routed to the server | The generated documents are refused at submit. The user submits them from the form while connected |
| POS session close and cash-up confirmed by the server | No backend endpoint | Cash-up stays local to the till |
| Malta fiscal receipts | MTCA approval and EXO number pending | Must not be claimed |
| Transactional email (invoices, statements, reminders) | No backend sending or delivery tracking | Not offered in Team |
| Stripe card payments | The webhook posts the Payment Entry, but provider clearing, fees and payouts are not modelled, and no live end-to-end run against Stripe has been done | Do not market pay links until M4.2 reconciliation exists and a live test is recorded |
| Customer and accountant portals | Backend-tested only. No hub end-to-end run, no security review of the public token routes beyond the tests | Not advertised. Enable per customer only with a recorded check |
| Commerce integrations (channels) | See above | Not advertised |
| Point-in-time recovery (RPO under 24 h) | No WAL archiving | RPO 24 h, which must be stated in the service terms |

## 3. Release blockers for Team 1.0

1. Real pilot (section 4) completed with external evidence.
2. Monthly restore drill on the production backup, filed (`docs/OPERATIONS.md`).
3. External uptime and alerting actually configured and shown to fire once.
4. A decision on the 24 h RPO: accept it in the terms, or add WAL archiving.
5. Server posting for Journal Entry, Expense and Customer Deposit.
   *Implemented in C5 (backend and hub, tested on PostgreSQL and end to
   end). Open until the pilot has posted each of them (P9).*
6. The period lock has one source of truth. *Implemented in C5: the server
   holds it, it moves only through `commands/set-books-lock`, and devices
   copy it. Open until the pilot month-end has closed a period with it
   (P7).*

## 4. Pilot plan (M4.6)

**Participant.** One real business, with at least an owner or accountant,
one sales or purchasing user, and one stock or till user. At least two
devices are active at the same time, and stock is in scope.

**Duration.** Four weeks of live use, including one month-end.

**Setup (week 0).**
- Migrate the customer's opening data in Solo and reconcile it. Then use
  Team › **Move these books to Atlas Team…** (`SOLO_TO_TEAM_MIGRATION.md`).
  A Solo book with issued documents cannot connect directly. Record the
  completion notice and keep the safety backup.
- Create members with their real roles, register their devices, and set a
  till series for every register.
- Configure the nightly encrypted backup, the monitor and the external
  uptime check. Run `restore_drill.sh` on the first production backup and
  file the report.

**Forced scenarios.** Each is done deliberately at least once, and recorded
with date, users, devices and outcome.

| # | Scenario | Pass condition |
|---|---|---|
| P1 | Two users edit the same customer at once | A conflict is raised and resolved, with no silent overwrite |
| P2 | Two users invoice the last units of one item at the same moment | One is posted and the other refused for stock. Numbers stay gap-free |
| P3 | A till works offline for at least an hour, then reconnects | Every sale is confirmed under its receipt number and every device's stock matches |
| P4 | A device is lost or replaced | Revoke it, register the new one, and the full pull matches |
| P5 | A user leaves | Removal takes effect on the next request, and that user's device can no longer sync |
| P6 | A server restore to a clean host | Restore from the off-site backup. Devices detect it and recover (Team › Recover this device). File the lost-records report with the incident log |
| P7 | Month-end | Trial balance, VAT and stock valuation on two devices equal the server's, and match the accountant's own check |
| P8 | Monitoring | A forced backend stop and a stale backup each raise an alert |
| P9 | Journals, expenses and deposits | An accountant posts a journal, a purchasing user an expense, a sales user takes a deposit that is later applied to an invoice. Every device shows the same ledger, and a second application beyond the deposit is refused |
| P10 | Period close | The accountant locks the month on one device. A device that was offline then tries to post into it and is refused. Reopening needs the owner or an admin, and the audit log shows who did what |

**Evidence.** A dated pilot log, kept by the pilot owner, with:
- screenshots or exports for P1 to P10;
- the restore-drill reports;
- the alert notifications;
- the month-end comparison;
- the customer's written confirmation.

The pilot is complete only when this log exists and the customer has signed
off. No test in this repository counts as pilot evidence.

**Exit.** Team 1.0 GA when the M4 release gate in
`docs/COMMERCIALISATION_IMPLEMENTATION_PLAN.md` §15 is met, and every item
in section 3 is closed or explicitly accepted by Kevin.
