# Atlas Solo — UX acceptance matrix

Release-gate companion to `COMMERCIALISATION_IMPLEMENTATION_PLAN.md` §M1.2. Each row says what must be true, how it is proven today, and what is still owed. **Automated** means a test in this repo (or Core UI) fails if the row regresses. **Owed** items are not proven by widget tests and must not be marked done until observed.

Legend: ✅ proven by automated tests · 🟡 partly proven / partly owed · ⛔ owed (manual or observed evidence required)

## 1. Product scope by profile

| Requirement | Services | Trade | Retail | Evidence |
|---|---|---|---|---|
| No vertical workspaces, sections, items or routes unless switched on (rentals, property, construction, memberships, online channels, hospitality, manufacturing, dispatch, fixed assets) | ✅ | ✅ | ✅ | `test/ux/navigation_scope_test.dart` |
| Approvals only with Atlas Team | ✅ | ✅ | ✅ | `navigation_scope_test.dart` "Approvals appear with Atlas Team"; shell deep-link test |
| Ledger, journals, cost centres and report builder only in the Accountant view | ✅ | ✅ | ✅ | `navigation_scope_test.dart` Owner/Accountant group |
| Every visible item, quick action and workspace is reachable (no link lands on a hidden-feature page) | ✅ | ✅ | ✅ | `navigation_scope_test.dart` "every visible link is reachable" (all presets, Accountant, legacy) |
| Every optional feature reachable from Settings › Business type & features | ✅ | ✅ | ✅ | `test/ux/features_and_presentation_test.dart` |
| Switching a feature applies live (no restart) | ✅ | | | `test/ux/hub_shell_widget_test.dart` |
| Retail till does not claim fiscal certification | ✅ | | | feature copy asserted in `features_and_presentation_test.dart` |

## 2. Phone navigation (≤ 5 destinations)

| Requirement | Evidence | Status |
|---|---|---|
| Services: Today · Customers · Invoices · Money · More | `hub_shell_widget_test.dart`, `navigation_scope_test.dart` | ✅ |
| Trade: Today · Sales · Stock · Money · More | same | ✅ |
| Retail: Today · Till · Stock · Money · More | same | ✅ |
| Bar never points at a switched-off feature | `navigation_scope_test.dart` "never point at a switched-off feature" | ✅ |
| More lists every other visible area and nothing hidden | `hub_shell_widget_test.dart` | ✅ |
| Tablet and desktop keep the rail or sidebar; brand inside the rail | Core `test/shell/layout_resilience_test.dart`; shell layout tests at 1024 and 1440 | ✅ |

## 3. Layout and accessibility

| Requirement | Evidence | Status |
|---|---|---|
| No overflow at 360, 390, 430, 1024, 1440 px (Home, Money, Sales × 3 profiles) | `hub_shell_widget_test.dart` "layouts" (45 cases) | ✅ |
| 200 % text on a 360 px phone: page text scales fully, bar labels clamp at 110 %, grids drop to one column, figures never break mid-number | `hub_shell_widget_test.dart`; Core `layout_resilience_test.dart`; `after/services_small_phone_large_text.png` | ✅ |
| Tap targets ≥ 48 dp and labelled (shell, hidden-feature page) | `meetsGuideline(androidTapTargetGuideline / labeledTapTargetGuideline)` in `hub_shell_widget_test.dart` | 🟡 shell only; forms owed |
| Report figures announce their meaning, not only their colour ("needs attention") | `ReportSummaryView` semantics labels | 🟡 implemented, no device test |
| TalkBack / VoiceOver walkthrough of the 10 journeys | — | ⛔ owed |
| Keyboard-only desktop operation | — | ⛔ owed |
| Contrast audit (light and dark) | — | ⛔ owed |

## 4. Owner / Accountant

| Requirement | Evidence | Status |
|---|---|---|
| Owner uses business words (Post invoice, Record payment, Reverse, Correct, Supplier bills, Money) | `features_and_presentation_test.dart`, `navigation_scope_test.dart` | ✅ |
| Accountant and classic installs keep engine terms | `features_and_presentation_test.dart` | ✅ |
| Journals keep accounting language in both views | `features_and_presentation_test.dart` | ✅ |
| View change never alters posting or permissions | No posting, permission or interceptor code changed (diff); the full posting suite passes unchanged | ✅ |

## 5. Existing installations

| Requirement | Evidence | Status |
|---|---|---|
| Legacy settings document keeps every feature it could reach; explicit offs stay off; migrated once to v2 | `test/hub_settings_test.dart` | ✅ |
| Company with no settings document keeps everything (classic navigation) | `hub_settings_test.dart` | ✅ |
| New install starts minimal, with no developer operator identity | `hub_settings_test.dart` | ✅ |
| Classic installs offered simplified navigation without losing features | `features_and_presentation_test.dart` | ✅ |
| Deep links into a hidden feature explain it and offer the switch; records stay readable | `hub_shell_widget_test.dart` "deep links" | ✅ |

## 6. Critical journeys (brief §E)

| Journey | Entry on phone (Services) | Feedback / states | Status |
|---|---|---|---|
| First-run setup | Onboarding: business type cards, optional extras (off by default), phone-bar preview | Saves preset + extras; setup checklist on Home | 🟡 `test/ux/onboarding_profile_test.dart`; observed test owed |
| Create customer | Customers tab → New | "Customer saved on this device"; guided empty state | 🟡 Core form confirmation tested; field layout unchanged |
| Create item / service | More › Sales or Settings › catalogue | Business-language empty state | 🟡 |
| Quotation | Invoices tab (includes quotes) / Home "New quote" | "Finalise quote" → "Quote finalised — ready to send" | 🟡 |
| Sales invoice | Invoices tab / Home "New invoice" | "Post invoice" → "Invoice posted — it now counts in your books" | 🟡 |
| Record / allocate payment | Money › Receive payment (guided) | "Record payment" | 🟡 allocation UI unchanged |
| Supplier expense | Home "Record expense" / Money › Pay | "Record expense"; scan receipt | 🟡 |
| Stock movement | Trade/Retail: Stock tab / Home "Move stock" | "Post movement" → "Stock updated" | 🟡 |
| Bank reconciliation | Money › Bank › Bank reconciliation | Unchanged screen | ⛔ phone redesign owed |
| Financial performance | Money › Financial reports | Summary → attention → drill-down → table | ✅ `test/ux/report_summary_test.dart`, screenshots |

## 7. Reports (brief §F)

| Report | Summary | Exceptions | Drill-down | Detail table | Status |
|---|---|---|---|---|---|
| Profit & loss | profit/loss, income, expenses, margin | loss, no income | account → ledger | ✅ | ✅ |
| Balance sheet | own, owe, net worth | does not balance | account → ledger | ✅ | ✅ |
| AR ageing | owed, 30+, 90+ | parties 90+ late | customer → invoices (filtered list) | ✅ | ✅ |
| AP ageing | owe, 30+, 90+ | suppliers 90+ | supplier → bills | ✅ | ✅ |
| Stock valuation | value, products | negative stock | item | ✅ | ✅ (stock profiles) |
| Gross margin | margin, %, sales | below-cost items | item | ✅ | ✅ (stock profiles) |
| Customer statement | — | — | — | table | ⛔ owed |
| Bank reconciliation | — | — | — | — | ⛔ owed |
