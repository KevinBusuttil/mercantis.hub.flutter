# Neuradix Atlas — Vertical Module Gap Analysis

**Scope:** independent, evidence-based analysis of `mercantis.core.flutter`,
`mercantis.hub.flutter`, and `neuradix-atlas-team-backend` to determine which
micro-business vertical modules are missing, which sectors the platform can
already operate (not merely invoice), and the smallest set of shared
capabilities and verticals that maximises Malta/EU micro-business coverage.

**Method:** three parallel code audits (hub operational modules; core engine
and UI-kit seams; backend + cross-cutting defect sweep) over source, tests,
migrations and services — deliberately *not* over READMEs, menus or route
names. Maturity is judged by the presence of dedicated services, posting
integration and engine-backed tests; a doctype with a free generic screen and
no service or test is classified skeletal. Where evidence is incomplete this
document says so.

**Reading guide for maturity labels:** production-complete · substantially
implemented · partially implemented · skeletal · documented-not-implemented ·
absent.

---

## 1. Current ERP capability map

### 1.1 The accounting/stock spine (the platform's real strength)

| Capability | Maturity | Evidence | Key gap |
|---|---|---|---|
| General ledger + derivation | **Production-complete** | `hub lib/ledger/ledger_derivation.dart` (+service), balance guard, `test/stock_cogs_acceptance_test.dart` | Audit rows missing for submit/cancel (see §8) |
| Perpetual inventory / COGS | **Production-complete** | Moving Average + FIFO (`stock_costing.dart`, `ledger_valuation_test.dart`), GRNI split, returns at cost | No landed costs |
| VAT engine + returns | **Substantially implemented** | `hub_tax_engine.dart` (exclusive+inclusive), Tax Transactions, Malta/UK return layouts (`tax_return_builder.dart`) | Backend never validates client tax math (§8-C2) |
| Sales chain QTN→SO→DN→SINV | **Substantially implemented** | `hub_document_conversion.dart` remaining-qty netting; `hub_conversion_fulfilment_test.dart` | No back-order object, no %-fulfilled rollup on SO |
| Purchasing chain PO→PR→PINV | **Substantially implemented** | GRNI clearing tested; duplicate-bill guard | Shallow supplier master; no landed costs, no RFQ compare |
| Payments & settlements | **Substantially implemented** | Guided payment, settlements, outstanding maintenance; Stripe payout-fee import | Command API lacks over-allocation guard (§8-C3) |
| Banking & reconciliation | **Substantially implemented** | CSV import (idempotent), matcher, reconcile workbench, rule-driven expense categorisation | No bank feeds (API); JE-side matching thin |
| Expenses + capture | **Production-complete** (capture) | `capture_service.dart` OCR→draft PINV, merchant memory, quota-gated LLM; 296-line test | Header-level extraction only; no email intake |
| Recurring invoicing | **Substantially implemented** | `recurring_invoice_service.dart`, catch-up, error stamping | No proration/dunning/pause (SaaS-grade) |
| Reporting | **Substantially implemented** | Trial Balance, P&L, BS, cash flow, aging, margin, valuation, GL export; SavedReportEngine (groupBy+aggregates) in core | Saved-report builder has **no UI**; charts spec-only |
| Year-end close / period lock | **Substantially implemented** | `year_end_close_builder.dart`, lock tool | Backend lock is lexicographic string compare (§8-C4) |
| Offline sync (Solo folder) | **Substantially implemented** | FileSystemCloudAdapter, children+blobs, quarantine of permanent rejections | Conflicts = wall-clock LWW, whole-document (§8-C6) |
| Team backend (Rust) | **Substantially implemented** | 7-doctype posting authority, gap-free numbering, portal, pay links, replication; 60+ tests | **All tests run on MemStore; PgStore has zero automated coverage** (§8-C1) |

### 1.2 Operational modules

| Module | Maturity | Evidence | Key gap |
|---|---|---|---|
| POS | **Substantially implemented** | 882-line till, sessions, X/Z, returns, barcode, park/resume, receipts (`pos_shift_report_test.dart`) | **No discounts anywhere**; no cashier identity on sales; Cash/Card/Other only |
| Manufacturing | **Substantially implemented** | BOM+ops, WO, Production Plan, auto-post completion at rolled-up cost (`ledger_production_cost_test.dart`) | Single backflush (no WIP issue step); operating cost display-only; no capacity |
| Projects/time | **Substantially implemented** | Retainer-safe billing, profitability (`projects_test.dart`) | No budgets, no Gantt, no cost-to-complete |
| E-commerce channels | **Substantially implemented** | CSV/Woo/Shopify → staged orders → official invoices with COGS; payout-fee JE | Polling only (webhook intake logged, never processed) |
| Deliveries/routes | **Partially implemented** | Real data model + event-sourced status service (`deliveries_test.dart`) | **Driver UX is no-op buttons** (`driver_today_screen.dart:77-80`); no dispatch board |
| CRM | **Partially implemented** | Lead→Customer→Quotation conversion tested | No activities/timeline, no pipeline view, no Opportunity automation |
| Setup Library | **Substantially implemented** (foundation) | Tamper-evident packs, idempotent applier + diff, deterministic rule engine (`setup_library_test.dart`) | Catalogue is 3 starter packs; no Team-hosted catalogue |
| Customer portal / pay links | **Substantially implemented** (Team) | Backend `portal.rs`/`pay.rs` well-tested; hub mint actions | Quote/invoice only; no statements/documents upload |

### 1.3 Absent or dead (verified by exhaustive search)

| Capability | Status | Evidence |
|---|---|---|
| Scheduling / appointments / bookings / resource calendars | **Absent** | Zero entity/service/screen matches across `lib/` + `test/` |
| Pricing engine (price lists, discounts, promotions) | **Skeletal (dead doctype)** | Price List/Item Price exist (`setup_module.dart:47-74`) but **nothing reads them**; POS uses `Item.standard_rate`; line items have no discount field |
| Batch / serial numbers / expiry dates | **Absent** | Zero matches; SLE "Reservation" enum value unused |
| Fixed assets & depreciation | **Absent** | Only chart-of-account labels mention depreciation |
| Contracts / rental / membership / subscription entities | **Absent** (beyond Recurring Invoice) | No entity-shaped matches |
| HR (employees, payroll, commissions, leave, rosters) | **Absent** | "Employee" is a party-type select option only |
| Multi-company | **Skeletal** | `company` field exists; interceptors fall back to "first company"; **reports/KPIs do no company filtering**; no switcher |
| i18n / localisation infrastructure | **Absent** | Zero intl/locale matches in either Flutter repo; all strings English |
| Credit limits / customer on-hold enforcement | **Absent** | Supplier `on_hold` stored, never enforced |
| Structured e-invoicing (EN 16931 / PEPPOL) | **Absent** | PDF + text only |

---

## 2. Micro-business sector coverage matrix

Classifications: **A** Strong native fit · **B** Fit with configuration ·
**C** Fit with reusable capability packs · **D** Requires a dedicated
vertical · **E** Requires substantial specialist integration · **F**
Unsuitable as the primary operational system.

| Sector | Class | Reasoning (operational workflows, not invoicing) |
|---|---|---|
| Freelancers / consultants | **A** | Projects, timesheets, retainer-safe billing, recurring, expenses/capture, statements — the whole loop is tested end-to-end today. |
| Accountants / professional practices | **B** | Firm's own books: strong. Client work = projects + recurring + accountant portal. Missing only deadline/compliance task calendaring (S1 makes this C→B is fine with Task due_dates). |
| Agencies / project-based services | **A** | Same loop as freelancers plus quotation→project conversion; profitability report exists. |
| Electricians / plumbers / HVAC / trades | **D → V1** | Can quote and invoice, cannot *operate*: no service requests, scheduling, dispatch, job sheets, customer equipment history, parts-from-van, photos, signatures. All absent (§1.3). |
| Field-service & maintenance cos | **D → V1** | Same as trades plus maintenance contracts and recurring job generation (S5+S11). |
| Builders / contractors / subcontractors | **D → V6** | Projects exist but no progress/application billing, retention money, variations, subcontractor cost tracking. Materially distinct billing rules. |
| Retail shops | **C** | POS is real (sessions, Z, returns, barcode) — but no discounts, no price lists in effect, no loyalty. S8 pricing pack closes most of it. |
| Wholesalers / distributors | **C** | Chain + partial fulfilment tested; needs S8 (customer price lists, qty breaks), credit limits, back-order visibility. Capability work, not a vertical. |
| E-commerce sellers | **A** | Three channels, SKU mapping, staged orders → COGS-posting invoices, payout-fee reconciliation. The strongest operational vertical today. |
| Cafés / restaurants / bars / takeaways | **D → V2** | Retail POS ≠ hospitality POS: no tables/tabs, no item modifiers, no kitchen routing, no split bills, no covers/service charge. Materially distinct UI + workflow. |
| Bakeries / catering / food production | **C** | BOM/WO manufacturing is real; missing batch/expiry traceability (S7) and production-day planning. Capability pack + config, not a full vertical. |
| Wineries / breweries / beverage | **C + localisation** | As above plus excise duty accounting (country pack). Bond/excise registers may push larger producers to E. |
| Salons / barbers / beauty / wellness | **C (thin pack)** | The operational core is appointments (S1) + deposits (S4) + staff commissions (S9) + retail POS (exists). No materially distinct records beyond that composition. |
| Gyms / fitness / membership orgs | **D-lite → V7** | Memberships (S6) + class schedules (S1) + access/attendance + dunning. Mostly capability composition but the membership lifecycle justifies a thin vertical. |
| Tutors / training centres | **C** | S1 (sessions/rooms) + S6-lite (course enrolment) + existing invoicing. |
| Repair workshops / garages | **D → V4** | Job cards exist only inside manufacturing; garages need vehicle asset history (S2), intake→diagnosis→approval→repair workflow, serials (S7-lite), courtesy flows. |
| Equipment / tool / vehicle rental | **D → V3** | Availability calendar, rental contracts, deposits, off-hire, damage charges, utilisation. Materially distinct records and rules. |
| Landlords / property management | **D → V5** | Leases, rent schedules, deposits (often segregated), maintenance requests, owner statements. Distinct records + fiduciary reporting. |
| Real-estate agencies | **C** | CRM pipeline depth + commissions (S9) + escrow-adjacent handled by banks. No distinct operational records beyond CRM+commissions. |
| Courier / transport / small logistics | **C (module completion)** | The route/driver/POD data model and status service already exist — what's missing is the driver mobile UX (currently no-op buttons) and a dispatch board. Finish the module; not a new vertical. |
| Cleaning / security / home services | **D → V1** | Recurring scheduled jobs, rosters, site checklists — V1 with recurring-job generation (S11). |
| Event organisers / creative production | **B** | Quotes, deposits (S4 improves), projects, purchase tracking. Configuration + S4. |
| Subscription / SaaS businesses | **C** | Recurring invoicing exists; missing proration, dunning, upgrade/downgrade, Stripe Billing sync. Capability extension + integration; not a vertical UI. |
| Charities / associations / clubs | **C** | S6 memberships + donations (a receipt doctype via config); Malta VO annual-return reporting = country pack. Full fund accounting → E for larger NGOs. |
| Agriculture / fisheries | **E/B** | Books + sales fit (B); regulated operational records (catch documentation, herd registers, subsidy schemes) are specialist systems. Atlas = financial ERP. |
| Light manufacturing | **B** | BOM, work orders, plan→WO→auto-posted completion at rolled-up cost — genuinely implemented and tested. |
| Advanced manufacturing | **E** | Capacity scheduling, shop-floor MES, quality plans out of scope; Atlas as ledger + integration. |
| Healthcare / dental / veterinary | **E** | Clinical records are GDPR special-category with retention/consent rules — specialist PMS; Atlas takes the financial side (+ S1 if the practice wants unified booking, with care not to store clinical data). |
| Legal practices | **E (client money) / B (firm books)** | Client/trust money accounting is regulated bookkeeping with segregation rules — do not reproduce; integrate. Matter time-billing works via projects today. |
| Hotels / guesthouses / short-let | **E** | Reservations, channel managers (OTA), housekeeping, night audit = PMS territory. Atlas = finance + payout reconciliation (the Stripe payout machinery generalises to OTA payouts). Single-unit short-lets can run as B with recurring + channels. |

**Additional archetypes worth naming:** market/stall traders and mobile
vendors (covered by POS + offline = B); IT/MSP shops (B today, C with S5
contract billing); import/trade agents (B); photographers/videographers
(B, deposits help); childcare (E-adjacent for compliance registers).

---

## 3. Missing vertical-module catalogue

Only genuine verticals — where records, workflows, rules or UI are
materially distinct — survive from the seventeen hypotheses. Each depends
on shared capabilities in §4 (listed as S-refs) rather than duplicating them.

### V1 — Field Service & Trades
*The single largest Malta/EU micro-business mass: electricians, plumbers,
HVAC, appliance repair, cleaning, pest control, lifts/maintenance.*
- **Problem:** the day is jobs, not documents: request → schedule → dispatch → do → prove → bill.
- **Doctypes:** Service Request; Job (site, asset link, checklist, materials-used child, labour child, photos, signature); Job Template; Maintenance Contract (S5+S11); Engineer/Technician (roster-lite).
- **Workflows:** request intake → triage → scheduled (S1) → en-route/on-site → completed (signature) → invoiced (job→SINV conversion reusing the conversion framework); recurring contract jobs auto-generated (S11); parts issue from a "van warehouse" (existing multi-warehouse + Stock Entry covers this).
- **Screens/mobile:** dispatch board (day/week per technician); technician mobile day list → job sheet (offline-first — the sync engine already supports this); photo + signature capture (needs the core attachment/signature field wired, §4-S3).
- **Accounting/stock:** job → Sales Invoice with materials (stock, COGS via existing `update_stock`) + labour lines; WIP optional later.
- **Reports/KPIs:** first-time-fix rate, jobs/day/tech, unbilled completed jobs, contract profitability.
- **Roles:** dispatcher, technician (job-scoped row access — engine's `rowAccessExpression` supports this), owner.
- **Malta/EU:** none specific beyond VAT already handled.
- **Placement:** Hub package + Setup Pack; Team backend unchanged (jobs are normal synced documents; only invoices post).

### V2 — Hospitality POS
*Cafés, restaurants, bars, takeaways — Malta's densest sector.*
- **Problem:** table/tab lifecycle, modifiers, kitchen coordination, splits.
- **Doctypes:** Floor/Table; Tab (open order); Menu Item Modifier groups; Kitchen Ticket; Service Charge/Tip config.
- **Workflows:** open tab → fire courses to kitchen (printer/screen) → amend → split/merge → tender (existing tenders) → Z (existing sessions/Z-reports reused); takeaway/delivery order type.
- **Screens:** table map till; kitchen display; the existing POS session machinery underneath.
- **Accounting/stock:** POS Invoice path already posts cash/VAT/stock; add recipe-level deduction later via BOM (exists).
- **KPIs:** covers, average ticket, per-hour sales, voids/comps (needs void audit).
- **Roles:** waiter, kitchen, manager (voids/comps approval).
- **Malta/EU:** fiscal-receipt regimes vary by country — Malta's fiscal receipt rules must be a country-pack concern; **verify current MTCA requirements before market claims**.
- **Placement:** Hub package (new till UI) + Setup Pack; heavy UI, no backend change.

### V3 — Rental & Hire
*Tools, equipment, vehicles, party/event kit.*
- **Doctypes:** Rental Asset (S2 specialisation w/ serial), Rental Contract (S5) with period pricing, Availability (S1 calendar over assets), Deposit (S4), Off-hire/Return inspection (damage charges).
- **Workflows:** reserve → pick/deliver (existing DN) → on-hire billing (S5 recurring or period) → off-hire inspection → deposit release/deduct → invoice.
- **Accounting:** deposits as liabilities (S4); assets as fixed assets (S10) with depreciation; damage → invoice lines.
- **KPIs:** utilisation %, revenue per asset, overdue returns.
- **Placement:** Hub package + Setup Pack; depends hard on S1/S2/S4/S5/S10.

### V4 — Repair Workshop & Garage
- **Doctypes:** Customer Vehicle/Device (S2 with serial/VIN, service history), Workshop Job Card (intake checklist, diagnosis, estimate→approval, parts+labour), Courtesy asset.
- **Workflows:** intake → estimate (reuses Quotation) → customer approval (portal reuse) → repair → QC → invoice; parts from stock (exists).
- **KPIs:** bay throughput, comeback rate, parts vs labour mix.
- **Placement:** Hub package + Setup Pack; shares 80% of V1's job-sheet machinery — build V1 first, V4 as its specialisation.

### V5 — Property Management & Landlords
- **Doctypes:** Property/Unit (S2), Lease (S5: term, rent schedule, indexation), Tenant deposit (S4, possibly segregated bank account — banking module supports multiple accounts), Maintenance Request (feeds V1-style jobs), Owner (for agencies managing third-party property) + Owner Statement.
- **Workflows:** lease → recurring rent (existing recurring engine) → arrears chase (existing reminders) → maintenance → deposit settlement at exit.
- **Accounting:** rent receivable; deposits as liabilities; agency mode needs client-money discipline → for *agencies*, deposits/client accounts approach the legal-segregation boundary (§5) — landlord self-management is safely in scope, third-party letting agents need care.
- **Placement:** Hub package + Setup Pack.

### V6 — Construction & Subcontracting
- **Doctypes:** Contract/Project (extends Projects), Payment Application/Progress Claim (% complete per line, certified vs applied), Retention (held/receivable with release schedule), Variation Order, Subcontractor Order (+ their applications inward).
- **Workflows:** application → certification → invoice with retention withheld → retention release at making-good; CIS-style subcontractor deduction where applicable (country pack concern; not Malta-core).
- **Accounting:** retention as separate receivable/payable; WIP/revenue recognition kept simple (invoice-based) for micro-scale.
- **Placement:** Hub package + Setup Pack; postpone-able behind V1 (many small builders operate happily as trades V1 + projects until they hit progress billing).

### V7 — Memberships, Classes & Clubs (thin)
- **Doctypes:** Membership Plan, Membership (S6), Class/Session schedule (S1), Attendance/Check-in.
- **Workflows:** join → recurring dues (existing) → dunning (S-extension) → class booking → attendance.
- **Placement:** mostly S1+S6 composition; the vertical is a UI veneer (check-in screen, schedule board) + Setup Pack.

**Rejected/absorbed hypotheses:** Appointments & Personal Services → S1+S4+S9
composition (salons need no distinct records). Food Production & Traceability →
S7 + existing BOM (config). Transport/Courier → completion of the existing
deliveries module, not a new vertical. Subscription & SaaS Billing →
recurring-engine extension + Stripe Billing integration. Professional
Practice, Real-Estate Agency, Event/Creative → configuration + S-packs.
Training & Education → S1+S6. Agriculture & Fisheries, Advanced
Manufacturing → §5 boundaries.

---

## 4. Shared capability modules (build once, reuse everywhere)

| # | Capability | Consumed by | Notes / evidence of absence |
|---|---|---|---|
| **S1** | **Scheduling & resource calendar** (appointments, bookings, technician/asset/room calendars, availability) | V1, V2(-lite), V3, V4, V7, salons, tutors, real-estate viewings, practice deadlines | The single highest-leverage missing capability. Zero scheduling code exists today. Needs: Schedulable Resource, Appointment/Booking doctype, calendar UI widget in core_ui, conflict checking. Offline-friendly (documents). |
| **S2** | **Customer asset register** (equipment/vehicle/property owned by the customer or by us; service history) | V1, V3, V4, V5 | Absent. Generic Asset doctype with `owner_party`, serial, location, history timeline (audit reader exists to power it). |
| **S3** | **Field job sheet primitives** (checklists, photo evidence, signature capture) | V1, V4, deliveries POD, stock count evidence | `FieldType.signature` exists in core metadata but has no capture widget; POD button is a no-op. Core_ui work. |
| **S4** | **Deposits & prepayments** (liability-accounted, applied to invoices, refundable) | V2, V3, V5, events, salons, tutors | Payment Entry lacks unapplied-deposit lifecycle; guided payment keeps overpayment "as credit" but there's no deposit request/receipt document or liability reporting. |
| **S5** | **Contract management** (term, renewal, billing schedule link, documents) | V1 maintenance, V3, V5, security/cleaning, MSPs | Absent. Contract doctype driving the existing recurring engine. |
| **S6** | **Memberships & plans** | V7, charities/clubs, training | Absent; recurring engine is the billing half. |
| **S7** | **Batch/serial/expiry traceability** | Food/beverage production, garages (serials), V3 assets, pharmacies-adjacent retail | Absent at SLE level — this is *core ledger surgery* (SLE + costing per batch), the deepest technical item here; scope carefully (batch-level first, serial second, expiry as batch attribute). |
| **S8** | **Pricing & discounts engine** (make Price List live: resolution order, customer/qty pricing, line+invoice discounts, POS discounts) | Retail, wholesale, POS, channels, everyone | Price List is a dead doctype today (§1.3). Highest ROI-to-effort ratio in this list. |
| **S9** | **Staff & commissions** (minimal staff master + commission rules on invoices/items, commission report) | Salons, real-estate, sales-agent wholesale | Absent; deliberately NOT payroll. |
| **S10** | **Fixed assets & depreciation** (register, schedules, monthly JE posting) | Universal accounting completeness; V3/V5 hard dependency | Absent; straightforward on the existing JE spine. |
| **S11** | **Maintenance & recurring job generation** (schedule → jobs) | V1 contracts, V3 fleet upkeep, V5 properties | Absent; composes S5 + V1 job. |
| **S12** | **Dispatch & driver mobile completion** | Courier/transport, V1 shared UX patterns | Data model exists; wire the no-op driver UX, POD (S3), dispatch board. |
| **S13** | **Structured e-invoicing (EN 16931 UBL/PEPPOL)** | All B2B/B2G sectors; EU regulatory direction (ViDA; B2G already mandatory in most member states) | Absent (PDF/text only). Country-pack adjacent but the UBL generator is shared. **Strategically urgent for "EU" positioning.** |
| **S14** | **Customer portal extensions** (statements, document upload, approvals) | Practices, V5 tenants/owners, V4 approvals | Portal foundation shipped (backend `portal.rs`); extend, don't rebuild. |
| **S15** | **Payroll-journal import** (map external payroll provider output → JE) | Every employer; NOT payroll computation | Absent; a mapping importer on the existing import machinery. |

**Order-of-dependence:** S8 and S4 unlock the most B/C-class sectors for
near-zero risk; S1+S3 unlock every D-class vertical; S10 is universal
accounting hygiene; S7 is the hardest and should wait until a paying food or
serial-driven segment demands it.

---

## 5. Specialist-system boundaries

Atlas should remain the **financial ERP + master data + document spine** and
integrate rather than reproduce:

| Domain | Why out of scope | Integration model |
|---|---|---|
| Clinical/care records (medical, dental, vet, childcare) | GDPR special-category data, clinical safety, retention/consent regimes | Specialist PMS owns records; Atlas receives invoices/fees via API or CSV; never store clinical data in synced documents |
| Legal client-money / trust accounting | Regulated segregation, audit regimes (e.g. MT/UK solicitors' accounts rules) | Firm books in Atlas; client account in specialist or tightly-scoped separate ledger; import summaries as JEs |
| Hotel PMS / OTA channel management | Reservations, allotments, night audit, OTA connectivity is an industry of its own | PMS→Atlas: daily revenue journal + payout reconciliation (the Stripe payout importer generalises to OTA payout files) |
| Regulated financial services, insurance, gaming | Licensing, conduct rules, product systems | Atlas = corporate books only |
| Payroll computation | Country-specific tax/social security engines with legal update cadence | S15 journal import from providers (e.g. local Malta payroll bureaus, cloud payroll) |
| Mature MES / advanced manufacturing | Capacity, routing execution, quality plans, machine integration | Atlas keeps BOM-costed inventory + finance; MES posts consumption/production via the command API (which now exists and is idempotent) |
| Fisheries/agriculture regulatory registers | Catch documentation, herd books, subsidy schemes | Keep in national systems; Atlas books the money |

The **command API + webhook intake + mutation-log replication** built this
cycle is exactly the right integration surface: a specialist system can post
official documents through the same authority as a device, with idempotency
and audit. The missing piece for third parties is API-key-style credentials
scoped narrower than a device token (§8-C8 adjacent).

---

## 6. Recommended architecture

**Target model:** `Universal ERP Core + Shared Capability Packs + Country Pack + Sector Vertical` — and the codebase is *already surprisingly close*:

- **Verticals/capabilities as Dart packages registering an `AppManifest`.**
  The core AppInstaller supports multiple apps, incremental `syncMetadata()`
  update, and uninstall (`app_installer.dart`, tested). A vertical package
  ships: doctypes+workflows+reports+dashboards+automation rules (manifest),
  interceptors (`documentInterceptorsProvider`), workspaces + custom routes
  (WorkspaceRegistry), command-bar actions (DocumentActionRegistry),
  dashboard cards, print formats, naming strategies, automation actions.
  All twelve seams exist and are enumerated in the core audit — **no fork
  needed**. Hard-coded industry forks are neither necessary nor acceptable.
- **Setup Packs stay the data/config layer** (accounts, defaults, rules,
  toggles) on top of code packages — the current tamper-evident pack format
  with recorded diffs is the right vehicle; extend `SetupPack` with
  `requiresApps: [package ids]`.
- **Country packs** = Setup Pack (chart, VAT bands — the seeder already does
  MT/UK/IE/generic) + code where behaviour differs (VAT return layouts
  already pluggable via `TaxReturnBuilder`; add fiscal-receipt and
  e-invoicing profiles here).
- **Feature flags / editions:** module toggles already flow
  preset→HubSettings→workspace visibility. Add per-pack `edition`
  requirement (field already reserved in the pack format) and gate Team-only
  packs on an active TeamSession.
- **Backend boundary:** verticals that only add *documents* need zero backend
  change (documents sync; only the 7 posted doctypes touch the posting
  authority). A vertical introducing a new *posted* doctype must extend the
  Rust engine + fixtures — keep posted doctypes a closed, slowly-growing set;
  most verticals bill through the existing Sales Invoice.

**Gaps to close before scaling packages (foundation work):**
1. Manifest **versioning/dependency resolution** — `minimumCoreVersion` is
   stored but never checked; add version+dependency validation at install.
2. **Migrations for pack data** — packs are additive-only today (correct),
   but doctype *changes* across pack versions need a declared migration hook.
3. **Per-doctype UI override registry** — verticals with bespoke UX (POS
   till, dispatch board) currently use custom routes; add an optional
   form/list override registry so a vertical can replace the generic form for
   its doctypes without touching navigation.
4. **Enforce the dormant metadata** — field `validationRules`,
   `visibilityExpression`, field-level permissions are parsed but unenforced;
   verticals will want them.
5. **Expression engine**: child-row aggregation (`sum(items.amount)`) and
   date arithmetic — needed by almost every vertical's computed fields.
6. **Workflow UI + approval semantics** — engine exists, UI doesn't; V4/V6
   approvals need it.
7. **Background scheduling** — the scheduler runs foreground-only and
   manifest `schedulerEvents` dispatch is a stub; recurring jobs (S11),
   dunning, and Team-side polling need either app-foreground contracts or
   backend cron (none exists server-side either).
8. **i18n scaffolding** before any non-English market claim.
9. **Offline/sync implications per pack:** all vertical doctypes must declare
   `SyncPolicy`; conflict UX (see §8-C6) becomes more urgent as verticals
   multiply concurrent editors.

---

## 7. Prioritised roadmap

**Criteria:** MT/EU micro-business count addressed · commercial value · reuse ·
complexity · dependency/regulatory risk · offline/mobile fit · architecture fit.

**Phase 0 — Foundation (before any vertical):**
1. Fix the §8 critical findings (posting-trust, doctype-set mismatch,
   official-number plumbing, token revocation, pull pagination) — vertical
   expansion on an unsafe spine multiplies the blast radius.
2. **S8 Pricing & discounts** (unlocks retail/wholesale properly; small).
3. **S4 Deposits** (unlocks events/salons/rental groundwork; small).
4. **S1 Scheduling core + calendar UI** (the gateway capability).
5. **S3 signature/photo capture + S12 driver-UX completion** (proves the
   mobile field pattern on the existing deliveries module).
6. Architecture items §6.1–6.5.

**First three verticals (in order):**
1. **V1 Field Service & Trades** — largest addressable mass (trades +
   cleaning + maintenance + home services all land on it), fully offline-
   friendly, no regulatory risk, reuses S1/S2/S3.
2. **V2 Hospitality POS** — Malta density + the existing POS spine halves
   the cost; verify fiscal-receipt compliance first.
3. **Appointments composition pack** (salons/tutors/studios) — not a
   vertical build at all: S1+S4+S9 + a booking screen + Setup Pack; cheap
   third "vertical" commercially.

**Next wave:** V4 Repair/Garage (V1 specialisation) → V3 Rental (needs
S10) → V5 Property/Landlords → V7 Memberships → S13 e-invoicing (timed to
EU/Malta B2B mandates) → V6 Construction.

**Postpone:** real-estate agency depth, event-production depth, SaaS billing
depth, S7 full traceability (until a paying segment), multi-company.

**Remain integrations:** everything in §5.

---

## 8. Critical code findings (vertical expansion is unsafe until C1–C5 are addressed)

**C1 — PgStore has zero automated test coverage.** Every backend test runs on
`MemStore` (`tests/support/mod.rs:45`); the 1,498-line `pg.rs` — advisory-lock
posting transaction, gap-free numbering SQL, projection fold, 7 migrations —
is exercised only by manual smoke tests. The concurrency guarantees marketed
by the posting authority are tested against a mutex, not Postgres. *Fix:
containerised Postgres test job running the same suite via the Store trait.*

**C2 — The posting authority trusts client-computed money.** `engine.rs`
derives `grand_total` only when absent (`ensure_invoice_totals`) and posts the
client's `taxes` array verbatim — no recomputation of rate×base, no
Σlines-vs-total cross-check. A buggy/tampered client writes arbitrary revenue
and VAT into the immutable official ledger under an official number
(`hub` computes correctly via `TaxCalculationInterceptor`, but the server is
the authority and must validate). *Fix: server-side recompute-and-compare
with tolerance; reject on mismatch.*

**C3 — Payment over-allocation unguarded.** `derive_settlements` never checks
Σallocations ≤ paid_amount nor allocation ≤ outstanding; outstanding can go
negative via the command API (the Stripe path clamps; the generic path
doesn't). Also: invoices cancel silently while settlements reference them.

**C4 — Period lock is a string compare on unvalidated dates.**
`posting_date: "9999"` (or any non-ISO junk) posts past any lock
(`engine.rs:1579-1588`). *Fix: strict ISO-date validation + sane range.*

**C5 — Team/local posting split-brain for Delivery Note & POS Invoice.**
Client `teamPostedDocTypes` lists 5 doctypes; backend `POSTED_DOCTYPES` has 7.
DN and POS Invoice submit through the *local* engine in Team mode — two
posting engines for the same doctypes, no official numbers, deterministic-id
collision risk (`GL-{id}-…`) if ever command-posted. *One-line client fix +
an offline-behaviour decision (POS must keep working offline — either an
offline submit queue for POS or an explicit documented carve-out).*

**C6 — Conflict resolution is wall-clock LWW, whole-document.** Concurrent
draft edits on two devices: later device clock wins wholesale; loser's edits
silently discarded; `versionCheckedMerge` flags conflicts nobody can see or
resolve (no UI, no API). Acceptable for single-user Solo; a real hazard as
verticals add concurrent editors (dispatcher + technician on the same job).

**C7 — Official numbers are invisible.** The client discards the submit
response's `number` and the replicated envelope's `official_number`
(`sync_engine.dart` submitDocument case updates docstatus only), so the legal
gap-free number exists only server-side while PDFs and screens show the
device-local series (`SINV-2026-0007`) — and *local* series from two offline
devices can collide and LWW-erase an invoice (block-allocator state is
device-local, unsynced). *Fix: persist official_number on apply; print it;
treat local ids as internal drafts.*

**C8 — No credential lifecycle.** User/device/portal/pay tokens never expire;
`devices.revoked_at` exists in schema but **no endpoint sets it** — no member
removal, no role change, no rotation. Client stores both tokens plaintext in
SharedPreferences (acknowledged in code). Stolen desktop credentials =
permanent company access short of DB surgery. *Fix: revocation + expiry
endpoints, member management, platform keychain storage.*

**C9 — Sync pull is unbounded.** No LIMIT server-side, no pagination
parameter; new-device bootstrap of a company with 100k mutations is one JSON
body, client applies row-by-row with no mid-batch cursor persistence (crash =
re-pull everything). Blobs ride Postgres `bytea` under axum's default 2 MB
body cap — accidentally too small for attachments. *Fix: paginated pull with
per-page cursor commit; explicit body-size config; blob size policy.*

**C10 — Local outstanding recompute can poison the sync queue.**
`recomputeOutstanding` issues `applyOnSubmitUpdate` on backend-posted
invoices whenever local settlement view diverges; the sync plane 409s it into
the `failed` quarantine — self-inflicted permanently-failed mutations
requiring manual requeue. *Fix: skip local outstanding writes for documents
carrying an official_number (server maintains them).*

**Also noted (medium/low):** unauthenticated `POST /companies` +
webhook-intake disk-fill (no rate limits anywhere); invitation tokens stored
plaintext (unlike every other credential); audit_log rows missing for
submit/cancel/amend/delete and table is mutable (no hash chain); reports do no
company scoping (multi-company latent trap); `DocumentEngine.fetch()` bypasses
permissions/row access entirely; row-access filtering applied after SQL LIMIT
breaks pagination; CSV formula-injection in the accountant GL export; Stripe
webhook into a locked period → 422 → infinite Stripe retries; sync-push
immutability check is TOCTOU-racy vs concurrent submits.

---

## 9. Conclusions

**1. Does Atlas currently cover most micro-businesses?** Not yet as an
*operational* system. The financial spine (GL, VAT, perpetual inventory,
payments, banking, reporting) is genuinely strong and mostly tested, and it
can *invoice* for almost anyone — but operating coverage is concentrated in
office/desk businesses and goods-selling. Roughly: strong for ~a third of
the sector list, configuration-reachable for another third, and blocked for
the service/appointment/field half of the economy by the absence of
scheduling, jobs, assets, deposits and pricing.

**2. Well-supported today:** freelancers/consultants, agencies and
project-service firms, e-commerce sellers, light manufacturers, simple
retail (minus discounts), wholesalers (minus price lists), event/creative
businesses, accountants' own practices.

**3. Genuinely missing verticals:** Field Service & Trades (V1), Hospitality
POS (V2), Rental & Hire (V3), Repair Workshop/Garage (V4), Property
Management (V5), Construction progress billing (V6), thin
Memberships/Classes (V7). Everything else hypothesised collapses into shared
capabilities, configuration, module completion (courier), or specialist
integrations (healthcare, legal client money, hotels, advanced
manufacturing, agri/fisheries registers).

**4. Smallest set for widest coverage:** five capabilities + two verticals —
**S8 pricing/discounts, S4 deposits, S1 scheduling, S3 photo/signature, S10
fixed assets**, then **V1 Field Service** and **V2 Hospitality POS**, with
the appointments composition pack riding S1/S4/S9 for salons/tutors/studios.
That combination moves ~20 of the 30 sectors into class A/B/C.

**5. Recommended sequence:** Phase 0 hardening (C1–C5 above are
non-negotiable before scale) + S8/S4 → S1/S3 + driver-UX completion → V1 →
V2 → appointments pack → V4/V3/V5 wave with S10/S5/S6 → S13 e-invoicing on
the EU mandate clock. Architecture-wise, build verticals as AppManifest
packages over the existing (genuinely composable) seams with Setup Packs as
their configuration layer — and close the six engine gaps in §6 as you go
rather than up front.

*Evidence limitations:* maturity judgments rest on static analysis and the
test suites, not on runtime QA of every screen; `mercantis_core_ui` widget
behaviour was verified by code reading, not UI testing; fiscal-receipt and
e-invoicing regulatory positions (MT fiscal receipts, ViDA timelines) were
asserted from general knowledge and must be verified against current law
before commercial claims.
