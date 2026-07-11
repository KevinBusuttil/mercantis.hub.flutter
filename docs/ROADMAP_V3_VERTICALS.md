# Roadmap v3 — Hardening, Shared Capabilities, and Verticals

**Source:** `VERTICAL_MODULE_GAP_ANALYSIS.md` (sector matrix, vertical
catalogue, critical findings). This document is the executable sequence.
Increments are commit-sized, land with tests, and pause for review after
each. Companions: `ROADMAP_V2_SOLO_TEAM.md` (completed), the gap analysis.

## Decisions taken

**POS offline policy — the carve-out (chosen over an offline submit
queue).** POS Invoice posts through the LOCAL engine even in Team mode,
deliberately: a till must complete a sale with zero network, and a server
rejection hours after the customer left is unresolvable. Compensating
controls: per-till receipt series (`POS Profile.receipt_series` →
`till_series` on the invoice → `POS-.{till}.-.####` naming) make
cross-register id collisions structurally impossible, and the Z-report /
session reconciliation is the retail control point. Upgrade path if a
jurisdiction mandates centrally issued receipt numbers or real-time fiscal
reporting: a durable offline submit queue replaying idempotent commands —
nothing in the carve-out precludes it. Every other posted doctype
(Sales/Purchase Invoice, Purchase Receipt, Payment Entry, Stock Entry,
**Delivery Note**) goes through the backend posting authority in Team mode.

## Phase 0 — Hardening (gate for all vertical work)

| # | Increment | Repo(s) | Status |
|---|---|---|---|
| 0.1 | Team posting set → 6 doctypes (DN in); POS carve-out documented + pinned by test; per-till receipt series (field tokens in naming series) | core + hub | **done** |
| 0.2 | Persist + display `official_number` (sync apply, form header, PDFs); local ids demoted to internal refs | core + hub | **done** |
| 0.3 | Skip local outstanding rewrites for officially-numbered documents (409 poison loop) | hub | **done** |
| 0.4 | Server-side money validation: recompute totals + tax with tolerance, reject mismatch; settlement over-allocation guard; strict ISO posting-date validation | backend | **done** |
| 0.5 | Credential lifecycle: device revocation, member remove/role-change, token expiry, hashed invitation tokens; Team-screen device management; keychain storage for TeamSession | backend + hub | **done** |
| 0.6 | Paginated sync pull with per-page cursor commit; explicit body-size limits; blob size policy | backend + core | **done** |
| 0.7 | Postgres CI: full backend suite against real Postgres via the Store trait | backend | **done** |
| 0.8 | Audit rows for submit/cancel/amend/delete in the core engine | core | **done** |
| 0.9 | Rate limiting; gated company creation; webhook intake caps | backend | **done** |
| 0.10 | Conflict visibility: list `sync_state=conflict` docs with keep-mine/take-theirs | core_ui + hub | **done** |

## Phase 1 — Gateway capabilities

1. **S8 Pricing & discounts** — price-resolution interceptor (customer
   price list → item price/qty breaks → standard rate) into invoices, POS,
   channels; line + invoice discounts with correct GL. *(2 increments)*
   **done** — resolver + interceptor + POS till (S8a); line/document
   discounts folded into rates from a captured base (S8b).
2. **S4 Deposits & prepayments** — request/receipt doctype, liability
   posting, application via settlements, liability report. *(1–2)*
   **done** — Customer Deposit doctype; application = Receive Payment
   Entry with paid_to = deposit liability; computed applied/outstanding;
   report screen.
3. **S1 Scheduling core** — Schedulable Resource + Appointment doctypes,
   conflict checking, reusable calendar widget (day/week, resource lanes),
   booking→invoice hook. *(2–3)*
   **done** — doctypes + half-open-interval conflict guard + S8-priced
   invoice hook (S1a); ResourceCalendar widget + day/week Schedule board
   with slot booking and status actions (S1b).
4. **S3 Capture primitives** — signature widget for `FieldType.signature`,
   camera-photo attach anywhere; wire deliveries POD. *(1)*
   **done** — POD sheet (signature strokes + camera photo + note) on
   Delivery Route Stop via markStopStatus; Driver Today gained
   Deliver/Failed actions.
5. **S12 Driver UX completion** — real Driver Today (status transitions,
   POD, per-driver filter). *(1)*
   **done** — today-first per-driver route selection, one-tap Start
   route, self-completing runs.

**Phase 1 complete.**

## Phase 2 — V1 Field Service & Trades (~6 increments)
Service Request + Job (materials/labour/checklist/photos/signature) →
dispatch board (S1 over technicians) → technician mobile day flow
(offline-first) → job→invoice conversion (stock/COGS via update_stock) →
Maintenance Contract + recurring job generation → KPIs.

Status: V1-1 **done** (module + request→job + dispatch booking S1
appointments); V1-2 **done** (invoiceForJob: van-stock issue + COGS via
update_stock, S8-priced materials, labour via service item). Ships as an
AppManifest package + Setup Pack — first proof of the composable
architecture; close manifest-versioning and UI-override-registry gaps here.

## Phase 3 — V2 Hospitality POS (~5 increments)
Floor/Table + Tab + modifiers → table-map till on the existing
session/tender/Z spine → kitchen tickets → split/merge + service charge →
void/comp audit. **Precondition: verify Malta fiscal-receipt law.**

## Phase 4 — Appointments composition pack (~2 increments)
S1 + S4 + S9 (commission rules) + booking screen + Setup Pack — the
salon/tutor/studio offering without a vertical build.

## Phase 5 — Next wave (each gated on its capability)
S10 Fixed assets → V4 Repair/Garage (V1 specialisation + S2 asset
register) → V3 Rental (S2+S5+S10) → V5 Property/Landlords → V7
Memberships → S13 EN 16931/PEPPOL e-invoicing (EU mandate clock) → V6
Construction.

**Deferred:** S7 batch/serial/expiry (deepest ledger surgery — wait for a
paying segment), multi-company, SaaS-billing depth, i18n scaffolding until
the first non-English market. **Integrations, never builds:** clinical
records, legal client money, hotel PMS, payroll computation, MES,
agri/fisheries registers — via the command API + webhooks.

## Operating model
Backend items run as parallel agents; hub/core inline; every increment
lands green with tests and pushes; pause for review after each. Droplet
redeploy: `git pull && docker compose up -d --build`.
