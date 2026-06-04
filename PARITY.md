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
| Setup | 14 (Company, groups, masters, PriceList, FiscalYear, UOM…) | 🟡 | core masters only; tree masters, UOM, Brand, PriceList partial |
| Selling | Item, Quotation, SalesOrder, SalesInvoice + line items | 🟡 | parents defined; **line-item child DocTypes missing** |
| Buying | Supplier, SQ, PO, PurchaseInvoice, Receipt + items | 🟡 | line items missing |
| Stock | Item, StockEntry, **StockLedgerEntry, Bin** | 🟡 | ledger/Bin missing |
| Accounting | Account, JE, PaymentEntry + **GL/CustTrans/VendTrans/Settlement/TaxTrans** | 🟡 | subledger tables all missing |
| Deliveries | SalesDelivery, Route, Driver, Vehicle, StatusEvent | 🟡 | partial; Routes/Fleet mostly mock |
| Manufacturing | BOM, WorkOrder, JobCard, ProductionPlan, Workstation, Operation | ❌ | module not ported |
| POS | POSProfile, POSSession, POSInvoice, PaymentTender | ❌ | not ported |
| Tax | TaxCode, TaxCategory, TaxCharge | ❌ | not ported |

## Business logic (the critical path)

| Capability | Swift | Flutter | Notes |
|------------|:----:|:------:|-------|
| Workflows (14) | ✅ | ❌ | manifest `workflows: []` |
| **LedgerDerivationService** (GL/SLE/Cust/Vend/Settlement on submit & cancel) | ✅ | ❌ | deterministic ids + reversal — port verbatim |
| **StockBalanceService** (Bin recompute) | ✅ | ❌ | |
| ManufacturingDerivationService | ✅ | ❌ | |
| DeliveryRouteService | ✅ | ❌ | |
| Business Profile defaults policy | ✅ | ❌ | currency/accounts/warehouse on new drafts |
| Fiscal-year posting validation | ✅ | ❌ | |
| Posting-account resolution | ✅ | ❌ | explicit → profile → company → error |

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

1. **Phase 2 — data model.** Line-item child DocTypes; all missing DocTypes
   incl. ledger tables (GL/SLE/Bin/Cust/Vend/Settlement); the 14 workflows.
2. **Phase 3 — ledger spine (critical).** Port `LedgerDerivationService` +
   `StockBalanceService` + posting-account resolution + fiscal-year & profile
   policies. Verify with ported tests + a balanced-books check.
3. **Phase 4 — reports/dashboards + de-mock.** 14 reports (using Core
   ReportEngine), 5 dashboards on real data, replace mock screens.
4. **Phase 5 — UX/menu parity.** 3-level nav, presets, settings, guided flows.
5. **Phase 6 — optional modules.** POS, Manufacturing, Tax, full Deliveries.

> Depends on Core repo Phase 1 (report/dashboard execution engine) — landed.
> See `mercantis.core.flutter/PARITY.md`.
