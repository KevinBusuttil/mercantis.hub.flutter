# Hub — Flutter Parity Tracker

Tracks the Flutter port of `mercantis.hub.app` (Swift/SwiftUI ERP) toward
feature parity. The Swift Hub is ~80% of a usable ERP (65+ DocTypes, 11
modules, 14 workflows, full ledger derivation). The Flutter Hub is currently a
**UX prototype backed by mock data**. The Swift app is the source of truth.

**Strategy:** _ERP correctness first._ The accounting/ledger spine is the
critical path and must be ported precisely (deterministic IDs, idempotency,
reversal-on-cancel). Mock-backed screens are replaced as real logic lands.

Legend: ✅ parity · 🟡 partial · ❌ missing/mock

## Modules & DocTypes

| Module | Swift DocTypes | Flutter | Notes |
|--------|:----:|:----:|-------|
| CRM | Customer, Supplier, Contact, Address, Lead, DynamicLink | 🟡 | masters defined; Address + DynamicLink missing |
| Setup | 14 (Company, groups, masters, PriceList, FiscalYear, UOM…) | 🟡 | core masters + Fiscal Year Company child; UOM/Brand/PriceList pending |
| Selling | Item, Quotation, SalesOrder, SalesInvoice + line items | ✅ | **line-item child DocTypes added (Phase 2)** |
| Buying | Supplier, SQ, PO, PurchaseInvoice, Receipt + items | 🟡 | line items added; Supplier Quotation pending |
| Stock | Item, StockEntry, **StockLedgerEntry, Bin** | ✅ | **Stock Entry Detail + Stock Ledger Entry + Bin added (Phase 2)** |
| Accounting | Account, JE, PaymentEntry + **GL/CustTrans/VendTrans/Settlement/TaxTrans** | ✅ | **all subledger tables + JE Account + PE Reference added (Phase 2)** |
| Deliveries | SalesDelivery, Route, Driver, Vehicle, StatusEvent | 🟡 | Delivery Note + items + journey workflow; Routes/Fleet mostly mock |
| Manufacturing | BOM, WorkOrder, JobCard, ProductionPlan, Workstation, Operation | ❌ | module not ported (workflows defined, inert) |
| POS | POSProfile, POSSession, POSInvoice, PaymentTender | ❌ | not ported (workflow defined, inert) |
| Tax | TaxCode, TaxCategory, TaxCharge | ❌ | not ported (Tax Transaction subledger stub present) |

## Business logic (the critical path)

| Capability | Swift | Flutter | Notes |
|------------|:----:|:------:|-------|
| Workflows (14) | ✅ | ✅ | all 14 defined + bound to existing submittable DocTypes (Phase 2); 4 inert pending modules |
| **LedgerDerivationService** (GL/SLE/Cust/Vend/Settlement on submit & cancel) | ✅ | ✅ | **Phase 3:** pure `LedgerDerivation` + runner wired at boot; deterministic ids + reversal; covered by `test/ledger_derivation_test.dart` |
| **StockBalanceService** (Bin recompute) | ✅ | ✅ | **Phase 3:** pure `StockBalance` fold + `recomputeBin` after stock moves |
| ManufacturingDerivationService | ✅ | ❌ | pending Manufacturing module (Phase 6) |
| DeliveryRouteService | ✅ | ❌ | pending (Phase 6) |
| Business Profile defaults policy | ✅ | ✅ | `BusinessProfileDefaultsInterceptor` (core `DocumentInterceptor.beforeSave`) stamps company, default currency, default posting accounts + today's posting date on new drafts; only fills blanks |
| Fiscal-year posting validation | ✅ | ✅ | `FiscalYearGuardInterceptor` (core `DocumentInterceptor.beforeSubmit`) blocks a posting dated outside every defined Fiscal Year; no-op until at least one year exists |
| Posting-account resolution | ✅ | ✅ | explicit voucher fields win; blank accounts fall back to Company defaults (default_receivable/income/payable/expense/cash) resolved by the runner before derivation |
| Invoice `outstanding_amount` update on settlement | ✅ | ✅ | **core `applyOnSubmitUpdate` added**; runner recomputes outstanding from the Settlement subledger (idempotent) on invoice submit + payment submit/cancel |
| Tax legs (VAT split + TaxTrans rows) | ✅ | ❌ | pending Tax module; invoices post 2-leg GL meanwhile |

## Reports, dashboards & flows

| Item | Swift | Flutter | Notes |
|------|:----:|:------:|-------|
| Reports (14, incl. aggregating) | ✅ | ❌ | `reports: []`; needs Core ReportEngine (now landed) |
| Dashboards (5) | ✅ | ❌ | all dashboard data is **mock** |
| Guided flows (Receive Payment, Pay Supplier, POS Checkout) | ✅ | ❌ | |
| Onboarding business presets | ✅ | ❌ | Services/Trade/Retail/Manufacturing |

## UX / navigation

| Surface | Status | Notes |
|---------|:----:|-------|
| Workspace shell + 9 workspaces | 🟡 | structure exists; many items route to mock screens |
| 3-level Module → Group → Item nav | 🟡 | flatter than Swift; no advanced/normal gating |
| Custom screens (Sales Orders, Customer Acct, Routes, Driver, Low Stock) | 🟡 | **mock-data prototypes** — de-mock as logic lands |
| Settings (advanced toggle, optional modules) | ❌ | |
| Real auth (vs hardcoded user) | ❌ | |

## Sequenced plan (ERP-correctness-first)

1. **Phase 2 — data model.** ✅ _Done:_ line-item child DocTypes (sales,
   purchase, stock, JE accounts, payment references, fulfilment); ledger tables
   (GL Entry, Customer/Supplier Transaction, Settlement, Tax Transaction, Stock
   Ledger Entry, Bin); all 14 workflows defined + bound. Guarded by
   `test/manifest_integrity_test.dart`. _Remaining:_ Item UOM/supplier child
   tables, Address/DynamicLink, UOM/Brand/PriceList masters.
2. **Phase 3 — ledger spine (critical).** ✅ _Core derivation done:_
   `LedgerDerivation` (GL + customer/supplier subledger + settlements + stock
   ledger, reversal-on-cancel, deterministic ids) and `StockBalance` Bin
   recompute, wired at boot, covered by `test/ledger_derivation_test.dart`
   (balanced-books, reversal-nets-zero, stock signs). _Follow-ups:_ business-
   profile defaults, fiscal-year validation, posting-account fallback, invoice
   outstanding update (needs a core API), tax legs.
3. **Phase 4 — reports/dashboards + de-mock.** 14 reports (using Core
   ReportEngine), 5 dashboards on real data, replace mock screens.
4. **Phase 5 — UX/menu parity.** 3-level nav, presets, settings, guided flows.
5. **Phase 6 — optional modules.** POS, Manufacturing, Tax, full Deliveries.

> Depends on Core repo Phase 1 (report/dashboard execution engine) — landed.
> See `mercantis.core.flutter/PARITY.md`.
