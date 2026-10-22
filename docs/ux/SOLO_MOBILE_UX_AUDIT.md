# Atlas Solo — mobile-first UX and product-scope audit

**Scope:** `mercantis.hub.flutter` (`main` @ `5c73e15`) and `mercantis.core.flutter` Core UI (`main` @ `dd57caf`).
**Branch:** `claude/project-thread-hlx9xb` in both repos.
**Plan reference:** `COMMERCIALISATION_IMPLEMENTATION_PLAN.md` §M1.2 (UX, onboarding and mobile usability).

Every finding below was checked against the code on `main`. Screenshots come from the real Flutter widgets (router, adaptive shell, workspace and report screens), rendered by widget tests over a synthetic business (`test/support/synthetic_business.dart`, "Harbour Lane Design"). They are not usability tests. Observed testing with real users is still required by M2.4.

---

## 1. Findings on `main`

### A. What a new Services business saw

| # | Finding | Evidence (main) |
|---|---|---|
| A1 | Rentals, Online channels and Memberships sections were unconditional in Sales. | `lib/workspaces/sales_fulfilment_workspace.dart:83,98,113` |
| A2 | Fixed assets and Property & tenancies were unconditional in Finance. | `lib/workspaces/finance_workspace.dart:64,79` |
| A3 | Construction contracts lived inside Projects and appeared with it. | `lib/workspaces/projects_workspace.dart:38-46` |
| A4 | The Services preset turned on Projects, Field service *and* Appointments, so a sole trader got three extra workspaces. | `lib/onboarding/business_preset.dart:41-43` |
| A5 | Every optional module defaulted to **on** in `HubSettings`. | `lib/settings/hub_settings.dart:30-36` |
| A6 | The default operator identity was a developer's name and address, and onboarding persisted it. | `lib/settings/hub_settings.dart:38-39` |
| A7 | Approvals was always a workspace, and Home showed an approvals card, in single-operator Solo. | `lib/workspaces/hub_workspaces.dart:32` |
| A8 | Owner/Accountant mode was stored but read nowhere outside the Settings screen, so the persona changed nothing. | `git grep advancedMode main -- lib` → only `hub_settings.dart` and `settings_screen.dart` |
| A9 | Module toggles applied "on next launch" because the workspace registry was filled once at boot. | `lib/navigation/hub_navigation.dart` (`if (registry.all.isEmpty)`) |
| A10 | Filtering happened only at workspace level. Sections, items, quick actions and deep links (`/w/<ws>/<route>`) were never gated, so any route rendered whatever the settings. | Core `app_navigation_registry.dart` |
| A11 | The Reports workspace linked three **unregistered** routes ("Coming soon": `sales-dashboard`, `stock-dashboard`, `finance-dashboard`), while the real statements screen (`reports` route: P&L, Balance Sheet, ageing…) was linked from **nowhere**. | `lib/workspaces/reports_workspace.dart:19-24` |
| A12 | `DocTypeWorkspaceItem.listFilter` was ignored: "Customer payments" opened every payment. | Core `workspace_view.dart`, `/list/:docType` route |

### B. Phone navigation

| # | Finding | Screenshot |
|---|---|---|
| B1 | The phone bar was simply the first four workspaces plus More. A Services business got **Home · Sales · Jobs · Projects · More**, with Finance and getting paid hidden under More. | `before/services_phone_home.png`, `before/services_phone_more.png` |
| B2 | Sales on a phone was a long list of ERP sections, including the verticals. | `before/services_phone_sales.png` |
| B3 | The tablet rail rendered the brand as a separate, vertically centred column beside the rail. | `before/services_tablet_home.png` |
| B4 | KPI figures were unformatted (`€10213.60`) and wrapped mid-number on tablet cards and at large text. | `before/services_tablet_home.png` |

### C. Tasks and reports

| # | Finding | Evidence |
|---|---|---|
| C1 | Save, submit and cancel gave no confirmation. | Core `generic_form_view.dart` |
| C2 | Empty lists said only "No documents". | Core `document_list_pane.dart` |
| C3 | Lifecycle buttons used engine words (Submit / Cancel / Amend) for every document. | Core `command_bar_view.dart` |
| C4 | P&L, Balance Sheet and ageing were desktop `DataTable`s. At 390 px the P&L amount column was cut off. | `before/phone_profit_and_loss.png` |
| C5 | The reports list showed Field service KPIs and Customer deposits to every business, plus Trial Balance and raw registers in engine terms. | `lib/screens/reports_screen.dart` |

---

## 2. What changed

### Product scope: feature catalogue (Hub)

- `lib/features/hub_feature.dart` defines 15 optional features (stock, till, tables & kitchen, leads, projects, appointments, field service, delivery routes, manufacturing, online store orders, memberships, rentals, property, construction, fixed assets). Each one has plain-language copy, a group and dependencies (tables & kitchen needs the till).
- Requirements are classified as **essential** (none), `NeedsFeature` / `NeedsAnyFeature`, `NeedsAccountant`, `NeedsTeam` (approvals) and `NeedsSystemTools` (DocType, workflow and custom-field designers).
- `lib/workspaces/*` are now pure functions of `HubSurface` (settings + Team connection). Gating applies at **workspace, section, item and quick-action** level. `hubRouteRequirements` gates **deep links**: a hidden route opens a page that explains what is off and offers the one switch to turn it on. Records (`/list`, `/form`) are never gated, so data from a hidden feature stays readable and searchable.
- Presets now turn on only what defines the business. Services turns on **nothing** optional and suggests projects, appointments, field service and leads at onboarding. Trade turns on stock. Retail turns on stock and the till.
- Settings › **Business type & features** (`lib/screens/features_screen.dart`) is the catalogue. Changes save at once and apply live. Changing business type lists what turns on and what is hidden, and records are kept.
- Visibility is presentation only. No DocType, record, service, posting rule or permission was removed or changed.

### Existing installations are preserved

- `HubSettings` payload `settings_version: 2` now writes every feature key explicitly.
- A **legacy document** (no version) is read with legacy rules. A missing key means **on**, as before. An explicit off stays off. Tables & kitchen follows the till and construction follows projects, because they used to live inside those sections. Classic full navigation and system configuration are kept. The document is rewritten once as v2.
- An installation with a **company but no settings document** gets `HubSettings.legacy()`: everything on, with classic navigation.
- Only a **brand-new** install (no company) starts minimal for onboarding to shape.
- Classic installs see a one-tap "Use simplified navigation" offer that keeps every feature on.

### Phone navigation (Core UI + Hub)

- Core: `ShellDestination` / `phoneDestinationsProvider` let a host define up to four task destinations, and the shell adds **More**. Without a host value, behaviour is unchanged.
- Hub (`hubPhoneDestinations`):
  - **Services:** Today · Customers · Invoices · Money · More
  - **Trade / Manufacturing / Mixed:** Today · Sales · Stock · Money · More
  - **Retail:** Today · Till · Stock · Money · More

  A destination whose feature is off falls back, so the bar never points at a hidden area.
- Tablets and desktops keep the full rail or sidebar. The rail now carries the brand correctly.

### Owner and Accountant views

- **Owner:** business words (Money, Buying, Supplier bills, "Post invoice", "Record payment", "Reverse", "Correct"), guided empty states, "Saved on this device" confirmations, and summary-first reports. No ledger, journal, cost-centre or report-builder entries.
- **Accountant:** engine terms, plus Ledger (accounts, journals, cost centres, all payment entries, audit trail), trial balance, reconciliations, raw registers and the report builder. The detailed report table is open by default.
- Journals keep accounting language in both views. Changing the view changes only what is shown. The screen says so, and tests assert that posting and permissions are untouched. Visibility is not a security boundary.

### Tasks

- Core: save, submit and cancel are now confirmed in the document's own words. Empty lists give guidance, for example "No invoices yet: create one here, or convert an accepted quote." Filtered list links work, so "Payments received" shows receipts only.
- Hub: Home quick actions follow the profile (New invoice, New quote, Receive payment, Record expense, Scan receipt; Move stock / Receive goods only with stock; Open till only with the till). Money groups Get paid · Pay · Bank · VAT, reports & accountant.

### Phone-first reports

- `lib/reports/report_summary.dart` reads each statement's `ReportResult` (the same numbers as the table, never recomputed) into **headline figures → what needs attention → groups with drill-down → detailed table**:
  - P&L: profit or loss, income, expenses, margin, with a loss flagged. Accounts drill into the ledger.
  - Balance sheet: own / owe / net worth, and whether it balances.
  - Cash flow: net, in, out.
  - AR and AP ageing: owed, 30+ and 90+ days late, with 90+ parties listed. Each party drills into its invoices or bills.
  - Gross margin and stock value: products below cost and negative stock are flagged.
  - Project profitability: losing projects and unbilled time are flagged.
- The reports list follows features and view, using plain names in the Owner view.
- Money is formatted `€10,213.60` everywhere on Home and in reports.

---

## 3. Before / after

| Surface | Before (`docs/ux/screenshots/before/`) | After (`docs/ux/screenshots/after/`) |
|---|---|---|
| Services phone, Home | `services_phone_home.png` | `services_phone_home.png` |
| Services phone, More | `services_phone_more.png` | `services_phone_more.png` |
| Services phone, Sales | `services_phone_sales.png` | `services_phone_sales.png` |
| Services phone, Finance → Money | `services_phone_finance.png` | `services_phone_money.png` (Accountant: `services_phone_money_accountant.png`) |
| Reports | `services_phone_reports_workspace.png` | `services_phone_reports.png` |
| P&L on a phone | `phone_profit_and_loss.png` | `phone_profit_and_loss.png` (Accountant: `phone_profit_and_loss_accountant.png`) |
| Tablet Home | `services_tablet_home.png` | `services_tablet_home.png` |
| Desktop Home | `services_desktop_home.png` | `services_desktop_home.png` |
| New | — | `phone_onboarding.png`, `phone_who_owes_you.png`, `phone_balance_sheet.png`, `services_phone_features.png`, `services_phone_hidden_feature.png`, `services_small_phone_large_text.png` (360 px, 200 % text), `trade_phone_home.png`, `retail_phone_home.png`, `legacy_phone_features.png` |

To regenerate the after set:

```
flutter test test/ux/ux_screenshots_test.dart --update-goldens
```

Plain `flutter test` skips these because font rasterisation differs between machines. The before set was rendered from `main` with the same fixture.

---

## 4. Not done here (honest limits)

- **Observed usability testing** with non-technical users (M1.2 exit criterion, M2.4) has not been done. Widget tests and screenshots are not a substitute.
- **TalkBack / VoiceOver** walkthroughs on devices have not been done. Tests cover semantics labels, the Android tap-target and labelled-tap-target guidelines on the shell, and 200 % text.
- **Form-level journeys** (customer, item, quotation, invoice, payment allocation, supplier expense, stock movement, bank reconciliation) gained confirmations, business words and guided empty states. Their field layouts were not redesigned. The guided payment and bank-reconcile screens are unchanged apart from navigation.
- **Retail fiscal compliance** is not claimed. The till's description says fiscal-receipt certification is jurisdiction-specific and not implied (see `MALTA_FISCAL_RECEIPTS.md`).
- **Customer statement** and **bank reconciliation** were not given summary-first phone views. The customer account screen still uses a `DataTable`.
