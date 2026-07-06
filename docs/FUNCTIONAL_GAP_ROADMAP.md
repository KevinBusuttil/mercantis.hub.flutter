# Neuradix Atlas (Mercantis Hub/Core) — Functional ERP Gap Audit & Roadmap

> **Status note (2026-07-06):** Sections 9 (MVP scope) and 12 (roadmap) are **superseded by `docs/ROADMAP_V2_SOLO_TEAM.md`**, which encodes the Atlas Solo / Atlas Team edition split, the Atlas Team Rust Backend, the Atlas Setup Library, and the rule-first AI strategy (see also `docs/ATLAS_SOLO_TEAM_BACKEND_DECISION.md`, `docs/STOCK_COGS_IMPLEMENTATION_PLAN.md`, `docs/ATLAS_SETUP_LIBRARY_AND_RULE_FIRST_AI.md`). The audit findings in this document remain the factual baseline. POS wording in §6/§12 has been corrected: POS document and Z-report **foundations** are present, but POS is not accounting-complete for product businesses until stock-to-GL/COGS is implemented.

**Audience:** product owner / founding team
**Perspective:** senior functional ERP consultant, micro-business & very-small-business ERP
**Scope:** `mercantis.hub.flutter` (the product) + `mercantis.core.flutter` (the platform packages)
**Method:** code-level inspection of both repositories (modules, ledger derivation, interceptors, workflows, screens, seeder, tests, parity docs). Findings below are grounded in actual code paths, not menus or metadata declarations. File evidence is confined to Section 15 (Technical Appendix) except where a citation is needed to justify a verdict.
**Date:** 2026-07-06

---

## 1. Executive Summary

Neuradix Atlas is **much more real than a demo, and much less finished than a product**. The verdict in one sentence:

> The accounting/stock **engine underneath is genuine, tested, and reusable — but the product cannot yet take a real micro-business from "send my first invoice" to "trust my profit number," because stock never reaches the general ledger (no COGS), documents cannot be emailed or paid online, banking has no user interface, the three headline financial statements don't exist, and business presets are cosmetic.**

What is genuinely strong (verified in code and covered by ~133 test files across the two repos):

- A real offline-first document engine: submit/cancel/amend lifecycle, optimistic concurrency, audit diffs, attachments, CSV import/export on every list, offline-safe document numbering.
- A real quote-to-cash *conversion* chain: Quotation → Sales Order → Delivery Note / Sales Invoice with line carry-over, remaining-quantity logic, back-links and lineage; credit notes and returns that restock at **original cost**, not selling price.
- A real payments core: guided "Receive payment"/"Pay supplier" screens with FIFO allocation, part payments, multi-invoice allocation, correct GL + AR/AP subledger + settlement postings that maintain invoice outstanding amounts.
- A real stock **subledger**: moving-average and FIFO costing, per-warehouse bins, UOM conversion, negative-stock guard, transfer/return handling, manufacturing backflush.
- A real VAT engine (exclusive pricing), tax transactions, a generic VAT return builder, chart-of-accounts seeding/repair, opening-balance and year-end-close builders, trial balance, AR/AP ageing.
- A genuinely wired receipt-capture pipeline: camera → on-device OCR → heuristic parse → optional LLM extraction (bring-your-own-key) → review screen → draft purchase invoice with the image attached.

What blocks real businesses today — the five product-defining gaps:

1. **Stock is not integrated with the general ledger.** Sales post revenue with **no COGS**; purchases expense **immediately** to COGS; the inventory asset account is never touched. Profit and inventory value in the financial ledger are structurally wrong for any product business. This directly fails the mandatory perpetual-inventory requirement.
2. **You cannot send a document or collect money.** No email sending, no payment links or provider integration, and PDFs render without logo/letterhead (the in-app print action is plain monospace text). Share-sheet PDF is the only delivery channel.
3. **Banking is headless.** The CSV importer, match-suggestion engine and reconciliation logic exist and are unit-tested — but there is **no screen** that calls them, no import persistence/dedup, no bank rules, no create-payment-from-bank-line.
4. **Owners can't see the business.** No Profit & Loss, no Balance Sheet, no Cash Flow, no gross margin (impossible anyway without GL COGS), no cash-position/overdue/VAT dashboard cards. The dashboard shows totals, not "what needs attention today."
5. **Presets and approvals are theatre.** The onboarding preset choice is discarded (its own doc-comment says the flags "have no effect yet"); there is no setup checklist; the approvals inbox in the shipped build is fed by three hard-coded mock entries; every operator is a full "System Manager."

Entirely missing categories: online store / sales channel, projects/jobs/timesheets, recurring invoices/bills, expense claims, multi-user cloud identity (sync is a shared-folder mechanism with no server).

**Recommendation:** do not rebuild — the engine deserves to be kept. Sequence the work as: (Phase 1) make the send-an-invoice-and-get-visibility loop real; (Phase 2) close the stock→GL/COGS gap, which is a well-bounded change to one derivation layer; (Phase 3) surface banking and add payment links; then channels, POS polish, services features. A small service business could be live at the end of Phase 1; a product business at the end of Phase 2–3.

---

## 2. Current Functional Coverage

Classification key: ✅ Implemented and usable · 🟡 Partially implemented · 🎭 Prototype/mock/demo only · ⚙️ Technically present but not business-ready · ❌ Missing

| Functional area | State | One-line verdict |
|---|---|---|
| Customers / suppliers / items (masters) | ✅ | Real DocTypes, editable, importable via CSV on every list |
| CRM (leads, opportunities, contacts) | 🟡 | Good data model + lead→customer/quotation conversion; no pipeline behaviour |
| Quotations | 🟡 | Create/submit/convert works; no Sent/Accepted/Rejected/Expired lifecycle, no expiry automation, no deposits |
| Quote → Order → Invoice conversion | ✅ | Real, lineage-linked, remaining-qty aware, tested |
| Sales invoices & statuses | ✅ | Draft/Unpaid/Partly Paid/Paid/Overdue derived from real data (no "Sent" state) |
| Credit notes / returns | ✅ | Return docs restock at original cost; GL & subledger reversal on cancel |
| Sending documents (email / share / PDF) | 🟡 | PDF via OS share sheet works; **no email**, no letterhead/logo, in-app print action is plain text |
| Payment recording (receive / pay) | ✅ | Guided flows, FIFO allocation, part payments, correct postings |
| Overpayment / customer advances | ❌ | Surplus is silently dropped, never booked as credit |
| Payment links / providers (Stripe etc.) | ❌ | No integration, no abstraction, no webhooks, no fees/clearing/payouts |
| Customer statements / reminders / timeline | ❌ | Balances & overdue lists exist; statement/reminder/dunning absent |
| Recurring invoices / bills | ❌ | Scheduler engine exists in core; no auto-repeat feature built on it |
| Purchase orders / receipts / invoices | ✅ | Full chain with conversions and workflows |
| Expense entry (lightweight) | ❌ | Only path is a full Purchase Invoice; no expense doctype or categories |
| Receipt capture (OCR + LLM) | ✅ | Real end-to-end on mobile; creates draft purchase invoice with image attached |
| Duplicate bill / invoice-number protection | ❌ | "Duplicate" status declared but never set; no supplier-invoice-no uniqueness |
| Expense claims / reimbursements | ❌ | No employee/claim concept |
| Bank accounts / statement import / matching | ⚙️ | Importer + matcher + reconciliation logic real and tested — **zero UI**, no persistence, no dedup |
| Bank rules / create-from-line / splits | ❌ | Not present |
| Stock subledger (qty + value) | ✅ | SLE → Bin, moving average & FIFO, UOM conversion, negative-stock guard |
| **Stock → GL (inventory asset, COGS, GRNI)** | ❌ | **No stock document posts any GL entry; purchases expense straight to COGS** |
| Stock counts / reorder suggestions | 🟡 | Adjustments only via Stock Entry; low-stock list exists, no count sheet or suggested-order qty |
| POS posting document + Z-report | ✅ | Cash sale posts revenue/VAT/cash + stock issue at cost; shift X/Z with variance |
| POS till UI | 🎭 | Cash-only, exact-tender, no receipt/returns/discounts/barcode, opening float hardcoded 0 |
| Manufacturing (BOM / WO / backflush) | 🟡 | Real and tested at stock level; no WIP/GL |
| Deliveries (delivery note + routes) | ✅ | Delivery note moves stock; route/driver overlay is real operational data |
| Online store / sales channel | ❌ | Nothing exists (and no server exists to host webhooks) |
| Projects / jobs / timesheets | ❌ | Nothing exists |
| Trial balance / AR / AP ageing / registers | ✅ | Computed live from the ledger; 14 flat registers |
| **P&L / Balance Sheet / Cash Flow / Gross margin** | ❌ | None exist |
| VAT return | ⚙️ | Real computation from tax transactions; generic 5-box model, no jurisdiction form, no e-filing |
| Owner dashboard | 🟡 | Live receivables/payables/open-orders tiles; no cash, overdue, profit, VAT, month-scoped cards |
| Report export / accountant handover | 🟡 | CSV-to-clipboard of 3 summaries; no journal/GL export, no file/share, no PDF |
| Setup / onboarding seeding | ✅ | CoA, tax bands (MT/UK/IE/generic), fiscal year, company — idempotent, tested |
| Business presets drive the product | 🎭 | Choice is recorded, then discarded; no reader of the preset flags anywhere |
| Guided setup checklist | ❌ | Does not exist |
| Opening balances | ⚙️ | Balanced-journal builder exists and is tested; **no screen invokes it** |
| Invoice numbering configuration | ✅ | Per-doctype series, offline-safe, next-number reset UI (not gap-free by design) |
| Branding / logo / templates | ⚙️ | Logo field stored, never rendered; no letterhead wired; no template editor |
| Users / roles / accountant invite | 🎭 | Device passcode profiles; **everyone is System Manager**; no invite, no backend |
| Approvals | 🎭 | Inbox fed by hard-coded mock rows in the shipped build; workflows gate everything on one role |
| Audit trail | ⚙️ | Field-level diffs written on every save; no read API or UI |
| Sync / multi-device | ⚙️ | Real mutation-log sync over a **shared folder** (iCloud/Dropbox); no cloud service |

---

## 3. What Is Business-Ready

These areas can be trusted and built upon today:

1. **Document engine and masters.** Creating, editing, submitting, cancelling and amending customers, suppliers, items, quotations, orders, invoices, journals works, with optimistic concurrency, per-save audit diffs, attachments on every record and CSV/JSON import/export on every list.
2. **Quote-to-cash conversions.** One-click Quotation→Sales Order→Invoice/Delivery, with line items carried, remaining-quantity logic on partial fulfilment, and bidirectional document lineage. Returns/credit notes exist for sales, purchase and POS documents and restock at original cost.
3. **Money in / money out recording.** Guided receive-payment and pay-supplier flows allocate across open invoices (FIFO, editable), post balanced GL + party subledger + settlement rows, and keep `outstanding_amount` correct — including on cancellation (idempotent reversal postings).
4. **The stock subledger.** Receipts, issues, transfers, manufacturing backflush; moving-average and FIFO valuation computed correctly per (item, warehouse); negative stock blocked unless the company explicitly allows it; UOM conversion applied at posting.
5. **VAT calculation and the tax base.** Tax codes resolve line→item→document→party; postings emit both GL tax legs and `Tax Transaction` rows; a period VAT return (output/input/net + bases) can be prepared from real data; zero-rated bases are captured.
6. **Setup seeding and accounting hygiene tooling.** Idempotent seeding of a starter chart of accounts, jurisdiction tax bands (Malta/UK/Ireland/generic), fiscal year and company defaults; a chart-repair tool; opening-balance and year-end-close builders (both produce balanced draft journals); books-lock-date and group-account posting guards.
7. **Receipt capture.** Photo → on-device ML Kit OCR → robust heuristic parser (EU/US formats) → optional cloud LLM extraction (off by default, quota-limited, bring-your-own-key) → human review → draft purchase invoice with the receipt image attached and merchant→supplier learning.
8. **Trial balance, AR/AP ageing, registers, account ledger drill-down, POS Z-report.** All computed live from the document store.

---

## 4. What Is Partial / Mock / Demo

| Item | Reality |
|---|---|
| **Business presets** | Four presets are shown at onboarding and promise "adds the POS till / adds BOMs" — the selection is never passed to the seeder and the enable-flags have no readers. All presets produce an identical product. |
| **Approvals inbox** | The shipped build wires the inbox to three fabricated entries ("SO-0142 — ACME Ltd", "PINV-77 — Apex Supplies"…). A real metadata-driven source exists in the code, one line away from being wired. Tiles have no approve/reject action; "approval" is a single-role Submit. |
| **POS till** | The posting document is production-grade; the till screen is a cash-only prototype: exact-tender hardcoded, no card/split, change always €0, no receipt output, no returns/discounts/barcode, opening float hardcoded to 0, no cashier identity. |
| **Banking** | Importer/matcher/reconciliation are tested pure logic invoked **only from tests**. No screen, no route, no workspace entry surfaces bank accounts, import or matching. |
| **Opening balances** | Complete, tested builder; no UI caller — a business cannot enter opening balances from the running app. |
| **Branding / print** | Core has a real PDF renderer with letterhead support; the hub registers no letterhead, never renders the stored company logo, and its in-app "Print" action shows monospace plain text. |
| **Multi-company** | Data model supports it; onboarding creates exactly one and there is no company switcher. |
| **Roles / permissions** | A genuinely granular permission engine (doctype/field/row/action) exists in core — the hub feeds it a single "System Manager" identity for every operator, so it is effectively unused. |
| **Audit trail** | Written faithfully on every save; unreadable — no list/read API, no history UI. |
| **VAT return** | Real numbers, generic 5-box layout; not any jurisdiction's actual form; filing fields are manual. |
| **Report builder** | Engine supports multi-group/multi-aggregate/filters/saved reports; the hub UI exposes one group-by, one aggregate, and cannot save. |
| **Dashboards** | Home tiles are live but coarse (all-time sums, drafts included in some KPIs); three workspace dashboard links are dead routes; KPI cards for cash/overdue/profit/VAT/month don't exist. |
| **Sync / multi-user** | Real mutation-log sync — over a user-managed shared folder. No server, no accounts, no invitations. Fine as offline/local-first; not "multi-user" in the product sense. |
| **Quotation lifecycle** | Internal Ordered/Lost model only; `valid_till` is a dead field (nothing expires quotes); no customer-facing accept/reject; no deposits. |

---

## 5. Critical Functional Gaps

Ranked by how directly they block a paying micro-business customer:

1. **No COGS / no inventory asset in the GL** (fails the mandatory requirement — full analysis in Section 7). Every product business gets a wrong P&L and a zero inventory asset.
2. **No email sending and no payment links.** "Send invoice → get paid" — the single most important micro-business loop — currently requires the OS share sheet and a manual bank transfer, with an unbranded PDF.
3. **No P&L / Balance Sheet / Cash Flow / VAT dashboard.** The owner questions ("am I profitable? what's my cash? what's my VAT exposure?") cannot be answered from the app.
4. **Banking invisible.** Import/match/reconcile logic exists but no user can reach it; no bank rules; no create-expense/payment-from-line; no dedup on re-import.
5. **Presets cosmetic + no setup checklist.** First-run experience promises differentiation it doesn't deliver, and never tells the user whether they can safely start invoicing.
6. **No customer statements or payment reminders.** Chasing money — the second most important loop — has no support beyond an overdue list.
7. **No recurring invoices** despite a working scheduler engine — blocks every retainer/subscription-style service business.
8. **No lightweight expense entry, no duplicate-bill protection.** Real risk of double-paying suppliers; every coffee receipt requires a full purchase invoice (capture mitigates this partially).
9. **Single-role security.** Every operator is a super-user; no owner/staff/accountant separation; workflow transitions unattributed ("system"); approvals mock.
10. **Accounting guardrails missing:** manual journal entries are not checked for debit=credit balance before posting; no enforced period lock (books-lock-date guard exists but no period-close workflow); audit trail invisible.
11. **No tax-inclusive pricing.** Retail (and most consumer-facing pricing) needs VAT-inclusive amounts; the engine only computes tax-exclusive.
12. **Online store, projects/timesheets: absent** (acceptable for now — see Sections 8 and 12 for sequencing).

---

## 6. Micro-Business User Journey Assessment

**Owner-manager** — *"How much money is coming in, who owes me, am I profitable, is VAT under control?"*
🟡→❌ Can see total receivables/payables and open orders live. Cannot see cash position, overdue-specific totals, month sales, profit (no P&L), or a VAT estimate. Verdict: **dashboard exists; answers don't.**

**Sales/admin user** — *"Create quote → convert → send → follow up → record payment."*
🟡 Create quote ✅, convert ✅, record payment ✅ (genuinely good). Send = share-sheet PDF without branding; no email, no reminder, no statement, no quote acceptance. Verdict: **can operate internally; can't communicate professionally.**

**Stock/product user** — *"Know stock, receive, count, sell, reorder, see margin."*
🟡→❌ Availability ✅ (bins), receive ✅ (purchase receipt), sell ✅ (delivery note/POS reduces stock at cost). Counting: no count-sheet workflow (adjustments only via raw Stock Entry). Reorder: low-stock list only, no suggestions. **Margin: impossible — COGS never reaches the P&L.** Verdict: **quantities trustworthy, money not.**

**Retail/POS user** — *"Open till → sell fast → mixed tenders → receipt → close and reconcile cash."*
🎭 Open session (no float entry), sell via a dropdown (no grid/barcode), cash-exact only, no receipt, no returns, close with Z-report ✅ (variance math is right but float=0 undermines it). Verdict: **not usable for a real counter yet — and not accounting-complete either: POS document and Z-report foundations are present (revenue/VAT/cash posting, stock issue at cost), but POS sales post no COGS or Inventory Asset movement to the GL until the stock-to-GL work lands.**

**Service business user** — *"Quote work, track jobs and time, recurring invoices, project profit."*
❌ Quote→invoice works; jobs/time/retainers/recurring/profitability all absent. Verdict: **usable only as an invoicing tool.**

**Bookkeeper/accountant** — *"Review, reconcile, adjust, report, export."*
🟡→❌ Journal entries ✅ (but unbalanced ones can post), account ledger with drill-down ✅, trial balance/ageing ✅, year-end close draft ✅, VAT return numbers ✅. Bank reconciliation unreachable; no P&L/BS; export = 3 CSVs to clipboard; no journal/GL file export; no role or invite; audit trail invisible. Verdict: **an accountant could inspect it over the owner's shoulder, not work in it.**

---

## 7. Stock and COGS Assessment

This was audited against the mandatory requirement: *perpetual inventory accounting; stock must register COGS.*

### What exists and is correct

- **Item classification:** stock vs service item is a real, enforced distinction; service lines are filtered out of every stock path.
- **Valuation:** moving average (default) and FIFO both implemented as pure, tested functions; issue cost always comes from valuation history, never the selling price; FIFO shortfall falls back to moving average.
- **Stock subledger:** append-only Stock Ledger Entries feed per-warehouse Bins (qty, valuation rate, stock value); reversal on cancel and return re-costing at original issue cost are implemented and tested; negative stock blocked unless a company-level setting allows it; UOM conversions applied.
- **Document flows:** Purchase Receipt (stock in), Delivery Note & POS Invoice (stock out), Stock Entry (issue/receipt/transfer/manufacture/repack), returns for all of them.

### The defect

**No stock movement generates a GL posting.** The derivation layer emits Stock Ledger Entries only; there is no `Dr COGS / Cr Inventory Asset` anywhere in either repo, no posting to the seeded "Stock In Hand" account, and no GRNI account flow. Worse, the **Purchase Invoice's expense account defaults to COGS**, so goods are fully expensed on purchase. The system is a *periodic* inventory model in the GL silently coupled to a *perpetual* model in the stock subledger — and the two never reconcile because one side is always zero. (A code comment claims stock vouchers "post COGS/inventory at moving-average cost"; they do not — a trap for future developers.)

**Acceptance test replay (buy 10 @ €5, sell 3 @ €12):**

| Check | Subledger | General ledger |
|---|---|---|
| Stock qty = 7 | ✅ (via Purchase Receipt + Delivery Note) | n/a |
| Inventory value = €35 | ✅ on the Bin | ❌ Stock account = €0 |
| Sales revenue = €36 | — | ✅ |
| COGS = €15 | ✅ implicit in Bin value reduction | ❌ COGS = **€50** (whole purchase expensed) if bought via Purchase Invoice |
| Gross profit = €21 | not reported | ❌ shows −€14 or requires period-end adjustment |
| Service item → no stock/COGS | ✅ | ✅ (trivially, since nothing posts) |
| Cancel/return reversal | ✅ stock + revenue/VAT | ❌ no COGS to reverse |

### Why this is very fixable

All postings flow through **one derivation layer** (`LedgerDerivation` + `LedgerDerivationService`), which already: computes the correct issue cost per line, owns idempotent/reversible posting IDs, handles returns at original cost, and is well tested. The change is additive: emit GL legs alongside the SLEs it already emits, add item-level inventory/COGS/adjustment account resolution (with company fallbacks, a pattern that already exists), and change the purchase side to post `Dr Inventory / Cr AP` for stock items (with a GRNI account once Receipt and Invoice are decoupled in accounting terms). The account-type vocabulary ("Stock", "Stock Adjustment", "Asset Received But Not Billed") is already defined but unused.

**Recommended functional decisions** (consistent with the requirement):

- Default valuation: **moving average** (already the default); keep FIFO as the advanced option (already built).
- Negative stock: **blocked by default** (already the behaviour); keep the company-level override as the "advanced" setting.
- MVP simplification: let **Purchase Invoice optionally receive stock** ("update stock" flag) so micro-businesses don't need the two-document Receipt+Invoice dance; keep Receipt→Invoice with GRNI as the grown-up path.
- Similarly, let **Sales Invoice optionally issue stock** for businesses that don't do delivery notes.
- Add a **Stock ↔ GL reconciliation report** (sum of Bin values vs Inventory account balance) as the trust check.

---

## 8. Online Store / Sales Channel Assessment

**Current state: nothing exists.** No connector, no channel entities, no webhook handling — and structurally, **there is no server anywhere in the architecture** (sync is a shared-folder mechanism), so there is nothing to receive a Shopify/WooCommerce webhook even if a connector UI existed.

Implications for the recommended generic sales-channel layer:

- A **polling-based connector** (app calls the store's REST API on demand/schedule) fits the current serverless architecture and is how the MVP should start. WooCommerce and Shopify both support polled order/product APIs. A **manual CSV order-import channel** is nearly free given the existing importer, and is a legitimate first "channel."
- A **webhook-based, real-time** integration requires the cloud backend decision (Section 14) to be made first.
- The building blocks that make import feasible already exist: items with SKU/barcode, customers, sales orders/invoices, payment entries, stock reduction via delivery/POS documents, and (after Phase 2) COGS.
- The accounting the requirement calls for (provider clearing account, fees, payout reconciliation) is the same machinery Phase 3 builds for payment providers — design them together.

Verdict: **defer to Phase 4, design the channel entities generically, start with CSV + one polled connector (WooCommerce recommended: simplest auth, self-hosted customers overlap with micro-business segment).**

---

## 9. Recommended MVP Scope

Smallest commercially useful product. "Build" = new; "Wire" = logic exists, needs UI/integration; "Have" = exists today.

| # | Capability | Status today | MVP action |
|---|---|---|---|
| 1 | Functional business presets | 🎭 cosmetic | **Build** (small): make preset flags drive workspace visibility, seeded defaults, dashboard layout |
| 2 | Guided setup checklist | ❌ | **Build**: preset-adaptive checklist with "can I invoice yet?" states |
| 3 | Customers/suppliers/items + import | ✅ | Have |
| 4 | Quotations (with Sent/Accepted/Expired + expiry) | 🟡 | **Extend** statuses + expiry automation; defer acceptance links |
| 5 | Sales invoices + statuses | ✅ | Have |
| 6 | Send by email + branded PDF + share | 🟡 | **Build** email send; **Wire** letterhead/logo into existing PDF renderer |
| 7 | Payment recording | ✅ | Have (add overpayment→customer advance) |
| 8 | Customer statements + reminders | ❌ | **Build** (statement = filtered ledger + PDF; reminder = templated resend) |
| 9 | Expenses + supplier bills | 🟡 | Have bills + capture; **Build** lightweight expense entry + duplicate-bill warning |
| 10 | Bank import + manual reconciliation | ⚙️ | **Wire** existing importer/matcher into screens; add import dedup + create-from-line |
| 11 | Stock with COGS | ❌ GL side | **Build** stock→GL posting (Section 7) — the defining MVP investment |
| 12 | Owner dashboard (cash, overdue, month sales, profit, VAT) | 🟡 | **Build** 5 cards on existing dashboard engine |
| 13 | Reports: P&L, Aged AR/AP, VAT summary, Stock valuation, Gross margin | 🟡 | Have ageing; **Build** P&L + gross margin (unblocked by #11); **Wire** VAT summary into reports list; total the stock valuation |

Explicitly **out of MVP**: online store, POS till completion, projects/timesheets, recurring invoices (first candidate after MVP), payment providers (manual bank transfer + reference is enough to start), multi-user cloud backend (single-device/folder-sync acceptable for first customers, but decide the backend now — Section 14).

---

## 10. Detailed Functional Requirements by Module

### 10.1 Presets & setup
- Preset selection must persist and drive: visible workspaces (hide POS/Manufacturing/Deliveries/Stock per preset), setup checklist contents, dashboard card set, and default settings (e.g. stock enabled off for Services). Mixed preset = start minimal, enable modules from settings (toggles already exist for POS/Manufacturing/Deliveries — extend to Stock and Banking).
- Setup checklist items (adaptive): company profile, jurisdiction, currency, fiscal year, VAT setup, chart review, numbering, logo/branding, templates check, customer/supplier/item import, opening balances, bank account, payment methods, stock settings*, POS setup*, invite accountant†, first document. (*conditional on preset; †deferred until multi-user.) Each item: Done / To do / Not applicable, with deep link. Banner answers "You can safely send your first invoice" when the minimum set is green.
- Opening balances: a screen over the existing builder (accounts + AR/AP per party + stock opening via valuation-bearing Stock Entry).

### 10.2 Selling
- Quotation: add derived statuses Sent / Accepted / Rejected / Expired / Converted; auto-expire past `valid_till`; "Mark accepted/rejected" actions; optional deposit request (percentage → generates a deposit invoice or payment request). 
- Invoice: "Sent" tracking (set on email/share), payment reminder action (resend PDF + message template), attachment already supported.
- Customer statement: per-customer document list (invoices, credit notes, payments) with running balance over a date range, printable/shareable PDF.
- Overpayment: book surplus as customer advance (credit) applicable to future invoices.
- Recurring invoice (fast follow after MVP): template + frequency + next date + auto-draft via the existing scheduler; auto-send only if enabled; failure visibility.

### 10.3 Buying & expenses
- Expense: lightweight doctype (date, supplier-optional, category=expense account, net/VAT/gross, paid-from account or unpaid flag, attachment) posting a simple journal; capture pipeline should optionally target Expense instead of Purchase Invoice for receipt-type documents.
- Duplicate protection: warn on same supplier + same supplier_invoice_no (and capture-side near-duplicate detection: same supplier+date+amount).
- Bills-due dashboard card scoped by due date.

### 10.4 Payments & banking
- Wire the banking module: bank account list/setup screen; CSV import screen (file picker → preview → commit with `import_batch` dedup); match workbench (suggestions with confidence, accept/reject); create Payment Entry or Expense from an unmatched line; split a line; reconciliation summary (bank vs book, unreconciled count).
- Bank rules: contains/amount/direction → suggested account/party/tax, optional auto-create expense/transfer, auto-match above a confidence threshold.
- Payment links (Phase 3): provider abstraction (create link, query status, record event), Stripe first, fees to a provider-fee account via a clearing account, payout matching against bank lines. Manual bank transfer with reference remains the zero-integration default.

### 10.5 Stock & COGS
As Section 7: item-level inventory/COGS/adjustment accounts with company fallbacks; GL legs emitted with the existing SLEs; purchase side to inventory (GRNI when receipt≠invoice); update-stock flags on Purchase/Sales Invoice for one-document businesses; stock count sheet (snapshot → count → post adjustment); reorder suggestions (reorder level vs bin + suggested qty); stock valuation total report; stock↔GL reconciliation report; gross margin by item/customer reports.
- Tax-inclusive pricing support (retail prerequisite).

### 10.6 POS
Complete the till against the existing posting engine: opening float entry; item search + barcode + favourites grid; card and mixed tenders with change; receipt print/share (80mm format + share sheet); returns via existing `is_return` path; line/total discounts; cashier attribution (operator on session and invoice); suspended sale (park/recall); POS Profile seeded by Retail preset.

### 10.7 Online store (Phase 4)
Generic entities: Sales Channel, Channel Product (SKU map), Channel Order (+items), Channel Payment, Channel Fulfilment, Sync Log. CSV channel first, then WooCommerce polling. Orders → Sales Order/Invoice + stock + COGS; payments → clearing account; fees at payout reconciliation; sync errors visible and re-runnable.

### 10.8 Services (Phase 6)
Project/Job (customer, status, budget), Task, Timesheet (billable flag, rate), billable expense (link expense→project→invoice), quote→project conversion, project invoicing (from time+expenses), retainer = recurring invoice + drawdown view, project profitability (invoiced − time cost − expenses).

### 10.9 Reporting & accountant
- P&L (period, from GL by root type), Balance Sheet (as-of), simple cash-flow overview (cash/bank account movements categorised), month-scoped dashboard cards (cash position, overdue total, bills due, sales this month, profit estimate, VAT estimate), low-stock card.
- VAT summary in the Reports list (reuse return builder), jurisdiction box-mapping layer later (UK 9-box first if UK market matters).
- Accountant export v2: date-ranged GL/journal CSV export to file/share (not clipboard); audit-trail viewer over the existing `audit_log`.
- Report export: CSV to file/share everywhere; PDF for statements/ageing.

### 10.10 Roles & permissions
Define seven role profiles (Owner/Admin, Sales, Purchasing, Stock, POS, Accountant, Read-only) as permission-rule sets over the **existing** core permission engine; role picker in operator setup; gate workflows/workspaces by role; attribute workflow transitions to the acting operator (fix the hard-coded "system" user). Cloud identity/invites arrive with the backend decision.

---

## 11. Acceptance Criteria by Module

**Presets/setup:** selecting Services on a fresh install shows no Stock/POS/Manufacturing surfaces anywhere; checklist shows accurate Done/To-do; "safe to invoice" banner appears only when company+VAT+numbering+one-customer+one-item are done; re-running setup never duplicates seeded data (already true — must stay true).

**Selling:** user creates and emails a branded PDF quote without touching accounting screens; marking accepted then converting produces an invoice with identical lines; emailing an invoice flips it to Sent; the dashboard overdue card count equals the overdue report; statement PDF for any customer reconciles to their outstanding balance; overpaid receipt leaves a visible customer credit, not vanished cash.

**Buying/expenses:** photographing a receipt yields a reviewable expense in ≤3 taps after capture; entering the same supplier invoice number twice warns before save; bills-due card shows only bills due within the horizon; expenses appear in P&L and the VAT input box.

**Banking:** importing the same CSV twice creates zero duplicate lines; ≥80% of exact-amount/date-window payments get a correct suggestion; an unmatched bank fee becomes an Expense in one action from the line; reconciliation screen shows bank vs book difference of €0.00 after full matching.

**Stock/COGS (the mandatory test):** buy 10 @ €5 → GL Inventory +€50 (via invoice-receives-stock or receipt+GRNI); sell 3 @ €12 → Revenue €36, **GL COGS €15**, GL Inventory −€15; Bin says 7/€35 **and Inventory account says €35**; the reconciliation report shows €0 difference; service invoice posts no stock/COGS; cancel and return each reverse both sides; gross margin report shows €21.

**POS:** open with €100 float, trade cash+card+mixed, print/share receipts, process one return, close: expected vs counted cash with variance posted; the day's sales appear in revenue, VAT, stock and COGS; Z-report totals equal the sales register for the session.

**Reports:** P&L for a period equals trial-balance-derived income−expense for the same period; balance sheet balances; every owner card answers its question without opening a report; accountant receives a file (not a clipboard) containing the full journal for a date range.

**Roles:** a Sales operator cannot open journals, settings or GL; a POS operator sees only the till; an Accountant sees reports/GL/journals but not settings; every workflow transition records who did it.

---

## 12. Recommended Implementation Roadmap

**Phase 0 — Audit (this document).** Key reuse decisions: keep the core engine and the entire ledger-derivation spine; keep conversions, guided payments, capture, seeder, banking logic; redesign nothing wholesale. De-mock, wire, and extend.

**Phase 1 — First real businesses (invoice-and-visibility loop).**
Presets made functional + setup checklist; letterhead/logo into the PDF path (kill the plain-text print action); email sending; quotation lifecycle statuses + expiry; customer statements + reminders; overpayment→advance; lightweight Expense + duplicate-bill warning; opening-balances screen; owner dashboard cards (cash, overdue, bills due, month sales, VAT estimate); P&L report; swap the approvals inbox to the real source (one line) or hide it; JE balance guard. *Outcome: a service or simple product business can set up, send branded invoices, chase money, and see profit.*

**Phase 2 — Stock & COGS foundation.**
Item accounts; GL legs from stock movements; purchase-to-inventory + GRNI; update-stock flags; stock count sheet; valuation/margin/reconciliation reports; tax-inclusive pricing; reorder suggestions. *Outcome: product businesses get correct COGS, margin, and an inventory asset that reconciles.*

**Phase 3 — Payments & banking.**
Banking UI over existing logic (import, match workbench, create-from-line, splits, reconciliation view); bank rules; payment links via provider abstraction (Stripe first) with fees/clearing/payout matching. *Outcome: collect payments, reconcile the bank.*

**Phase 4 — Sales channel MVP.**
Generic channel entities; CSV order channel; WooCommerce polling connector; SKU mapping; payment/fee reconciliation via Phase-3 clearing machinery; sync log. *Depends on the backend decision if real-time is wanted; polling works serverless.*

**Phase 5 — POS completion.** Float entry, barcode/search grid, card/mixed tender, receipts, returns, discounts, cashier attribution, suspended sales, offline crash recovery of the cart. (POS document and Z-report foundations are already in place, but POS is only accounting-complete for product businesses once Phase 2's stock-to-GL/COGS work has landed — both are prerequisites of this phase.)

**Phase 6 — Service business.** Projects/tasks/timesheets/billable expenses; recurring invoices (may be pulled earlier — it is small and high-value); retainers; project profitability.

**Phase 7 — Accountant & trust.** Role profiles over the existing permission engine; transition attribution; audit-trail viewer; period lock/close workflow; jurisdiction VAT forms; GL/journal file export; balance sheet + cash flow; review queue (real approvals with role routing).

Sequencing rationale: Phase 1 is entirely UI/wiring on proven logic (fast, low risk, immediately sellable). Phase 2 is the single deepest change and gates margin reporting, POS correctness and channel accounting — do it before widening surface area. Phases 3–5 each unlock a preset persona. Recurring invoices are the one item worth pulling forward opportunistically.

---

## 13. Risks and Dependencies

1. **Stock→GL migration for existing data.** Once COGS posting ships, existing databases have stock value with no GL counterpart. Ship a one-time "inventory take-on" journal (Dr Inventory / Cr Opening Equity from Bin values) as part of the upgrade, plus the reconciliation report to prove it.
2. **Purchase double-counting during transition.** Today Purchase Invoice→COGS and Purchase Receipt→stock coexist without linkage. The Phase 2 design must define which document carries value (update-stock flag vs GRNI) and guard against booking both.
3. **Misleading in-code comment** claiming stock vouchers already post COGS — correct it before Phase 2 work starts, or it will misdirect implementers.
4. **No JE balance guard / no period lock** — accounting-integrity risks that get worse as real businesses accumulate data; both are cheap interceptors; do them in Phase 1.
5. **Mock approvals in the shipped build** — reputational risk in any demo-to-real transition; the real source exists; swap or hide immediately.
6. **The backend question shadows everything social:** multi-user, accountant invite, payment webhooks, real-time store sync, payment-link status all require a server the architecture deliberately lacks. Polling and folder-sync postpone it, but Phases 3–4 will force the decision — make it early (Section 14).
7. **Numbering is not gap-free by design** (offline block allocation). Several EU jurisdictions expect sequential invoice numbers; assess per target market; a "single-device strict-sequential" mode may be needed.
8. **Tax-inclusive pricing** touches the tax interceptor, totals and POS — schedule inside Phase 2, before POS completion.
9. **Security items:** LLM API key stored in plain SharedPreferences (move to keychain/secure storage); every operator is a super-user until Phase 7 roles land.
10. **Platform seam:** hub pins core by git ref; at least one feature (work-order auto-post) historically waited on a ref bump — keep the pin fresh as core changes land.
11. **Test discipline is a strength — protect it.** The ledger spine is well tested; every Phase 2 posting change must extend `ledger_derivation`/valuation tests, including the Section 11 acceptance scenario as an automated test.

---

## 14. Questions / Decisions Needed

1. ~~**Cloud backend strategy** (the big one): stay serverless (folder sync, polling connectors, no invites) for how long?~~ **DECIDED (2026-07-06):** two editions — Atlas Solo stays local-first/serverless; Atlas Team adds a Rust-first Linux coordination backend (PostgreSQL authority, local-first client retained). The serverless/relay alternatives listed here previously are superseded — see `docs/ATLAS_SOLO_TEAM_BACKEND_DECISION.md` and `docs/ROADMAP_V2_SOLO_TEAM.md`.
2. **Target jurisdictions for launch** — determines VAT form mapping (Malta? UK MTD? Ireland?), gap-free numbering requirements, and e-invoicing roadmap (EU e-invoicing mandates are approaching — worth a position).
3. **Email delivery mechanism:** on-device `mailto`/share (zero infra, poor tracking) vs SMTP per customer vs transactional email service (needs backend). Affects "Sent" status reliability and reminders.
4. **Payment provider order:** Stripe first (recommended: links API, broad EU coverage) — confirm against target market (Revolut Business popular in Malta).
5. **First store connector:** WooCommerce (polling-friendly, micro-business overlap) vs Shopify (bigger market, webhook-oriented). CSV channel ships first regardless.
6. **POS hardware ambitions:** share-sheet receipts only, or ESC/POS thermal printer + cash drawer support? Determines Phase 5 scope.
7. **Positioning of Manufacturing/Deliveries:** both are unusually far along for this segment — keep behind presets as differentiators, or de-emphasise to focus the product?
8. **Pull recurring invoices into Phase 1/2?** Small effort (scheduler exists), high demand from service businesses.
9. **Amendment/cancellation policy per jurisdiction:** cancel-and-amend exists technically; some jurisdictions require credit notes instead of cancellations for issued invoices — needs a product rule.

---

## 15. Technical Appendix

Where functionality lives, where the mocks are, and where to start. Paths are repo-relative; `hub` = `mercantis.hub.flutter`, `core` = `mercantis.core.flutter/packages/mercantis_core[,_ui]`.

### 15.1 The posting spine (start here for Phase 2)
- `hub lib/ledger/ledger_derivation.dart` — all GL/subledger/stock derivation rules. `_salesInvoice` (:129) posts AR/revenue/VAT with **no COGS leg**; `_purchaseInvoice` (:180) posts expense (defaulting to COGS via company `default_expense_account`) with no inventory leg; `_stockDocument` (:512) and `_stockEntry` (:468) emit **Stock Ledger Entries only**. Header comment at :43–45 wrongly claims COGS/inventory posting. `stockSources` (:38) lists stock-moving doctypes (Purchase Receipt, Delivery Note, POS Invoice, Stock Entry — Sales/Purchase Invoice excluded).
- `hub lib/ledger/ledger_derivation_service.dart` — event-driven runtime: costs issues via `_costStockMovements` (:202), returns at original cost `_returnCost` (:260), idempotent reversals (:126), Bin recompute (:355+), settlement-driven outstanding amounts (:308).
- `hub lib/ledger/stock_costing.dart`, `stock_balance.dart` — moving average + FIFO, tested in `test/stock_costing_test.dart`, `ledger_valuation_test.dart` (assert SLE rates only — no GL COGS test exists, confirming the feature is unbuilt, not regressed).
- `hub lib/ledger/hub_interceptors.dart` — totals/tax/negative-stock/books-lock/group-account guards. **No JE balance guard** (chain at :14–25). Negative-stock guard :419–476.
- `core src/posting/posting_batch.dart` — idempotent posting-batch primitive; not yet used by the hub's derivation service.

### 15.2 Mocks / demo remnants
- `hub lib/mock/mock_data.dart` — only remaining mock: `approvals()`. Wired into the **production** ProviderScope at `lib/main.dart:17` via `mockApprovalInboxSourceOverride`; the real `metadataApprovalInboxSourceOverride` sits unused in `lib/navigation/hub_navigation.dart:36–51`. One-line swap.
- `hub lib/onboarding/business_preset.dart` — presets with `enablesPos/enablesDeliveries/enablesManufacturing`; doc-comment admits flags "have no effect yet"; `onboarding_screen.dart` collects `_preset` and never passes it to `HubSeeder.seed()` (:37–58). No reader of the flags exists.
- Dead routes: `sales-dashboard`, `stock-dashboard`, `finance-dashboard` links in `reports_workspace.dart` are not registered in `hub_navigation.dart`.

### 15.3 Built-but-unwired (highest ROI wiring targets)
- **Banking:** `hub lib/modules/banking/bank_statement_csv_importer.dart` (multi-format parser), `bank_matcher.dart` (scored matching), `bank_matching_service.dart` (suggest/apply/reconcile/ledgerBalance) — all invoked **only from tests**; no screen, route or workspace entry; parsed lines are never persisted; `import_batch` field unused.
- **Opening balances:** `hub lib/modules/accounting/opening_balance_builder.dart` — tested, no caller.
- **Branded PDF:** `core src/printing/pdf_print_renderer.dart` + `LetterHead` support + `core_ui PrintRecordButton` (share/print PDF, mounted on every record) — hub registers no letterhead and never renders `Company.company_logo`; hub's own `lib/printing/hub_print_actions.dart` renders plain text only.
- **Saved reports:** `core src/reporting/saved_report_engine.dart` supports multi-group/aggregate/filters/persistence; hub `report_builder_screen.dart` exposes one group/one aggregate, no save.
- **Permissions:** `core src/permissions/permission_engine.dart` (doctype/field/row/action granularity) — hub supplies only `System Manager` (`lib/auth/auth_store.dart:114,209`).
- **Audit trail:** written by `core src/document_engine/document_engine.dart:197–217`; no read API/UI.
- **Scheduler:** `core src/scheduling/scheduler_service.dart` (interval+cron) — no recurring-document feature uses it.

### 15.4 Solid subsystems to build on
- Conversions/lineage: `hub lib/modules/selling/hub_document_conversion.dart`, `hub_conversion_actions.dart`, `hub_document_lineage.dart` (+4 test files).
- Payments: `hub lib/payments/guided_payment.dart` + `guided_payment_screen.dart`; Payment Entry doctype in `modules/accounting/accounting_module.dart:103–161`.
- Capture: `hub lib/capture/*` — ML Kit OCR, `receipt_parser.dart`, `llm_receipt_extractor.dart` (real Anthropic/OpenAI-compatible HTTP, BYOK, off by default; **key stored in SharedPreferences — move to secure storage**), `capture_service.dart` (creates draft Purchase Invoice; "Duplicate" status declared in `capture_module.dart:21` but never set).
- Seeder/CoA: `hub lib/onboarding/hub_seeder.dart` (idempotent; MT/UK/IE/generic tax bands), `modules/accounting/coa_repair.dart`, `year_end_close_*`, `tax_return_builder.dart`.
- Reports/dashboards: `hub lib/manifest/hub_reports.dart` (16 reports), `lib/reports/aggregating_reports.dart` (trial balance, AR/AP ageing), `hub_dashboards.dart` + `dashboard_engine` (live tiles; `_sum` ignores docstatus — draft/cancelled leakage in some KPIs).
- POS: `hub lib/payments/pos_checkout.dart` (multi-tender math, tested), `modules/pos/pos_shift_report.dart` (X/Z + variance); till prototype `screens/pos_till_screen.dart` (cash-only :184, float hardcoded 0 :81–89).
- Manufacturing: `hub lib/modules/manufacturing/*` + `lib/manufacturing/manufacturing_service.dart` (plan→WO explosion, completion backflush; stock-only).
- Workflows: `hub lib/workflows/hub_workflows.dart` — 15 state machines, all transitions `System Manager`-gated (:6 admits it); core `workflow_engine.dart` logs `user_id: 'system'` (:202) and passes empty user context to guards (:148).
- Sync: `core src/sync_engine/*` — real mutation-log sync; only `NoOpCloudAdapter` and `FileSystemCloudAdapter` ("There is no central server"); hub `lib/sync/company_sync.dart`.
- Numbering: `core src/naming/counter_block_allocator.dart` — per-device block reservation, deliberately not gap-free (:8–11).

### 15.5 Key technical risks for implementers
1. Correct the false COGS comment in `ledger_derivation.dart:43–45` before Phase 2.
2. Phase 2 data migration: take-on journal from Bin values; decide update-stock vs GRNI to avoid Receipt+Invoice double counting (Purchase Invoice currently expenses to COGS via `accountFallbacks` :66–68 → seeded `COGS`).
3. Add a JE balance interceptor and period-close guard early — cheap, prevents corrupt books.
4. Dashboard `_sum` should filter `docStatus == 1`.
5. Tax engine is exclusive-only (`hub_tax_engine.dart:67`); inclusive pricing touches interceptor + POS + print.
6. Hub pins core by git ref — event-emission seams (e.g. work-order auto-post) depend on keeping the pin current.
7. Test the Section 11 COGS acceptance scenario as an automated ledger test the day Phase 2 starts.
