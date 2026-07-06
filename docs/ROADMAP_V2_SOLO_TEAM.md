# Neuradix Atlas Roadmap V2 — Solo / Team, Rust Backend, Setup Library, Rule-First AI

**Status:** Accepted direction (pre-implementation)
**Date:** 2026-07-06
**Supersedes:** Sections 9 (MVP scope) and 12 (roadmap) of `docs/FUNCTIONAL_GAP_ROADMAP.md`. The audit's findings (§1–8), requirements (§10–11), risks (§13) and technical appendix (§15) remain the factual baseline and are unchanged except for the POS correction below.
**Companion documents:** `docs/ATLAS_SOLO_TEAM_BACKEND_DECISION.md` · `docs/STOCK_COGS_IMPLEMENTATION_PLAN.md` · `docs/ATLAS_SETUP_LIBRARY_AND_RULE_FIRST_AI.md`

---

## 1. Strategic decisions this revision encodes

```text
Atlas Solo  = local-first / serverless, single-operator, accounting-correct
Atlas Team  = local-first client + Atlas Team Rust Backend (Linux, PostgreSQL)
COGS        = mandatory before any product/retail/POS/online-store release, both editions
Backend     = Team coordination authority (postings, numbering, identity, webhooks, portals) — not generic cloud SaaS
Setup       = Atlas Setup Library: signed, versioned, composable setup packs + deterministic rule engine
AI          = sparing setup/rule assistance; rules execute, AI never posts; customer-private data behind consent/BYOK
```

Implementation discipline is unchanged from the audit: **keep** the document engine, ledger derivation spine, conversions, guided payments, capture/OCR, seeder and banking logic; **de-mock, wire and extend**; no wholesale rewrite. The Rust backend avoids inconsistent duplicated logic via **Option A**: Dart stays the Solo (and Team preview) engine, Rust is the Team posting authority, and both run the same shared accounting fixture suite (see backend decision doc §9 and stock/COGS plan §5).

## 2. Correction to the audit's POS statement

The audit said POS "accounting is already done — [Phase 5] is till UX". That overstated it. Accurate statement:

> **POS document and Z-report foundations are present, but POS is not accounting-complete for product businesses until stock-to-GL and COGS are implemented.** A POS sale today posts revenue/VAT/cash and reduces stock quantity/value in the subledger at cost — but posts no COGS and no Inventory Asset movement to the GL.

POS completion therefore has **two** prerequisites: Phase 1B (COGS/inventory GL) for accounting completeness, and the till-UX work for operational completeness. The mandatory stock/COGS acceptance test explicitly covers POS sales.

## 3. Atlas Solo vs Atlas Team scope matrix

Legend: ✔ = in edition · ✔📦 = Solo via optional downloaded setup packs · ✔🛡 = Team with backend authority · ✖ = not in edition

| Area | Solo | Team | Notes |
|---|---|---|---|
| Company setup (guided, checklist) | ✔ | ✔ | Same setup library UX in both |
| Setup packs | ✔📦 signed download, offline apply | ✔🛡 central catalogue, versioned, synced | |
| Customers / suppliers / items | ✔ | ✔ | Team: synced masters, safe-edit conflict policy |
| Quotations | ✔ | ✔ | Team: official numbering on submit via backend |
| Sales invoices | ✔ local posting | ✔🛡 backend-confirmed submission | |
| Purchase invoices / supplier bills | ✔ local posting | ✔🛡 backend-confirmed submission | |
| Lightweight expenses | ✔ | ✔ | |
| Receipt capture (OCR) | ✔ (mobile; manual entry elsewhere) | ✔ | AI extraction optional/BYOK in both |
| Stock (quantities, warehouses, counts) | ✔ | ✔🛡 shared stock authority, availability enforced centrally | |
| **COGS / Inventory Asset GL** | **✔ local engine (Track A)** | **✔🛡 Rust engine (Track B)** | Release blocker for product businesses in both |
| POS | ✔ one device, one till | ✔🛡 multiple tills/users, shared stock, POS roles | |
| Online store | ✔ manual CSV import; polling only while app runs; manual fulfilment | ✔🛡 webhooks, automated stock sync, connector jobs | |
| Bank import | ✔ manual CSV import + local rules | ✔ + backend-run rules; 🛡 reconciliation finalisation | |
| Payment links + provider webhooks | ✖ (manual bank transfer + reference) | ✔🛡 | Requires an endpoint |
| Email sending | ✔ device-level (mailto/share; own SMTP where feasible) | ✔ backend transactional email, delivery/"Sent" tracking | |
| Customer portal | ✖ | ✔🛡 | |
| Accountant access | export files only | ✔🛡 accountant invite + portal/role | |
| Roles & permissions | single operator (device lock) | ✔🛡 role profiles enforced server-side | |
| Reports (P&L, ageing, VAT, margin…) | ✔ local | ✔ over replicated official state | |
| Backups | ✔ local backup/export | ✔🛡 server backup/restore + client cache | |
| Recurring invoices | ✔ local scheduler drafts | ✔ backend-scheduled, reliable when devices are off | |
| Projects / jobs / timesheets | ✔ | ✔ (+ multi-user assignment) | Phase 7 |
| Approvals / multi-step workflow | ✖ (single user — hide) | ✔🛡 role-routed | |
| Audit trail UI | ✔ local history | ✔🛡 company-wide, user/device-attributed | |

**Hard rule:** online-store webhooks, payment-provider callbacks, customer portal, accountant portal, multi-user identity and shared official postings **require Atlas Team**. Solo's equivalents are manual/polled/local by design, and marketing must not blur this.

## 4. Presets mapped to editions

Presets become setup-pack compositions (see setup library doc) and must state what needs Team:

| Preset | Works in Solo | Requires Team |
|---|---|---|
| **Services** | quotes, invoices, expenses, recurring-invoice drafts, reports | accountant invite/portal, payment links, shared users, customer portal |
| **Trade / Distribution** | stock, buying, selling, **COGS**, reports | shared warehouse users, payment links, online store (webhook mode), accountant access, shared official postings |
| **Retail / POS** | one-device POS, local stock, **local COGS** | multiple tills/users, shared stock authority, payment terminals, store sync, POS roles |
| **Online Store** | manual CSV order import, polled import while app runs, manual fulfilment | real webhooks, payment callbacks, automated stock sync, customer portal |
| **Light Manufacturing** | simple one-user manufacturing (BOM, work orders, backflush) | multi-user operational control, shared stock authority, roles, approvals, team audit trail |
| **Mixed Small Business** | gradual module enablement locally | as per enabled modules above |

## 5. Revised phases

Sequencing logic: **product-business accounting correctness (1B) is pulled ahead of everything expansionary** — it is not allowed to queue behind online store, POS expansion, or the backend. 1A and 1B are Solo-codebase work that also ships in the Team client; Phases 2–3 build the Team backend; 4+ each unlock a persona. 1A ∥ 1B can proceed in parallel (different layers: product surface vs posting spine); Phase 2 design can start alongside, informed by the fixture suite from 1B.

### Phase 1A — Immediate product usability (both editions; Solo-ready outcome)

Functional presets (as setup-pack compositions) · guided setup checklist · branded PDF (letterhead/logo wired into the existing core PDF renderer; retire the plain-text print action) · email/share sending · quotation lifecycle (Sent/Accepted/Rejected/Expired/Converted + expiry automation) · customer statements · payment reminders · overpayment → customer advance · lightweight Expense doctype · duplicate supplier-bill warning · opening balances UI (over the existing tested builder) · owner dashboard cards (cash, overdue, bills due, month sales, VAT estimate) · P&L report · swap approvals inbox to the real metadata source or hide it in Solo · journal-entry balance guard.

**Outcome:** an Atlas Solo **service** business can set up, send branded documents, chase money and see profit. *Not sufficient for product businesses — do not market it as such.*

### Phase 1B — Product-business accounting correctness (both editions; release blocker)

Track A of `docs/STOCK_COGS_IMPLEMENTATION_PLAN.md`: stock→GL, COGS, Inventory Asset, GRNI/update-stock decision, stock count workflow, stock valuation, stock↔GL reconciliation report, gross margin reporting, tax-inclusive pricing, migration/take-on journal. Shared fixture suite authored here (it later validates the Rust engine too).

**Outcome:** Atlas Solo is correct for **product/trade** businesses; the mandatory COGS acceptance test passes on the Dart engine. **Gate:** no product/retail/POS/online-store positioning of any edition before this is green.

### Phase 2 — Atlas Team Rust Backend MVP (coordination, not yet posting authority)

Rust backend skeleton (Axum/Tokio/SQLx) · PostgreSQL schema · company/user/device model · invitations & memberships · roles · sync API implementing the existing `CloudAdapter` contract (mutation log + blob store) · Flutter `HttpCloudAdapter` Team sync adapter · backend audit log · backup/restore tooling · Docker Compose deployment (hosted & self-hosted).

**Outcome:** a Team company with multiple users/devices syncing masters and drafts through the backend. Acceptance criteria in §6.

### Phase 3 — Backend-authoritative postings

Command API: submit sales invoice / purchase invoice / payment entry / stock entry; cancel-reverse; POS session close · backend COGS + Inventory Asset posting (Track B) · official gap-free numbering · stock availability + GL transaction safety under concurrency · client preview-vs-official flow · fixture suite green on Rust.

**Outcome:** Team official postings are backend-confirmed; two devices cannot corrupt stock or numbering; the COGS acceptance test passes in backend-authoritative mode.

### Phase 4 — Banking and payments

Banking UI over the existing tested logic (accounts, CSV import with persistence + `import_batch` dedup, match workbench, create payment/expense from bank line, splits, reconciliation view) · bank rules (rule-engine type) · payment links via provider abstraction (Stripe first) · provider clearing accounts · payment fees · payout reconciliation. Payment links/webhooks are Team (backend endpoint); bank CSV import and rules work in Solo too.

**Outcome:** businesses collect payments and reconcile the bank; provider fees and payouts don't vanish.

### Phase 5 — Online store / sales channel

Generic channel entities (Sales Channel, Channel Product/Order/Payment/Fulfilment, Sync Log) · CSV order channel (both editions) · WooCommerce polling first (Solo: while app runs; Team: backend jobs) · Shopify later · webhook mode through the Team backend · SKU mapping (rule-engine type) · order import → official sale with stock + COGS · payment/fee reconciliation via Phase-4 clearing machinery.

**Outcome:** online sellers import orders with correct stock, COGS and fees; Team gets automation, Solo gets manual/polled parity.

### Phase 6 — POS completion

Opening float entry · barcode/search/favourites grid · card & mixed tenders with change · receipt print/share (80mm + share sheet) · returns & discounts at the till · cashier attribution · suspended sales/crash recovery · session close **with stock and COGS verified end-to-end** (fixture-backed). Team adds multi-till/multi-user POS over Phase-3 authority.

**Outcome:** a shop trades all day and closes a reconciled, fully-posted session.

### Phase 7 — Services depth

Projects/jobs · tasks · timesheets · billable expenses · recurring invoices (may be pulled earlier — small effort on the existing scheduler, high demand) · retainers · project profitability.

**Outcome:** service businesses run recurring and project work with visible profitability.

### Phase 8 — Accountant & trust

Accountant role + invite (Team) · accountant portal · audit trail UI · period close/lock workflow · VAT jurisdiction forms (first target market's form, e.g. Malta or UK 9-box) · Balance Sheet · Cash Flow · GL/journal file export (real handover, not clipboard CSV).

**Outcome:** owner and accountant trust the books; filing-ready VAT.

## 6. Atlas Team Rust Backend MVP acceptance criteria

1. Owner can create a Team company.
2. Owner can invite another user.
3. The second user can join and register a device.
4. Two devices sync customers, suppliers, items and draft documents through the backend.
5. Official document submission is backend-confirmed (client draft → command → official result).
6. Official document numbers are allocated safely (no duplicates, no races; gap-free where configured).
7. Submitted documents cannot be destructively edited (immutability enforced server-side).
8. The audit log records user, device, company, action and timestamp for every official action.
9. Roles restrict access to sensitive accounting screens (server-enforced, not client-only).
10. Backup and restore are possible and drilled (scripted, documented, tested on a copy).
11. The mandatory stock/COGS posting test passes in backend-authoritative mode (fixture #1 on Rust).
12. Payment link events can be received by the backend (webhook endpoint verified, logged, idempotent) — even before full provider UX ships.
13. Online store webhook/polling events can be received and logged, even while the full connector is incomplete.

## 7. Release gates (summary)

| Release claim | Gated on |
|---|---|
| "Atlas Solo for service businesses" | Phase 1A |
| "Atlas Solo for product/trade businesses" | Phase 1B (fixture suite green on Dart) |
| "Atlas Team (multi-user)" | Phases 2–3 (backend MVP criteria 1–11) |
| "Payment links" / "connect your store (automated)" | Phase 4 / 5 + Team |
| "Run your shop on Atlas" (POS) | Phase 1B + Phase 6 |
| "Invite your accountant" | Phase 8 (portal) on Team |

## 8. What changed vs the audit's roadmap (V1 → V2)

- Single product → **two editions** with an explicit scope matrix and hard Team-only list.
- V1 Phase 1 → split into **1A (usability)** and **1B (product-business accounting correctness)**, with 1B promoted to a release blocker that nothing may queue ahead of.
- V1 "Phase 3 banking/payments before any backend" → payments/webhooks now explicitly land on the **Atlas Team Rust Backend** (Phases 2–3 inserted); Solo keeps manual/CSV paths.
- The audit's open question "cloud backend strategy" (V1 §14 Q1) is **decided**: Rust-first Linux coordination backend, PostgreSQL authority, local-first client retained; hosted and self-hosted.
- Presets → **Atlas Setup Library** (signed, versioned, composable packs + deterministic rule engine) instead of hard-coded preset flags.
- AI strategy formalised: **rule-first**, consent-gated for customer-private data, never a posting authority — generalising the capture module's existing BYOK pattern.
- POS statement corrected (§2): foundations present, accounting-complete only after 1B.
- Numbering: Solo keeps offline-safe blocks; Team backend enables gap-free sequences where jurisdictions require them (closes V1 risk #7 for Team).
- V1's "pull recurring invoices forward?" question stands; recurring remains Phase 7 with explicit permission to advance it opportunistically.
