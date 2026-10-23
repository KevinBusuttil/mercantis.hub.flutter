# Atlas Team — posting-authority matrix

Status: October 2026. Applies to Atlas Team only. Solo stays local-first:
no Team session means none of the rules below are active (the guard and the
Team naming are inert).

**Invariant.** No transaction may produce official accounting on one Team
device alone. Official GL, stock ledger, bins, settlements and party/tax
subledgers exist in a Team company only when the Team server committed them.
The one deliberate exception is the till (POS). It posts locally at once so
checkout never needs the network, and the server confirms each sale
afterwards (see *POS offline policy*).

Three layers enforce this. Each layer holds on its own even if another is
bypassed:

| Layer | Where | What it does |
|---|---|---|
| Server sync plane | backend `src/authority.rs` | `sync/push` refuses (422, whole batch) client-authored ledger rows (`GL Entry`, `Stock Ledger Entry`, `Bin`, `Settlement`, `Customer/Supplier/Tax Transaction`, `Posting Batch`), any submit/cancel or `docstatus ≥ 1` on the server-authority doctypes, and spoofed system provenance (`atlas-backend` / `atlas-payments` / `atlas-portal` device ids, `postmut-` / `portal-` mutation ids). |
| Engine guard | hub `lib/team/team_posting_guard.dart` | `DocumentEngine.submit` and `cancel` refuse every ledger-posting doctype while connected, whatever screen or service calls them, with a message saying what to do instead. POS is allowed under a till series, but cannot be cancelled. |
| Sync runner | hub `lib/team/team_sync_runner.dart` | Locally derived ledger rows never leave the device: their queue entries are dropped and the rows yield to the server's on pull. Offline till sales are confirmed through the command plane. |

Official numbers come only from the server's gap-free `numbering_series`, in
the same transaction as the postings. Draft ids are device-scoped in Team
(`SINV-.2026.-3FA2C1-0001`, `lib/team/team_naming.dart`), so two devices
never create the same draft.

## Matrix

"Server" means `POST /companies/{id}/commands/submit-document` or
`cancel-document`. It runs as one PostgreSQL transaction under a per-company
advisory lock: validation, numbering, derivation, ledger writes, idempotency
record and audit all commit or roll back together. The server recomputes
totals, tax and allocations from the lines, and client totals are never
trusted. The postings replicate to every device as system mutations.

| Transaction | Authoritative engine (Team) | Offline creation | Offline posting | Official number | GL / stock derivation | Backend accepts / rejects | Reversal | Concurrency |
|---|---|---|---|---|---|---|---|---|
| Sales Invoice (incl. credit note `is_return`) | Server | Draft, syncs | No, refused by guard | Server `SINV-#####` | Server: AR, income, VAT (tax rows sent in the command), COGS/stock when `update_stock` | Rejects on validation, role, period lock, negative stock (when `update_stock`), foreign tenant | Server cancel: reversal rows | Advisory lock, SLE expectations (stale → retry), gap-free numbering. Concurrent sales on two devices proven E2E |
| Purchase Invoice (incl. debit note) | Server | Draft | No | Server `PINV-#####` | Server: AP, expense/GRNI split per item type, VAT, stock when `update_stock`, UOM conversion | As above | Server cancel | As above |
| Purchase Receipt | Server | Draft | No | Server | Server: stock + GRNI | As above | Server cancel | As above |
| Delivery Note | Server | Draft | No | Server | Server: stock + COGS | Rejects when stock is short | Server cancel | As above |
| Payment Entry | Server (form and guided payment) | Draft | No | Server `PAY-#####` | Server: bank/cash vs party, settlements against references | Rejects allocation above the paid amount or the outstanding, references to unknown or unposted invoices | Server cancel | As above |
| Stock Entry (receipt, issue, transfer, manufacture) | Server | Draft | No | Server | Server: SLE/bins, valuation (Moving Average/FIFO), production cost roll-up | Rejects negative stock | Server cancel | As above |
| POS Invoice (till) | Till, confirmed by server | Yes | **Yes, under the till's series** | The till receipt id (`POS-.TILL1.-0001`) becomes the official number when the server confirms it | Till derives provisional rows. The server re-derives the official rows with the same ids and they replace the till's | Confirmation rejects: no `till_series`, a series bound to another device, a receipt number already used, wrong role. **Never rejected for stock**: shortfalls are recorded and reported | Return sale from the till. Local cancel is refused | Till series bound to one device. Per-till numbering means no cross-till collision. Idempotent confirmation |
| Journal Entry (manual, depreciation, payout import) | **None yet** | Draft | **Blocked** | — | — | Lifecycle refused on sync | — | — |
| Expense | **None yet** | Draft | **Blocked** | — | — | Refused on sync | — | — |
| Customer Deposit (booking, rental, lease) | **None yet** | Draft | **Blocked** | — | — | Refused on sync | — | — |
| Recurring invoices (scheduler) | Would be server | Generates drafts | Submit refused by guard | — | — | — | — | Generated drafts must be submitted from the form while connected |
| Channel import, construction valuations, rental/booking invoicing | Server (Sales Invoice / Payment Entry) | Drafts | Submit refused by guard | — | — | — | — | Same as above: the vertical flows are not Team-routed yet |
| Manufacturing / work-order completion | Server (Stock Entry) | Draft | Submit refused by guard | — | — | — | — | Routing the completion to the server is open |
| Opening take-on | Not for Team | — | Refused (submits Stock Entry locally) | — | — | — | — | Migrate in Solo, then connect, or add server take-on later |
| Masters (Customer, Supplier, Item, Account, …) | Sync log, conflict-checked | Yes | n/a | Device-scoped series id | n/a | Accepted. Concurrent edits raise a manual conflict, never last-write-wins | n/a | `versionCheckedMerge` |

**Blocked** means that in Team the document can be drafted and synced but
not made official. The guard explains why ("…cannot be posted in Atlas Team
yet… Keep it as a draft for now"), and the server refuses the lifecycle
mutation if a modified client tries anyway.

## POS offline policy

- **Numbering.** Each till has its own receipt series (`POS Profile`
  `till_series`). A Team POS sale without one is refused at checkout. The
  server binds a series to the first device that confirms with it, so a
  second register cannot reuse it. The receipt id is unique across tills
  without the network.
- **Local fiscal vs Team-confirmed.** A sale is *local fiscal* when the till
  submits it: the receipt is printed and the books on the till include it.
  It is *Team-confirmed* when the server has posted it, and then the sale
  carries `official_number` and `offline_fiscal`/`till_device` in the server
  payload. Only Team-confirmed sales are in the shared books other devices
  see.
- **Stock convergence.** The server never refuses a sale for stock (the goods
  have already left the shop). It records the shortfall in the response and
  the audit log (`stockShortfalls`), and later documents that need that stock
  are refused normally. Every device converges on the server's bins.
  Verified E2E: the till goes 15 → 10 locally, and all three devices reach 9
  after confirmation.
- **Duplicates and crash recovery.** Confirmation uses idempotency key
  `submit-POS Invoice-<receipt id>`, bound to that doctype and document. A
  confirmation whose response was lost replays, and a crash between submit
  and confirmation is picked up on the next sync, because the runner scans
  for the till's own submitted sales without an `official_number`.
- **Returns.** A sale is reversed with a return sale from the till, never a
  local cancel.
- **Cash reconciliation and session close.** These are local on the till
  today. The backend has no POS session close, so cash-up is not
  server-confirmed. This is an open item for Team 1.0 POS.
- **Lost till before confirmation.** Its unconfirmed sales are lost with the
  device, and its series stays bound to the old device until an admin
  releases it (manual today).
- **Malta fiscal claims.** Fiscal-receipt status remains gated on MTCA
  approval and an EXO number (`docs/MALTA_FISCAL_RECEIPTS.md`). Team
  confirmation is an accounting state, not a fiscal certification, and must
  not be marketed as one.

## Evidence

- Backend: `tests/authority_guard.rs` (11), `tests/tenant_isolation.rs` (4),
  and the posting/replication/validation suites. All 120 pass on MemStore
  and PostgreSQL.
- Hub: `test/team_posting_guard_test.dart`, `test/team_naming_test.dart`,
  `test/team_sync_runner_test.dart`, `test/team_posting_test.dart`.
- Shared accounting contract: the backend's 12 fixtures also run on the
  Solo engine (`test/accounting_contract_test.dart`, copies in
  `test/fixtures/accounting_contract`, drift check
  `tool/check_accounting_contract.sh`). All 12 pass on both engines. Only
  server-enforced role rejections and Team official numbers are skipped on
  the Solo side.
- Real multi-device test: `test/team_e2e/team_multi_device_e2e_test.dart`
  via `tool/team_e2e.sh`. It runs three hub databases against the real
  backend binary on PostgreSQL over HTTP, with no mocks. See
  [evidence/team-e2e-2026-10-23.md](evidence/team-e2e-2026-10-23.md).
