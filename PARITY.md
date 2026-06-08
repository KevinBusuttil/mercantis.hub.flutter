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
| Selling | Item, Quotation, SalesOrder, SalesInvoice + line items | 🟡 | **line-item child DocTypes added (Phase 2)**; Item child tables (ItemSupplier, UOMConversionDetail) pending |
| Buying | Supplier, SQ, PO, PurchaseInvoice, Receipt + items | 🟡 | Supplier, PO, PurchaseInvoice + items, Receipt (under Fulfilment); **Supplier Quotation pending** |
| Stock | Item, StockEntry, **StockLedgerEntry, Bin** | ✅ | **Stock Entry Detail + Stock Ledger Entry + Bin added (Phase 2)**; hosts Item, Item Group, Warehouse |
| Accounting | Account, JE, PaymentEntry + **GL/CustTrans/VendTrans/Settlement/TaxTrans** | ✅ | **all subledger tables + JE Account + PE Reference added (Phase 2)** — full DocType parity |
| Deliveries | SalesDelivery, Route, DeliveryRouteStop, Driver, Vehicle, StatusEvent | ✅ | Delivery Note + items + journey workflow **plus routes/fleet now ported**: Delivery Route (+ Stop child), Driver, Vehicle, Delivery Status Event; `DeliveryRouteService` appends status events + mirrors route/status onto the Delivery Note. In the Delivery workspace. Covered by `test/deliveries_test.dart` |
| Manufacturing | BOM, WorkOrder, JobCard, ProductionPlan, Workstation, Operation | 🟡 | **DocTypes ported** (BOM+items+operations w/ cost rollup, Work Order+required items, Job Card, Production Plan, Workstation, Operation); `wf-bom`/`wf-work-order`/`wf-production-plan` bound; submitting a Production Plan auto-creates Work Orders (BOM-exploded). Stock-only posting via `Manufacturing.completionStockEntry` (consume raw + produce finished → existing Stock Entry derivation). Covered by `test/manufacturing_test.dart`. **Shop-floor `WorkOrderCompleteScreen` added** (post production from a Work Order); auto-post on workflow completion still pending a core transition event |
| POS | POSProfile, POSSession, POSInvoice, PaymentTender | 🟡 | **DocTypes + ledger posting ported**: POS Invoice (cash sale) issues stock + posts Dr Cash / Cr Income(net) / output VAT (reuses tax engine + stock derivation), `wf-pos-invoice` bound, pure `PosCheckout` builder, in Sales workspace. Covered by `test/pos_checkout_test.dart` + POS group in `ledger_derivation_test.dart`. **POS till (`PosTillScreen`) with live VAT + cash checkout added** |
| Tax | TaxCode, TaxCategory, TaxCharge | ✅ | **Tax Code/Category masters + Tax Charge child ported; VAT calc on save + tax-leg derivation + Tax Transaction subledger live.** WHT/excise tax types pending |

## Business logic (the critical path)

| Capability | Swift | Flutter | Notes |
|------------|:----:|:------:|-------|
| Workflows (14) | ✅ | ✅ | all 14 defined + bound to existing submittable DocTypes (Phase 2); 4 inert pending modules |
| **LedgerDerivationService** (GL/SLE/Cust/Vend/Settlement on submit & cancel) | ✅ | ✅ | **Phase 3:** pure `LedgerDerivation` + runner wired at boot; deterministic ids + reversal; covered by `test/ledger_derivation_test.dart` |
| **StockBalanceService** (Bin recompute) | ✅ | ✅ | **Phase 3:** pure `StockBalance` fold + `recomputeBin` after stock moves |
| ManufacturingDerivationService | ✅ | 🟡 | `Manufacturing` helpers (BOM explosion, cost rollup, completion Stock Entry) + `ManufacturingDerivationService` (Production Plan → Work Orders on submit). Stock-only (Swift posts no GL). Auto-post-on-WO-completion pending a workflow-transition event |
| DeliveryRouteService | ✅ | ✅ | `DeliveryRoutePlanner` (pure: change detection + deterministic event ids) + `DeliveryRouteService` (on route save: append status events, mirror route/status onto Delivery Notes). Started at boot; covered by `test/deliveries_test.dart` |
| Line-item & document totals | ✅ | ✅ | `LineItemTotalsInterceptor` (beforeSave) computes per-row `amount = qty*rate`, `total` = Σ amount; `grand_total` = total on non-tax docs, and `total + tax` on invoices (owned by `TaxCalculationInterceptor`) — authoritative on every save path; child grid also evaluates `formulaExpression` live (core `applyRowFormulas`) |
| Business Profile defaults policy | ✅ | ✅ | `BusinessProfileDefaultsInterceptor` (core `DocumentInterceptor.beforeSave`) stamps company, default currency, default posting accounts + today's posting date on new drafts; only fills blanks |
| Fiscal-year posting validation | ✅ | ✅ | `FiscalYearGuardInterceptor` (core `DocumentInterceptor.beforeSubmit`) blocks a posting dated outside every defined Fiscal Year; no-op until at least one year exists |
| Posting-account resolution | ✅ | ✅ | explicit voucher fields win; blank accounts fall back to Company defaults (default_receivable/income/payable/expense/cash) resolved by the runner before derivation |
| Invoice `outstanding_amount` update on settlement | ✅ | ✅ | **core `applyOnSubmitUpdate` added**; runner recomputes outstanding from the Settlement subledger (idempotent) on invoice submit + payment submit/cancel |
| Tax legs (VAT split + TaxTrans rows) | ✅ | ✅ | `TaxCalculationInterceptor` computes VAT on save (line → item → document → party code fallback, default-VAT-account fallback, zero-rated rows kept); `LedgerDerivation` splits income/expense net + posts output/input VAT GL legs + signed `Tax Transaction` rows, reversal-on-cancel. Covered by `test/hub_tax_engine_test.dart`, `test/hub_tax_calc_test.dart`, `test/ledger_derivation_test.dart` |

## Reports, dashboards & flows

| Item | Swift | Flutter | Notes |
|------|:----:|:------:|-------|
| Reports (14, incl. aggregating) | ✅ | ✅ | 14 flat registers via Core ReportEngine (`HubReports`) **plus app-side aggregating reports — Trial Balance + AR/AP aging** (`HubAggregatingReports`, `trial_balance`/`ar_aging`/`ap_aging` providers, surfaced in `ReportsScreen` under "Financial statements"). Covered by `test/aggregating_reports_test.dart`. (AP aging is new — Swift shipped AR aging only.) |
| Dashboards (5) | ✅ | ✅ | 5 dashboards (Home, Finance, Sales, Buying, Inventory) on real data via Core DashboardEngine; monetary KPIs use the new `sum` widget. `HubDashboards` + `dashboardEngineProvider` + `DashboardsScreen`/`DashboardScreen`. **Home workspace cards now fed by the real `home` dashboard** (mock home KPIs retired); Sales/Inventory workspace cards still mock |
| Guided flows (Receive Payment, Pay Supplier, POS Checkout) | ✅ | 🟡 | **Receive Payment + Pay Supplier done** — `GuidedPayment` builder (FIFO auto-allocate + Payment Entry construction) + `GuidedPaymentScreen` wired into the Finance workspace; posts a submitted Payment Entry whose references drive the existing settlement/outstanding derivation. Covered by `test/guided_payment_test.dart`. POS Checkout ✅ via the POS till (`PosTillScreen`) |
| Onboarding business presets | ✅ | ✅ | First-run wizard (`OnboardingScreen`, gated on Company existence in `hub_app.dart`) + idempotent `HubSeeder`: Currency, Main Store warehouse, current Fiscal Year, 8-account chart, **VAT bands (enhancement over Swift)**, and a Company wired to the default accounts. 4 presets (Services/Trade/Retail/Manufacturing) — module-enable flags recorded for when POS/Mfg/Deliveries land. Covered by `test/hub_seeder_test.dart` |

## UX / navigation

| Surface | Status | Notes |
|---------|:----:|-------|
| Workspace shell + 9 workspaces | 🟡 | structure exists; many items route to mock screens |
| 3-level Module → Group → Item nav | 🟡 | flatter than Swift; no advanced/normal gating |
| Custom screens (Sales Orders, Customer Acct, Routes, Driver, Low Stock) | 🟡 | **mock-data prototypes** — de-mock as logic lands |
| Settings (advanced toggle, optional modules) | ✅ | `SettingsScreen` + persisted `Hub Settings` singleton (`hubSettingsProvider`): advanced toggle + POS/Manufacturing/Deliveries visibility (gates those workspaces at launch) + operator identity. Covered by `test/hub_settings_test.dart` |
| Real auth (vs hardcoded user) | 🟡 | operator is now data-driven from `Hub Settings` (editable in Settings), not hardcoded; `currentUserProvider` derives from it. True credential/backend auth still pending |

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
5. **Phase 6 — optional modules.** Tax ✅ (VAT codes + tax legs); POS ✅
   (cash-sale posting; till UI pending); Manufacturing ✅ (BOM/WO/plan +
   stock-only production posting; auto-complete + UI pending); Deliveries
   routes/fleet ✅ (routes, fleet, status-event log + Delivery Note mirror).
   All modules ported. Remaining work is UI capstones (POS till,
   shop-floor) + Settings/auth.

> Depends on Core repo Phase 1 (report/dashboard execution engine) — landed.
> See `mercantis.core.flutter/PARITY.md`.
