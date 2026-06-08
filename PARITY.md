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
| CRM | Customer, Contact, Address, Lead, DynamicLink | 🟡 | Customer, Contact, Lead live (+ Opportunity, Flutter-only); **Address + DynamicLink missing** |
| Setup | 14 (Company, groups, masters, PriceList, FiscalYear, UOM…) | 🟡 | live: Company, Currency, CostCenter, FiscalYear (+ Fiscal Year Company child); ItemGroup/Warehouse live under Stock. **Pending: UOM, Brand, PriceList, ItemPrice, NumberingSeries, CustomerGroup, SupplierGroup, Territory** |
| Selling | Item, Quotation, SalesOrder, SalesInvoice + line items | ✅ | **line-item child DocTypes added (Phase 2)**; Item child tables (ItemSupplier, UOMConversionDetail) pending |
| Buying | Supplier, SQ, PO, PurchaseInvoice, Receipt + items | 🟡 | Supplier, PO, PurchaseInvoice + items, Receipt (under Fulfilment); **Supplier Quotation pending** |
| Stock | Item, StockEntry, **StockLedgerEntry, Bin** | ✅ | **Stock Entry Detail + Stock Ledger Entry + Bin added (Phase 2)**; hosts Item, Item Group, Warehouse |
| Accounting | Account, JE, PaymentEntry + **GL/CustTrans/VendTrans/Settlement/TaxTrans** | ✅ | **all subledger tables + JE Account + PE Reference added (Phase 2)** — full DocType parity |
| Deliveries | SalesDelivery, Route, DeliveryRouteStop, Driver, Vehicle, StatusEvent | 🟡 | Delivery Note + items + journey workflow only; **Route/Driver/Vehicle/StatusEvent not ported as DocTypes — mock screens only** |
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
| Line-item & document totals | ✅ | ✅ | `LineItemTotalsInterceptor` (beforeSave) computes per-row `amount = qty*rate`, `total` = Σ amount, `grand_total` = total (until tax legs) — authoritative on every save path; child grid also evaluates `formulaExpression` live (core `applyRowFormulas`) |
| Business Profile defaults policy | ✅ | ✅ | `BusinessProfileDefaultsInterceptor` (core `DocumentInterceptor.beforeSave`) stamps company, default currency, default posting accounts + today's posting date on new drafts; only fills blanks |
| Fiscal-year posting validation | ✅ | ✅ | `FiscalYearGuardInterceptor` (core `DocumentInterceptor.beforeSubmit`) blocks a posting dated outside every defined Fiscal Year; no-op until at least one year exists |
| Posting-account resolution | ✅ | ✅ | explicit voucher fields win; blank accounts fall back to Company defaults (default_receivable/income/payable/expense/cash) resolved by the runner before derivation |
| Invoice `outstanding_amount` update on settlement | ✅ | ✅ | **core `applyOnSubmitUpdate` added**; runner recomputes outstanding from the Settlement subledger (idempotent) on invoice submit + payment submit/cancel |
| Tax legs (VAT split + TaxTrans rows) | ✅ | ❌ | pending Tax module; invoices post 2-leg GL meanwhile |

## Reports, dashboards & flows

| Item | Swift | Flutter | Notes |
|------|:----:|:------:|-------|
| Reports (14, incl. aggregating) | ✅ | 🟡 | 14 flat registers wired on real data via Core ReportEngine (`HubReports` + `reportEngineProvider` + `ReportsScreen`/`ReportViewerScreen`); aggregating reports (Trial Balance, aging) still to layer on top |
| Dashboards (5) | ✅ | ✅ | 5 dashboards (Home, Finance, Sales, Buying, Inventory) on real data via Core DashboardEngine; monetary KPIs use the new `sum` widget. `HubDashboards` + `dashboardEngineProvider` + `DashboardsScreen`/`DashboardScreen`. **Home workspace cards now fed by the real `home` dashboard** (mock home KPIs retired); Sales/Inventory workspace cards still mock |
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
