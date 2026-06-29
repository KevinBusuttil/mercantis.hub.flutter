# macOS → Flutter Parity: Authoritative Gap Analysis & Implementation Plan

> **Status:** authoritative. Supersedes the optimistic `PARITY.md` trackers in
> both Flutter repos for the purpose of closing the gap with the Swift/SwiftUI
> macOS apps.
> **Scope:** all four repos — `mercantis.core.app` / `mercantis.hub.app` (Swift,
> source of truth) vs `mercantis.core.flutter` / `mercantis.hub.flutter` (port).
> **This file is committed identically to both Flutter repos** so it is
> discoverable from either side; the implementation plan is split by repo below.

---

## 1. Executive summary

The Flutter port is **not partially behind — it is a coherent snapshot frozen in
time.** Both Flutter repos last merged work on **2026-06-11/12**. The Swift macOS
apps continued through **2026-06-29**, adding ~18 days of development across
roughly 100 commits. **None of that delta has been ported.**

That delta is two intertwined waves:

- **Business-logic wave** (caught by the first analysis): Banking, the
  "Accounting Autopilot" compliance suite, multi-currency, document conversion,
  FIFO valuation, returns, plus the core `ExecutionContext` / `PostingBatch`
  substrate.
- **UI/UX wave** (initially under-weighted): the **Tree view**, **Data Browser**,
  the **form-UX layer** (help text, inline validation, prerequisite nudges,
  inline create), the **Glossary**, the **visual report builder**, the **no-code
  print designer**, the **⌘K command palette / sidebar upgrade**, the
  **conversion-lineage inspector**, **POS shift reports**, **Owner/Accountant
  mode**, and a **full product rebrand to "Neuradix Atlas."**

The existing `PARITY.md` files predate this wave; they both **omit** the new
features entirely and, in a few spots, are stale (they list UI widgets as missing
that have since been built). Treat this document as the source of truth.

### Headline parity gates (Definition of Done)

A repo reaches parity when, against the Swift macOS app of the same date:

1. Every Swift DocType has a Flutter equivalent and every workflow is bound.
2. The ledger spine is correct under the new substrate (ExecutionContext +
   PostingBatch + UnitOfWork) with idempotency, reversal, and recovery.
3. Every Swift screen/view has a Flutter equivalent or an explicit, signed-off
   deferral.
4. No screen is backed by mock data.

---

## 2. Method & evidence base

- Compared module/DocType/view inventories file-by-file across the four repos.
- Reconstructed the **2026-06-12 → 2026-06-29 Swift delta** from
  `git log`/`git diff --stat` on both Swift repos (the Swift Hub repo's history
  is itself a 2026-06-26 re-baseline, so its *entire* current feature set
  postdates the Flutter Hub snapshot).
- Verified each suspected gap by grepping the Flutter trees for a real
  implementation (not just a data-model trace or an engine stub).
- Sized each item by the Swift source line count as a porting proxy.

Severity: **High** = blocks ERP correctness or a primary user task ·
**Medium** = significant missing capability with a workaround ·
**Low** = cosmetic / convenience.
Effort (T-shirt, one engineer): **S** ≤2d · **M** 3–5d · **L** 1–2wk · **XL** >2wk.

---

## 3. Gap inventory — Core (`mercantis.core.flutter`)

### 3.1 Engine (`packages/mercantis_core`)

| # | Gap | Swift (source of truth) | Flutter status | Sev | Eff |
|---|-----|-------------------------|----------------|:---:|:---:|
| C1 | **ExecutionContext + lifecycle threading** | `Identity/ExecutionContext.swift` (136) threaded through `DocumentEngine` (+390 diff); per-op operator/company/roles/device/session/system flag; remote mutations under explicit system context; fail-closed when operator has no roles | Missing — user/device baked at engine construction; no per-call context | High | L |
| C2 | **Posting substrate** | `Posting/PostingBatch.swift` (180) + `DocumentEngine/UnitOfWork.swift` (104) + in-transaction posting writer; deterministic `POST-<src>-v<n>` ids, status (pending/posted/failed/reversed), reversal linkage, recovery & audit | Missing — Hub gets idempotency only from deterministic GL ids; no batch/recovery/diagnostics, no UnitOfWork seam | High | L |
| C3 | **Validation hardening** | `ValidationPipeline.swift` (+267): recursive child-row validation, child immutability after submit, `DocumentVersion.swift` (55) optimistic versioning | Partial — top-level validation only; child rows under-validated | High | M |
| C4 | **Field help metadata** | `FieldDefinition.swift` (+46): `helpText`, `placeholder` (ordering: helpText before defaultValue/options) | ✅ **Done** — `helpText`/`placeholder` added to `FieldDefinition` (+ JSON round-trip, copyWith) and threaded through `ResolvedFieldDefinition`. Covered by `field_definition_help_test.dart`. | High | S |
| C5 | **Permission granularity** | distinct submit/cancel/amend perms; opt-in fail-closed for submittable DocTypes (`PermissionRule` +26) | Partial — coarse perms | Medium | M |
| C6 | **Read-only SQL substrate** | `Storage/ReadOnlyQuery.swift` (110) — guarded read-only runner backing the Data Browser | Missing | Medium | M |
| C7 | **Saved-report power features** | `SavedReportDefinition.swift` (+85) + `SavedReportEngine.swift` (+50): grouping, aggregates, charts, typed execution | Engine present but without grouping/aggregate/chart execution | Medium | M |
| C8 | **Numeric null fix + line-item fetch** | empty numeric stores `null` not `""`; declarative `fetchFrom` + live formula recompute on line items | Verify/port — decimal type errors otherwise | Medium | S |

### 3.2 UI shell (`packages/mercantis_core_ui`)

| # | Gap | Swift | Flutter status | Sev | Eff |
|---|-----|-------|----------------|:---:|:---:|
| CU1 | **Tree view + view-mode switcher** ⭐ | `UIShell/RecordViewMode.swift` (list/browse/tree/detail) + `RecordTreeView.swift` (135) + `RecordCollectionHostView.swift` (661) | 🟡 **Tree view + List/Tree toggle landed** — `record_tree_view.dart` (pure `RecordTree` builder + outline widget) + `record_view_mode.dart`, gated on `isTree`, persisted per-DocType, wired into `GenericListView` (and `RecordCollectionView`). Covered by `record_tree_view_test.dart`. _Remaining:_ `browse`/`detail` split panes. | High | L |
| CU2 | **Form-UX layer** | `GenericFormView.swift` (+518), `FormPrerequisites.swift` (91), `LinkPickerField.swift` (+204): field help/placeholder, inline validation, prerequisite nudge, **inline create from picker**, currency-symbol affordance, file picker, module hints | ✅ **Done:** C4 metadata, field help footnotes + placeholders, inline validation (required/numeric, touched-aware + on-save), prerequisite "set up your basics first" banner, **currency-symbol prefix** (`currency`→`Currency.symbol` resolver), and **inline-create-from-link-picker** (creates + selects the new master without leaving the form; nested links recurse). `form_field_support.dart` + `LinkPickerField`. Covered by `form_field_support_test.dart`, `field_definition_help_test.dart`, and the link-picker inline-create widget test. (File picker = existing attachment field; module hints deferred — cosmetic.) | High | L |
| CU3 | **Data Browser** | `UIShell/DataBrowserView.swift` (461) — read-only SQL runner + schema/columns inspector (System-Manager gated) | Missing | Medium | M |
| CU4 | **Glossary** | `UIShell/Glossary.swift` (203) — plain-language jargon window | Missing | Low | S |
| CU5 | **Visual report viewer/runner** | `GenericReportView.swift` (183) + saved-report runner + chart rendering in `DashboardResultGrid` | Partial — `report_result_view.dart` renders flat tables; no grouping/aggregate/chart UI, no saved-report runner | Medium | M |
| CU6 | **Rich-text field** | `RichTextField.swift` (WYSIWYG) | Missing — `richText` falls back to plain text | Medium | M |
| CU7 | **Multiselect field** | chip selector | Missing — falls back to text | Medium | S |
| CU8 | **Image field (inline)** | `ImageField.swift` stores image inline (`Data`) | Partial — merged into attachment (file-path) widget | Low | S |
| CU9 | **Theme retint + chrome polish** | single brand-indigo accent app-wide, monochrome sidebar icons, CommandBar auto-focus | Missing | Low | S |
| CU10 | **Settings routing** | `SettingsView` wired | Widget exists; router still a "coming soon" stub (`shell_router.dart`) | Low | S |

---

## 4. Gap inventory — Hub (`mercantis.hub.flutter`)

### 4.1 Modules & business logic

| # | Gap | Swift | Flutter status | Sev | Eff |
|---|-----|-------|----------------|:---:|:---:|
| H1 | **Banking & reconciliation** | `Modules/Banking/`: `BankingDocTypes.swift` (140 — BankAccount/BankStatementLine/BankReconciliation), `BankMatchingService.swift` (127), `BankStatementCSVImporter.swift` (168) | Missing entirely | High | L |
| H2 | **Accounting Autopilot — compliance** | `Modules/Accounting/`: `ComplianceDocTypes.swift` (106 — TaxFiling/TaxFilingBox), `TaxReturnBuilder.swift` (189), `YearEndCloseBuilder.swift` (119), `BooksLockPolicy.swift` (21) + `Company.books_lock_date`, `OpeningBalanceBuilder.swift` (101), `InvoiceStatusService.swift` (175), `HubAccountResolver.swift` (54), `HubPostingFlow.swift` (53) | Missing — only `GuidedPaymentBuilder` was ported | High | XL |
| H3 | **Document conversion** | `Modules/Selling/HubDocumentConversion.swift` (274): Quotation→SO→Delivery→Invoice, PO→Receipt→Invoice, Lead→Customer/Quotation, partial-fulfilment "remaining lines" | Missing entirely | High | L |
| H4 | **Multi-currency posting** | `PostingCoordinator.swift` (1388) reads `conversion_rate`, posts base-amount legs | Missing — single (company) currency only | High | M |
| H5 | **Valuation & posting guards** | FIFO valuation, manufactured-goods at production cost, UOM conversion applied in stock posting, period-close + negative-stock guards | Missing/partial | Medium | L |
| H6 | **Sales / Purchase returns** | returns via `is_return` | Missing | Medium | M |
| H7 | **WHT / excise tax types** | `Modules/Tax/TaxDocTypes.swift` (148) `tax_type` beyond VAT | VAT only | Medium | M |
| H8 | **POS shift reports** | `Modules/POS/POSShiftReportBuilder.swift` (123) — X-Report, Z-Report, POS Shifts | Missing | Medium | M |
| H9 | **Jurisdiction-aware setup** | setup wizard: COA/tax templates by country/business-type, dropdown pickers, adaptive re-run | Simpler onboarding seeder | Medium | M |
| H10 | **Repair Chart of Accounts** | Tools ▸ Repair COA menu command | Missing | Low | S |

### 4.2 Hub UI

| # | Gap | Swift | Flutter status | Sev | Eff |
|---|-----|-------|----------------|:---:|:---:|
| HU1 | **Compliance views** | `UI/Compliance/`: `HubTaxReturnView.swift` (359), `HubYearEndCloseView.swift` (286), `HubBooksLockView.swift` (127), `HubAccountantExportView.swift` (143) | Missing (pairs with H2) | High | L |
| HU2 | **No-code print designer** | `UI/Printing/HubPrintFormatsManagerView.swift` (714) + `HubPrintButton.swift` (169) + `Printing/` engine (`HubPrintFormats` 208, `HubPrintHTML` 279, `HubPrintLayoutModel` 121, `HubPrintFormatStore` 171, `HubPrintFormatValidator` 57, `HubPrintPresenter` 86) + `PrintFormat` DocType; PrintStyle (logo/density/typography/standing text), HTML/CSS templates, per-DocType print menu | Engine `print_format.dart` exists; **no PrintFormat DocType, no designer UI, no HTML renderer** | Medium | XL |
| HU3 | **Visual report builder** | `UI/Reports/`: `HubReportStudioView.swift` (439), `HubReportCustomiseView.swift` (559), `HubReportContainerView.swift` (263), `HubCustomReportsView.swift` (173), `HubSavedReportRunnerView.swift` (203), `HubReportOutputView.swift` (126) — palette, grouping, charts, live preview | Missing (depends on C7/CU5) | Medium | L |
| HU4 | **Conversion-lineage "Related" inspector** | clickable cross-DocType lineage card (quote→order→invoice) | Missing | Medium | M |
| HU5 | **Navigation upgrade** | ⌘K command palette, sidebar filter, multi-expand + persistence | Missing in Hub shell | Medium | M |
| HU6 | **Owner / Accountant mode** | role-based UI mode (Autopilot Phase 4) | Missing | Medium | M |
| HU7 | **Header action bar** | lifecycle actions consolidated at top | Missing | Low | S |
| HU8 | **Rebrand → "Neuradix Atlas"** | product name + 3-colour logo + in-app glyph | Still "Mercantis Hub" everywhere | Medium† | M |

† **Requires product sign-off before applying** — it is a branding decision, not
a defect. Listed for completeness.

### 4.3 Cross-cutting / platform

| # | Gap | Swift | Flutter status | Sev | Eff |
|---|-----|-------|----------------|:---:|:---:|
| X1 | **macOS receipt OCR** | `ReceiptTextRecognizer.swift` uses Apple **Vision** (runs on macOS) | OCR via ML Kit is **Android/iOS only**; desktop = `UnavailableTextRecognizer` → no OCR on the macOS build | Medium | M |
| X2 | **De-mock Approvals inbox** | real approval engine | `lib/mock/mock_data.dart` `approvals()` still used | Low | S |

---

## 5. Implementation plan

**Principle:** _ERP correctness first, and unblock-the-blockers first._ Core
engine substrate (Phase 0) gates almost everything else; the Hub business logic
(Phase 2) depends on it; the UI phases depend on their respective logic. Within a
phase, items are independent and parallelizable.

Dependency spine:
`C4 → CU2` · `C1/C2/C3 → H2/H4/H5` · `C6 → CU3` · `C7 → CU5 → HU3` ·
`H2 → HU1/HU6` · `H3 → HU4`.

### Phase 0 — Core engine substrate *(repo: core.flutter — blocks Hub)*
Highest priority; everything downstream assumes it.

- **0.1 ExecutionContext (C1)** — add the context type; thread it through every
  `DocumentEngine` create/update/submit/cancel/amend; ambient provider; apply
  remote/sync mutations under a system context; fail-closed when an operator has
  no roles. *Eff L.*
- **0.2 Posting substrate (C2)** — `PostingBatch` value type + store, `UnitOfWork`
  transaction seam, in-transaction posting writer, deterministic batch ids,
  reversal linkage, recovery/diagnostics read API. *Eff L.*
- **0.3 Validation hardening (C3)** — recursive child-row validation, child
  immutability after submit, optimistic `DocumentVersion`. *Eff M.*
- **0.4 Field help metadata (C4)** — add `helpText`/`placeholder` to
  `FieldDefinition` (unblocks CU2). *Eff S.*
- **0.5 Permission granularity (C5)** + **numeric-null/fetchFrom fixes (C8)**.
- **0.6 Read-only query substrate (C6)** + **saved-report power features (C7)**.

**Exit:** `ledger_derivation_test` and a new `posting_batch_test` pass under the
new substrate; existing Hub tests stay green against the pinned core ref.

### Phase 1 — Core UI capstones *(repo: core.flutter)*
- **1.1 Tree view (CU1)** ⭐ — `RecordViewMode` enum + `RecordTreeView` widget +
  view-mode switcher in the collection host. *Self-contained; good first PR.*
- **1.2 Form-UX layer (CU2)** — render help/placeholder, inline validation,
  prerequisite nudges, inline-create from link picker, currency symbol, file
  picker. *Depends on 0.4.*
- **1.3 Data Browser (CU3)** — depends on 0.6.
- **1.4 Report viewer/runner + charts (CU5)** — depends on 0.6/0.7.
- **1.5 Rich-text (CU6) + multiselect (CU7) + inline image (CU8) widgets.**
- **1.6 Glossary (CU4), theme retint (CU9), settings routing (CU10).**

**Exit:** field-widget coverage = Swift; tree/browse/list/detail modes available;
no field type silently falls back to a bare text editor.

### Phase 2 — Hub business logic *(repo: hub.flutter — depends on Phase 0)*
Sequenced as the Swift "Tier 1–2 / Autopilot 1–4" waves were:

- **2.1 Multi-currency base-amount foundation (H4).**
- **2.2 Document conversion (H3)** — the conversion map + partial-fulfilment.
- **2.3 Valuation & guards (H5)** — FIFO, production cost, UOM-in-posting,
  period-close/negative-stock guards.
- **2.4 Sales/Purchase returns (H6)** + **WHT/excise (H7)**.
- **2.5 Autopilot 1 — jurisdiction setup + COA/tax templates (H9).**
- **2.6 Autopilot 2 — opening balances + Banking module (H1, OpeningBalanceBuilder).**
- **2.7 Autopilot 3 — compliance logic (H2):** TaxFiling/TaxFilingBox DocTypes,
  TaxReturnBuilder, YearEndCloseBuilder, BooksLockPolicy + `books_lock_date`,
  InvoiceStatusService.
- **2.8 POS shift reports (H8)** + **Repair COA (H10).**

**Exit:** full DocType parity; trial-balance/AR/AP plus new compliance figures
reconcile; bank reconciliation matches statement lines to payments.

### Phase 3 — Hub UI *(repo: hub.flutter — depends on Phases 1 & 2)*
- **3.1 Compliance views (HU1)** — pair with 2.7.
- **3.2 Visual report builder (HU3)** — depends on 1.4.
- **3.3 No-code print designer (HU2)** — PrintFormat DocType + HTML renderer +
  manager UI + per-DocType print menu. *Largest single UI item.*
- **3.4 Conversion-lineage inspector (HU4)** — depends on 2.2.
- **3.5 Navigation upgrade (HU5)** + **header action bar (HU7).**
- **3.6 Owner/Accountant mode (HU6)** — depends on 2.7.

### Phase 4 — Cross-cutting & polish
- **4.1 macOS OCR (X1)** — desktop text-recognition path (e.g. a macOS Vision
  plugin / channel, or a desktop OCR engine) so the macOS build matches Swift.
- **4.2 De-mock Approvals inbox (X2).**
- **4.3 Rebrand to "Neuradix Atlas" (HU8)** — **only after product sign-off.**

### Suggested milestones
- **M1 (Core correctness):** Phase 0 complete, core ref re-pinned.
- **M2 (Core UX parity):** Phase 1 complete — includes the Tree view.
- **M3 (Hub ledger parity):** Phase 2.1–2.4 complete.
- **M4 (Accounting Autopilot):** Phase 2.5–2.8 + Phase 3.1 complete.
- **M5 (Hub UX parity):** remainder of Phase 3.
- **M6 (Full parity):** Phase 4 + sign-off items.

---

## 6. Testing & rollout

- **Port the Swift tests alongside each item:** `ExecutionContextTests`,
  `PostingBatchTests`, `UnitOfWorkTests`, `ChildTableValidationTests`,
  `PermissionFailClosedTests` (core); banking/compliance/conversion/valuation
  suites (hub). Keep the existing Flutter `*_test.dart` green throughout.
- **Core/Hub coupling:** the Hub pins a Core ref. Land each Core phase, re-pin,
  then build the dependent Hub phase — mirroring the Swift "Bump Core pin"
  commits.
- **Manifest integrity:** extend `manifest_integrity_test.dart` as DocTypes land
  so every new DocType is registered and every workflow bound.
- **Parity gate per PR:** reference the gap id(s) closed; a phase is done only
  when its Exit criteria above are met.

## 7. Maintenance note

The Flutter `PARITY.md` files are now stale and over-state parity. On completion
of each phase, update them — or retire them in favour of this document — so the
trackers stop omitting the June-12→29 wave.
