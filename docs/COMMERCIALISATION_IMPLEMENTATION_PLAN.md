# Neuradix Atlas — Commercialisation Implementation Plan

**Status:** canonical implementation sequence for commercial readiness  
**Date:** 2026-09-13  
**Baseline reviewed:** `main` at `35f41dd847890ff1ec9aed3c63cb1dc54534dde6`  
**Applies to:** `mercantis.hub.flutter` and, where explicitly stated, `mercantis.core.flutter` / Atlas Team backend  
**Primary audience:** product owner, Claude Code, ChatGPT/Codex, maintainers and reviewers

> This document is the execution roadmap for taking Atlas from its current state to a commercially ready **Atlas Solo**, then to a commercially ready **Atlas Team**.
>
> `docs/ROADMAP_V2_SOLO_TEAM.md` remains authoritative for the strategic Solo/Team architecture and edition boundaries. Its older eight-phase sequencing is superseded by this document for implementation priority and release gating.

---

## 1. Goal

Reach commercial readiness with the **fewest credible milestones** while avoiding further breadth-first feature expansion.

There are four milestones only:

1. **M1 — Atlas Solo Product Hardening**
2. **M2 — Atlas Solo Commercial Release**
3. **M3 — Atlas Team Multi-user Authority**
4. **M4 — Atlas Team Commercial Release**

The governing rule is:

> Do not add a new vertical, major module, integration family or AI feature while an earlier commercialisation milestone has an open release blocker unless the work directly removes that blocker.

The product already has substantial ERP depth. Commercial readiness now depends primarily on usability, migration, recovery, offline reliability, release engineering, supportability and — for Team — server-side authority and security.

---

## 2. Strategic product boundaries

### 2.1 Atlas Solo

Atlas Solo is:

- local-first;
- serverless for normal operation;
- single-operator;
- accounting-correct;
- usable without continuous connectivity;
- responsible for its own local posting, numbering and stock/accounting state;
- backed up/exported locally by the operator.

Conceptually:

```text
Flutter application
        |
        +-- local database
        +-- local document engine
        +-- local accounting/stock engine
        +-- offline-first operation
        +-- local backup/export
```

Solo must not claim multi-user authority, server-side role enforcement, always-on webhooks or central official posting.

### 2.2 Atlas Team

Atlas Team keeps the local-first Flutter client, but introduces a backend as the coordination and official posting authority.

```text
Flutter client
     |
     | local cache / offline drafting
     v
Atlas Team backend
     |
     +-- identity and membership
     +-- roles and permissions
     +-- authoritative submission
     +-- official numbering
     +-- authoritative stock availability
     +-- authoritative GL / subledger posting
     +-- sync and conflict coordination
     +-- audit
     +-- webhooks / scheduled integrations
     +-- backup / recovery
     v
PostgreSQL + blob storage
```

The backend is not a reason to rewrite working Solo behaviour indiscriminately. Shared accounting fixtures must prove that Solo and Team produce equivalent official accounting results where the same transaction is supported.

---

## 3. Current baseline and scope freeze

At the reviewed baseline, Atlas already contains or substantially contains:

- customer, supplier and item masters;
- quotations, sales orders and sales invoices;
- purchase orders, receipts and purchase invoices;
- payments and settlements;
- returns / credit notes;
- stock ledger and warehouse balances;
- perpetual inventory / COGS accounting;
- tax/VAT logic;
- GL, AR and AP foundations;
- Profit & Loss, Balance Sheet and Cash Flow reporting;
- ageing, stock valuation and gross-margin reporting;
- banking/reconciliation workbench;
- customer statements and reminders;
- offline/local-first document infrastructure;
- multi-device conflict tests and sync foundations;
- setup packs / seeding;
- optional modules including POS, manufacturing, deliveries and vertical packs.

This means **commercialisation is no longer gated on adding more ERP modules**.

### 3.1 Solo 1.0 commercial scope

The following form the Solo 1.0 commercial core and may block release if materially broken:

- Company/setup
- Customers
- Suppliers
- Items/services
- Quotations
- Sales orders
- Sales invoices
- Credit notes / returns
- Purchase orders
- Purchase receipts
- Purchase invoices
- Payments
- Expenses
- Banking/reconciliation
- Stock
- VAT/tax
- GL / AR / AP
- P&L
- Balance Sheet
- Cash Flow
- AR/AP ageing
- Stock valuation
- Gross margin
- Customer statements
- Payment reminders
- Attachments
- Import/export
- Opening data / migration
- Backup/restore
- Offline operation

Optional modules may ship, but **manufacturing, POS, deliveries, hospitality, construction, field service, rentals, projects, online store connectors and AI enhancements must not delay Solo 1.0 unless a chosen first customer explicitly depends on them**.

---

# M1 — Atlas Solo Product Hardening

## 4. Objective

Produce an **Atlas Solo Release Candidate** that one real small-business owner can install, configure, migrate or start fresh, operate through normal daily work, close/review the books, back up and restore without developer intervention.

M1 is complete only when product correctness and product usability are both demonstrated.

---

## 5. M1 work packages

Execute these work packages in order unless a dependency requires a small reorder.

### M1.1 — Commercial acceptance baseline and scope guard

Create and maintain a commercial acceptance suite that expresses the product Atlas intends to sell.

Required work:

1. Add a named automated/integration suite for the canonical Solo business journey.
2. Inventory the current implementation behind every Solo 1.0 scope item.
3. Classify discovered gaps as:
   - `BLOCKER-SOLO-RC`
   - `BLOCKER-SOLO-GA`
   - `PILOT`
   - `POST-GA`
4. Remove or clearly label any reachable mock/demo path in the Solo core.
5. Prevent unrelated scope expansion while a `BLOCKER-SOLO-RC` remains.

Canonical business journey:

```text
Create business
 -> configure fiscal/tax basics
 -> create customer
 -> create supplier
 -> create stocked item and service item
 -> buy stock
 -> receive stock
 -> post supplier invoice
 -> pay supplier
 -> create quotation
 -> convert/order
 -> deliver
 -> invoice
 -> receive part payment
 -> receive final payment
 -> return item / issue credit
 -> record expense
 -> import bank statement
 -> reconcile
 -> run VAT/tax summary
 -> run P&L
 -> run Balance Sheet
 -> run stock valuation
 -> run AR/AP ageing
 -> produce customer statement
 -> back up
 -> restore into a clean installation
```

Accounting assertions must include, where applicable:

- balanced GL;
- correct inventory asset;
- correct COGS;
- correct receivables/payables;
- correct invoice outstanding amounts;
- correct stock quantity/value;
- reversal/cancellation nets correctly;
- restored data reproduces the same accounting totals.

**Exit criterion:** the canonical journey is represented by repeatable tests or scripted acceptance steps, and every failure maps to a tracked release classification.

---

### M1.2 — UX, onboarding and mobile usability

Treat UX/UI as a commercial release gate equal to accounting correctness.

#### First-run journey

The normal path must be:

```text
Install
 -> Create business
 -> Country / currency / VAT
 -> Business type / setup pack
 -> Seed configuration
 -> Setup checklist
 -> Import existing data OR start fresh
 -> Ready to trade
```

A user must not discover mandatory accounting setup only when posting the first transaction.

Minimum setup checklist:

- business details;
- financial/fiscal year;
- chart of accounts;
- VAT/tax setup;
- invoice/document numbering;
- bank/cash account;
- customers or explicit skip;
- items/services or explicit skip;
- opening balances or explicit "new business" decision;
- opening stock when stock is enabled.

#### Business-language pass

Keep engine terminology internally but use task language in normal operator surfaces.

Examples:

| Engine/domain action | Preferred normal-mode UI |
|---|---|
| Submit Sales Invoice | Post invoice |
| Submit Purchase Receipt | Receive goods |
| Payment Entry | Receive payment / Pay supplier |
| Cancel | Reverse / cancel |
| Amend | Correct / create corrected version |
| Stock Entry | Move stock / Adjust stock / Receive stock, context-dependent |
| Journal Entry | Keep in accounting/advanced mode |

Do not rename accounting concepts where precision would be lost; instead use an **Advanced/Accounting mode** for terminology intended for accountants and ERP specialists.

#### Mobile-first information design

Primary phone/tablet flows must not be desktop tables merely scaled down.

For key reports use:

```text
Summary -> Exceptions -> Drill-down -> Raw transactions
```

At minimum optimise:

- P&L;
- Balance Sheet;
- AR ageing;
- AP ageing;
- customer statement;
- stock valuation;
- bank reconciliation.

#### Empty/loading/error/offline states

Every primary surface needs explicit states. Examples:

- `No sales invoices yet — create one or convert an accepted quotation.`
- `No bank transactions imported — import a statement to begin reconciliation.`

Offline/sync state must clearly distinguish:

- saved locally;
- waiting to sync;
- synced;
- conflict requires attention;
- operation failed.

A user must never be left unsure whether data was saved.

#### Accessibility acceptance

Critical flows must be tested for:

- TalkBack;
- VoiceOver;
- keyboard-only desktop operation where appropriate;
- large text / display scaling;
- touch target size;
- contrast;
- destructive action confirmation;
- error recovery without colour-only meaning.

**Exit criterion:** representative non-technical users can complete the critical daily tasks without developer coaching, and no critical workflow depends on hidden gestures, unexplained ERP jargon or desktop-only layout assumptions.

#### M1.2 status (October 2026)

Evidence: `docs/ux/SOLO_MOBILE_UX_AUDIT.md` (audit, before/after) and `docs/ux/UX_ACCEPTANCE_MATRIX.md` (row-by-row proof).

- **Done, automated:**
  - Product scope follows the business profile at workspace, section, item, quick-action and deep-link level, through an opt-in feature catalogue in Settings › Business type & features.
  - Phone bar of at most five destinations per profile (Services: Today · Customers · Invoices · Money · More; Trade: Today · Sales · Stock · Money · More; Retail: Today · Till · Stock · Money · More).
  - The Owner/Accountant view is now meaningful: business-language lifecycle words versus engine terms, with Ledger, trial balance, registers and report builder in the Accountant view only.
  - Legacy installations keep every feature they could reach. Settings are migrated once to `settings_version: 2`.
  - Save, submit and cancel are confirmed; empty states are guided.
  - Summary-first phone reports for P&L, Balance Sheet, Cash flow, AR/AP ageing, stock valuation, gross margin and project profitability.
  - Layout verified at 360–1440 px and at 200 % text.
- **Owed (blocks the M1.2 exit criterion):**
  - Observed sessions with non-technical users.
  - TalkBack/VoiceOver and keyboard-only walkthroughs.
  - Contrast audit.
  - Phone-first customer statement and bank reconciliation.
  - Field-layout review of the ten critical forms.
- **Not claimed:** Maltese fiscal-POS approval. The till's own copy says certification is jurisdiction-specific.

---

### M1.3 — Opening data and migration

Build a repeatable opening-data process suitable for a real implementation, not merely generic CSV import.

The opening-data flow must support, as applicable:

1. customers;
2. suppliers;
3. items/services;
4. UOMs and prices;
5. warehouses;
6. opening stock quantity and value;
7. open receivables;
8. open payables;
9. GL opening balances;
10. bank/cash opening balances;
11. optional open sales/purchase documents where explicitly supported.

Provide reconciliation output after import:

```text
Opening Trial Balance      balanced / difference
Accounts Receivable        amount
Accounts Payable           amount
Stock valuation            amount
Bank/cash                   amount
```

Import must be idempotent or safely restartable where practical. Validation errors must identify the source row and corrective action.

#### Required migration acceptance fixture

Take a representative legacy dataset and demonstrate:

```text
Legacy Trial Balance  == Atlas Trial Balance
Legacy AR             == Atlas AR
Legacy AP             == Atlas AP
Legacy inventory      == Atlas inventory valuation
Legacy bank/cash      == Atlas bank/cash
```

Use a documented rounding tolerance only where the source data itself requires one.

**Exit criterion:** a fresh Atlas Solo company can be taken from legacy/opening data to a reconciled opening position without manual database edits.

#### M1.3 status (October 2026)

Evidence: [SOLO_OPENING_DATA_MIGRATION_GUIDE.md](SOLO_OPENING_DATA_MIGRATION_GUIDE.md) and [SOLO_ACCEPTANCE_MATRIX.md](SOLO_ACCEPTANCE_MATRIX.md).

- **Done, automated:**
  - Setup › Move from another system, with nine CSV templates: customers, suppliers, warehouses, items/UOM/prices, opening stock qty/value, open AR, open AP, trial balance, bank/cash.
  - Column mapping with aliases.
  - A dry run that writes nothing, with row-level verdicts and a downloadable rejected-rows file.
  - Duplicate and conflict detection that never overwrites.
  - All-or-nothing posting sections.
  - Idempotent re-import and resume after an interrupted run, using deterministic ids, so a retry never posts twice.
  - Exact cents, with no invented values.
  - Reconciliation as at the opening date: TB per account, AR/AP per party, stock per item and warehouse, bank against statement, Opening Balance Equity must net to zero, and drill-down to vouchers.
  - Tests: `test/opening_take_on_test.dart`, `test/opening_data_screen_test.dart`, `test/solo_acceptance_test.dart`.
- **Owed:** the same flow run on a **real legacy dataset** from the first design partner (M2.2). Optional open sales/purchase documents (item 11) are not supported. Open invoices come over as balances only.

---

### M1.4 — Backup, restore and disaster recovery

Provide obvious user-facing backup and restore actions.

A Solo backup must contain sufficient information to reconstruct the business, including:

- application database;
- attachments/blobs required for records;
- relevant local configuration;
- setup-pack/version metadata required for compatibility;
- schema/build/version metadata.

Required acceptance drill:

```text
Create representative business
 -> back up
 -> remove Atlas application data
 -> fresh installation
 -> restore
 -> verify documents
 -> verify attachments
 -> verify Trial Balance
 -> verify AR/AP
 -> verify stock valuation
 -> verify bank/cash
```

Restore must fail safely on incompatible/corrupt backups and must never partially overwrite a healthy live company without explicit recovery handling.

**Exit criterion:** the full drill succeeds from a clean installation and is documented for customers/support.

#### M1.4 status (October 2026)

Evidence: [SOLO_BACKUP_AND_RECOVERY.md](SOLO_BACKUP_AND_RECOVERY.md) and [SOLO_DATA_INTEGRITY_AND_THREAT_MODEL.md](SOLO_DATA_INTEGRITY_AND_THREAT_MODEL.md).

- **Done, automated:**
  - Setup › Preferences › Backup & restore, plus "Restore from a backup instead" on the first-run screen.
  - Encrypted `.atlasbackup` (Argon2id + AES-256-GCM STREAM, `package:cryptography`). The passphrase is never stored.
  - Consistent DB snapshot, attachments verified by SHA-256, non-secret preferences, schema/app/build metadata, and a business summary.
  - Staged restore with typed confirmation, a journalled atomic swap, verification to the cent, rollback at every step, recovery at startup, and a safety copy.
  - The drill from a representative business into an **empty data folder** reproduces every table, report and attachment exactly, and normal use resumes (`test/solo_acceptance_test.dart`).
- **Owed (BLOCKER-SOLO-RC):** run the same drill on a physical Android and iOS device (uninstall, reinstall, restore from cloud storage) and record it. Until then, disaster recovery on mobile is not claimed as proven.

---

### M1.5 — Offline and adversarial reliability

Run failure-oriented tests, not only happy-path sync tests.

Minimum scenarios:

| Scenario | Required outcome |
|---|---|
| Internet loss during document editing | Local work survives |
| Process/app killed during save | No partial/corrupt document |
| Repeated connectivity flapping | Idempotent convergence |
| Two devices edit same master | Explicit conflict; no silent overwrite |
| Duplicate/replayed remote mutation | One logical result |
| Attachment transfer interrupted | Recoverable retry |
| Device resumes after long offline period | Deterministic reconciliation/conflict handling |
| Upgrade with pending local work | No lost edits/postings |
| Storage/database error | Clear failure; no silent corruption |
| Restore followed by normal operation | New mutations remain valid |

Where conflicts are user-resolvable, provide a comprehensible comparison. For important masters, prefer field-level differences over an opaque `mine/theirs` choice.

Core invariant:

> After every supported failure scenario, the books remain mathematically correct and no user-entered information disappears silently.

**Exit criterion:** the documented failure matrix is green or every known exception is explicitly excluded from the supported commercial behaviour.

#### M1.5 status (October 2026, Solo scope)

Evidence: [SOLO_ACCEPTANCE_MATRIX.md](SOLO_ACCEPTANCE_MATRIX.md) (scenario by scenario).

- Saves, submits, cancels, deletes and migrations are now transactional.
- A **posting outbox** guarantees that no submitted document is left without its GL, stock and party postings: they are completed at the next start after a crash, write failure or full disk.
- Attachments are written atomically. Newer-schema databases are refused.
- Fault injection uses real SQLite failures (`RAISE` triggers, `max_page_count`) and SIGKILL of child processes. It covers save and submit kills, write failures, low storage, repeated restart, long offline periods, double submit, attachment interruption, interrupted backup and restore, and an upgrade across every schema version.
- Multi-device scenarios (two devices editing the same master, replayed remote mutations) belong to Atlas Team (M3) and were not changed.

---

### M1.6 — Release engineering, diagnostics and supportability

Define the official Solo platform matrix. The repository currently contains multiple platform targets; commercial support must be explicit rather than inferred from project folders.

For every supported platform define:

- minimum supported OS;
- installation mechanism;
- release/signing requirements;
- upgrade mechanism;
- tested device/layout classes;
- backup location/behaviour.

CI/release validation should include, for supported targets where automation is practical:

- `flutter analyze`;
- unit/widget tests;
- commercial acceptance/integration tests;
- release-mode build;
- database migration from the previous supported release;
- backup/restore test;
- selected visual/golden tests for critical workflows.

Support diagnostics must provide an exportable bundle or equivalent containing non-secret diagnostic information such as:

- Atlas version/build;
- database/schema version;
- enabled modules/setup packs;
- sync/offline state;
- recent application errors/logs;
- diagnostic IDs needed to correlate failures.

The diagnostic mechanism must avoid leaking credentials, payment secrets or unnecessarily exporting personal/customer data.

**Exit criterion:** a support case can be diagnosed without asking the customer to query SQLite manually or install a development environment.

#### M1.6 status (October 2026)

Evidence: [release/SOLO_RELEASE_READINESS.md](release/SOLO_RELEASE_READINESS.md), the gate-by-gate tracker. Per-gate detail and residual issues live there, not here.

- **Done, automated:**
  - **Platform matrix:** [release/PLATFORM_MATRIX.md](release/PLATFORM_MATRIX.md) gives four levels per platform (implemented, buildable, tested, commercially supported). Every platform is buildable and none is yet tested on hardware.
  - **Permanent app id:** `com.neuradix.atlas` on every platform (product-owner decision, 22 Oct 2026).
  - **Android:**
    - release signing comes from `key.properties` or CI secrets, and is never the debug key;
    - the signed build fails closed when the key is missing;
    - OS Auto Backup is off, because it copied unencrypted books and cloned the device id;
    - the `INTERNET` permission is declared.
  - **iOS and macOS:** the Xcode projects are now in source control (a clone could not build before). The iOS camera and photo privacy strings are added.
  - **Pipeline:**
    - committed `pubspec.lock` with `--enforce-lockfile`;
    - Solo acceptance gate in CI, including accessibility guidelines and the host performance baseline;
    - gitleaks, OSV and committed-key checks;
    - release builds for Android, iOS, macOS and Windows, with stamped version and build number and checksums;
    - a signed Android job behind a protected `release` environment.
    See [release/RELEASE_PROCESS.md](release/RELEASE_PROCESS.md) and [release/RELEASE_SIGNING_AND_SECRETS.md](release/RELEASE_SIGNING_AND_SECRETS.md).
  - **Support diagnostics** are in Settings › Help & diagnostics, and on the start-up error screen. They cover version/build/commit, OS, schema and integrity, postings owed, record counts, modules, backup/recovery, sync and recent errors. The report is privacy-filtered, exportable and tested on a populated book (`test/support_diagnostics_test.dart`).
  - **R14 (Bin id collision) verified and guarded.** New item and warehouse codes that would share a Bin are refused (`test/bin_identity_test.dart`).
  - **Host performance baseline** measured on 10k customers and 5k items ([release/PERFORMANCE_BASELINES.md](release/PERFORMANCE_BASELINES.md)).
  - **User guides** 1–8 in [solo/](solo/README.md), and draft commercial policies in [release/policies/](release/policies/COMMERCIAL_POLICY_CHECKLIST.md). These are **not legally reviewed**.
- **Owed:**
  - a production upload key and the first signed build (REL-1, product owner);
  - device runs: R1, performance and TalkBack;
  - Apple and Windows signing;
  - a branded icon (G-ICON).

---

## 6. M1 release gate — Atlas Solo RC

M1 is complete when all of the following are true:

- [ ] Solo 1.0 scope is frozen. *(No recorded freeze decision: tracker M1-1.)*
- [ ] Canonical commercial acceptance journey passes. *(Automated and green in the CI acceptance gate; awaiting acceptance: M1-2.)*
- [ ] No reachable mock/demo data is required for a core Solo workflow.
- [ ] First-run setup reaches an explicit `ready to trade` state.
- [ ] Critical tasks are usable on supported phone/tablet/desktop form factors.
- [ ] Opening-data migration produces a reconciled opening position.
- [ ] Backup -> clean install -> restore succeeds. *(Automated clean-folder restore passes. **Physical device not run: R1, BLOCKER-SOLO-RC.**)*
- [ ] Offline/adversarial matrix has no unresolved data-loss/accounting blocker.
- [ ] Accessibility checks are complete for critical workflows. *(Automated guidelines on 15 screens pass. Manual TalkBack/VoiceOver matrix PENDING: M1-9.)*
- [ ] Platform support matrix is explicit. *(Written: `release/PLATFORM_MATRIX.md`. Awaiting product-owner acceptance of the Android-first recommendation.)*
- [ ] Release builds and upgrade/migration checks are repeatable. *(Four-platform CI release builds and the lockfile are in place. **No signed build yet: REL-1.**)*
- [ ] Support diagnostics are available. *(Implemented and tested. Support process not yet exercised: M1-12.)*
- [ ] There is no known `BLOCKER-SOLO-RC` issue. *(Open: R1, REL-1, A11Y-ANDROID.)*

**Milestone output:** `Atlas Solo Release Candidate`.

Gate-by-gate evidence: [release/SOLO_RELEASE_READINESS.md](release/SOLO_RELEASE_READINESS.md) §2. **Verdict (22 Oct 2026): not RC-ready.**

---

# M2 — Atlas Solo Commercial Release

## 7. Objective

Prove Atlas Solo with a real paying/design-partner business, then release Solo 1.0 only after an actual operating period reconciles successfully.

M2 intentionally contains little architectural development. It converts "the software works" into "a customer has proved the product".

---

## 8. M2 work packages

### M2.1 — Select the first design partner

Prefer:

- owner-operated or very small business;
- one principal operator;
- service or simple trade model;
- moderate transaction volume;
- cooperative feedback relationship;
- not dependent on uncertified Maltese fiscal POS;
- no requirement for Team-only shared official posting.

Avoid using the first production customer to prove several high-risk dimensions at once (for example multi-location, heavy manufacturing and high-volume POS together).

### M2.2 — Real migration and reconciliation

Use their actual opening data. Produce a signed/recorded reconciliation pack containing at least:

- opening Trial Balance;
- AR;
- AP;
- stock valuation where applicable;
- bank/cash balances;
- migration exceptions/resolutions.

### M2.3 — Live operating / parallel validation period

During a representative accounting cycle, compare Atlas results against the previous process or an independently prepared control where feasible.

Validate:

- sales;
- purchases;
- VAT/tax;
- receivables;
- payables;
- stock quantity/value;
- gross margin;
- P&L;
- Balance Sheet;
- bank balance/reconciliation.

Every discrepancy must be classified as:

- product defect;
- migration issue;
- setup/configuration issue;
- source-system issue;
- documentation/training issue.

Do not close the milestone with unexplained differences.

### M2.4 — Observed UX validation

Observe users completing tasks rather than relying only on subjective satisfaction questions.

At minimum observe:

- create customer;
- create quotation;
- create/post invoice;
- receive payment;
- record expense;
- reconcile bank;
- issue credit/return;
- identify overdue debt;
- read P&L;
- back up Atlas.

Repeated hesitation, repeated support questions and repeated wrong-action selection should be treated as product evidence and fixed or documented before GA.

### M2.5 — Commercial operations package

Before Solo GA provide:

#### Installation/update

- supported platform list;
- official download/install route;
- signing/notarisation where applicable;
- update procedure;
- rollback/recovery guidance where applicable.

#### Customer support

- support channel;
- diagnostic export instructions;
- backup/restore instructions;
- supported response/severity policy;
- known-limitations route.

#### Essential documentation

Maintain concise, task-oriented guides:

1. Getting started
2. Business setup
3. Migrating/opening data
4. Daily operations
5. Month-end/accounting review
6. Backup and recovery

#### Legal/product terms

As applicable to the launch market and distribution model:

- licence/EULA;
- privacy notice;
- support terms;
- backup responsibility statement;
- data-processing terms where services process customer data.

#### M2.5 status (October 2026)

**Drafts only:**

- install/update procedure: [release/RELEASE_PROCESS.md](release/RELEASE_PROCESS.md), guides 1 and 7;
- user guides 1–8: [solo/](solo/README.md);
- support and severity policy, EULA, privacy notice and backup statement: [release/policies/](release/policies/COMMERCIAL_POLICY_CHECKLIST.md).

None has been legally reviewed or approved. The legal entity (P-1) and the Apple export-compliance answer (P-7) are open product-owner decisions.

### M2.6 — Solo 1.0 release decision

Do not call Solo commercially ready until the first representative customer has completed enough real operation to validate the relevant accounting cycle and recovery process.

---

## 9. M2 release gate — Atlas Solo 1.0

- [ ] Real customer migrated without manual DB edits.
- [ ] Opening TB/AR/AP/stock/bank reconciled.
- [ ] Representative operating period completed.
- [ ] No unexplained accounting differences remain.
- [ ] Backup and clean restore completed with customer-representative data.
- [ ] Installation/update process proven outside a development checkout.
- [ ] Critical UX tasks do not require developer coaching.
- [ ] Support and diagnostics process is operational.
- [ ] Essential user/admin documentation exists.
- [ ] No known critical data-loss, posting or recovery defect.
- [ ] No known `BLOCKER-SOLO-GA` issue.

**Milestone output:** `Atlas Solo 1.0 — commercially ready`.

Gate-by-gate evidence: [release/SOLO_RELEASE_READINESS.md](release/SOLO_RELEASE_READINESS.md) §3. The pilot procedure is [release/FIRST_CUSTOMER_PILOT.md](release/FIRST_CUSTOMER_PILOT.md). **No pilot has taken place.**

Recommended initial positioning:

> Atlas Solo is an offline-first ERP for owner-operated and small businesses that keeps sales, purchases, stock, banking and accounts available locally without requiring an always-on server.

Do not market Solo as multi-user Team, an always-on integration host, or an approved Maltese fiscal POS unless those claims are separately satisfied.

---

# M3 — Atlas Team Multi-user Authority

## 10. Objective

Add a production-grade coordination/authority backend while preserving the local-first client.

M3 is the largest remaining technical milestone. The release target is an **Atlas Team Release Candidate**, not yet broad commercial GA.

---

## 11. M3 work packages

### M3.1 — Identity, companies, membership and devices

Implement server-side entities and flows for:

- organisation/account owner as needed;
- company/tenant;
- user;
- membership;
- role profile;
- registered device;
- session/token;
- invitation;
- user revocation;
- device revocation.

Required flow:

```text
Owner creates Team company
 -> invites user
 -> user accepts
 -> device registered
 -> role assigned
 -> authenticated access
```

### M3.2 — Team sync transport

Implement the production Team transport over the backend instead of treating a user-managed shared folder as the commercial multi-user authority.

The client remains local-first for supported offline drafting/caching. The server provides company-scoped mutation coordination, versioning and attachment/blob coordination.

Required properties:

- idempotent mutation handling;
- tenant/company isolation;
- device/user attribution;
- deterministic retry behaviour;
- explicit conflict detection;
- resumable attachment transfer where required;
- schema/protocol versioning.

### M3.3 — Conflict policy by record class

Define and enforce different policies for different data classes.

**Masters/drafts:** may permit explicit conflict resolution.

**Submitted financial/stock documents:** never merge destructively. Corrections occur through cancel/reversal/amendment semantics.

**Shared stock:** availability and official mutation order must be authoritative at the server when Team submission occurs.

### M3.4 — Backend-authoritative submission

Official Team submission follows:

```text
local draft
 -> submit command
 -> authenticate/authorise
 -> validate version/state
 -> allocate official number
 -> validate stock / period / permissions
 -> derive official ledger/subledger/stock postings
 -> commit atomically
 -> append audit/event/mutation
 -> return official result
 -> update local cache
```

If any step fails, there must be no partially official document/posting.

At minimum implement authoritative command paths for the official transactions required by the chosen Team 1.0 scope, including core sales, purchasing, payment and stock transactions.

### M3.5 — Shared accounting fixture suite

Create canonical transaction fixtures that run against both:

- Dart/Solo engine;
- Team backend authority.

Example fixture:

```text
Purchase 10 units @ 5
Sell 3 units @ 12
Expected:
  Inventory asset = 35
  COGS            = 15
  Revenue         = 36
  Gross profit    = 21
```

Fixtures must cover at least:

- purchase/receipt/invoice path;
- sale/delivery/invoice path;
- return/credit;
- payment/settlement;
- cancellation/reversal;
- VAT/tax legs;
- stock valuation/COGS;
- concurrency-sensitive stock rejection;
- official numbering uniqueness.

A Team backend accounting change may not ship if the shared fixtures diverge without an explicitly approved semantic difference.

### M3.6 — Server-enforced role profiles

Start with practical commercial role profiles:

- Owner
- Administrator
- Accountant
- Sales
- Purchasing
- Warehouse
- Cashier/POS where enabled
- Read-only/Auditor

The backend must enforce permissions. Hiding a Flutter button is not authorisation.

Test horizontal/vertical privilege escalation and revoked user/device behaviour.

### M3.7 — Central audit

Record at least:

- company;
- user;
- device;
- timestamp;
- operation;
- document/entity;
- version/result;
- request/session correlation ID;
- relevant source metadata where legally/operationally appropriate.

Pay particular attention to:

- submit/post;
- cancel/reverse/amend;
- payments;
- stock movement;
- role/permission changes;
- company/accounting settings;
- period locks;
- integration-originated mutations.

### M3.8 — Team backup, restore and operations baseline

Provide:

- PostgreSQL backup strategy;
- attachment/blob backup strategy;
- encrypted off-site copy strategy where hosted;
- schema migration procedure;
- restore drill into a clean environment;
- documented RPO/RTO target;
- health checks and structured logs sufficient to diagnose sync/posting failures.

**Exit criterion:** a scripted restore reconstructs an authoritative company and clients can resynchronise safely.

---

### M3 status (October 2026)

Evidence-backed progress. The audit and hardening ran on 23 October 2026,
on branch `claude/project-thread-ff896d` of both the hub and the backend.

- **M3.1 identity, membership, devices.** Done and tested. A change found
  that device tokens were not bound to their company. They are now, and
  revocation or a role change takes effect on the next request (backend
  `tests/tenant_isolation.rs`).
- **M3.2 transport.** Done. Two additions:
  - the pull returns the log `head`, so a device ahead of a restored server
    re-pulls from 0;
  - an idempotency key is bound to its doctype and document.
- **M3.3 conflict policy.** Masters and drafts raise manual conflicts, and
  this is proven against the real backend. Ledger rows are server-only.
  Draft ids are now device-scoped in Team: before this, two devices minted
  the same ids and one device's draft silently replaced the other's.
- **M3.4 backend-authoritative submission.** Done for Sales Invoice,
  Purchase Invoice, Purchase Receipt, Delivery Note, Payment Entry and Stock
  Entry, and for offline POS through server confirmation. The sync plane now
  refuses client ledger rows and client lifecycle changes on these doctypes.
  An engine-level guard stops every hub flow from posting locally in Team.
  Journal Entry, Expense and Customer Deposit have no server path and are
  blocked in Team. See `docs/team/TEAM_POSTING_AUTHORITY.md`.
- **M3.5 shared fixtures.** Green on both engines. The 12 backend fixtures
  run on the Solo engine (`test/accounting_contract_test.dart`). This
  surfaced one Solo defect, now fixed: Solo let a paid invoice be cancelled
  while its payment was still allocated.
- **M3.6 roles.** Enforced server-side (fixture 0007, backend API tests).
- **M3.7 audit.** Server audit rows carry company, user, device and action.
  Offline POS confirmations add `offlineFiscal` and `stockShortfalls`.
- **M3.8 backup and operations.** Done in the repository: encrypted off-site
  backup, a restore drill into a clean isolated cluster with ledger
  invariants and a resync check, CI on every change, `/ready`, structured
  logs and a backup-age monitor (backend `docs/OPERATIONS.md`). Two things
  remain: running the drill on a real production backup, and a decision on
  the 24 h RPO.

Real multi-device test: three hub devices against the real backend on
PostgreSQL over HTTP, with no mocks (`tool/team_e2e.sh`, record in
`docs/team/evidence/team-e2e-2026-10-23.md`). It ran in a development
container. It is not the M3 gate's acceptance scenario with real users.

---

## 12. M3 release gate — Atlas Team RC

Run a two-user/two-device acceptance scenario with forced concurrency and intermittent connectivity.

M3 is complete only when:

- [x] Owner can create a Team company. *(hub E2E)*
- [x] Owner can invite, role and revoke users. *(backend `tests/api.rs`, `tests/tenant_isolation.rs`)*
- [x] Devices can be registered and revoked. *(hub E2E: till revoked)*
- [x] Two devices sync masters and drafts through the backend. *(hub E2E)*
- [x] Conflicts do not silently overwrite concurrent edits. *(hub E2E step 3; the draft-id collision is fixed)*
- [x] Official submission is backend-confirmed. *(sync-plane guard, engine guard, hub E2E)*
- [x] Official document numbers cannot duplicate under concurrency. *(backend `tests/posting.rs`, hub E2E step 6, unique index 0011)*
- [x] Submitted official documents are server-side immutable except through valid reversal/amendment flows. *(backend `tests/authority_guard.rs`)*
- [x] Shared stock cannot be over-consumed due to concurrent stale clients. *(SLE expectations plus retry, fixture 0003. Offline POS is the documented exception: shortfalls are reported, not refused)*
- [x] Shared accounting fixture suite is green on both Solo and Team authority. *(12 of 12 on both engines)*
- [x] Roles are enforced server-side. *(fixture 0007)*
- [x] Audit attributes official changes to company/user/device.
- [x] Backup/restore drill succeeds. *(CI job plus a local report; the production-backup drill is still due)*
- [x] Tenant-isolation/security tests have no unresolved critical finding. *(all 25 company routes attacked)*
- [ ] Two-user/two-device acceptance with forced concurrency and intermittent connectivity, run by real users on real devices. *(automated equivalent passes; the human run is still to do)*

**Milestone output:** `Atlas Team Release Candidate`.

---

# M4 — Atlas Team Commercial Release

## 13. Objective

Turn the authoritative Team backend into a commercially operable multi-user product and prove it with a real organisation.

---

## 14. M4 work packages

### M4.1 — Transactional communication

Provide backend-supported sending for selected business documents, for example:

- quotation;
- invoice;
- customer statement;
- payment reminder;
- purchase order.

Track useful delivery state such as:

```text
Queued -> Sent -> Delivered/Accepted by provider -> Failed
```

Do not claim delivery/receipt semantics that the chosen provider cannot prove.

### M4.2 — Payment provider foundation

Implement one provider first behind a provider abstraction.

The accounting path must model:

```text
Invoice
 -> payment link
 -> provider event/webhook
 -> provider clearing account
 -> Payment Entry / settlement
 -> provider payout
 -> fees
 -> bank reconciliation
```

A webhook must not simply flip an invoice to Paid without the corresponding accounting/settlement evidence.

### M4.3 — Always-on integrations

Use Team backend infrastructure for capabilities that require a continuously reachable endpoint or scheduler, including as prioritised:

- commerce webhooks/polling;
- payment callbacks;
- scheduled jobs;
- customer/accountant portals;
- server-side recurring work.

Do not make these prerequisites for Solo.

### M4.4 — Production operations

Before Team GA establish:

- monitoring;
- health checks;
- alerting;
- structured/correlated logs;
- database migration procedure;
- deployment/rollback procedure;
- backup verification;
- secret rotation;
- dependency/security scanning;
- rate limits/abuse controls;
- capacity/retention policy.

### M4.5 — Security review

At minimum test:

- cross-tenant data access;
- horizontal privilege escalation;
- role forgery;
- company-id forgery;
- replayed submit commands;
- duplicate submit commands;
- stale-version submit;
- revoked user;
- revoked device;
- malicious/oversized attachment behaviour;
- webhook replay/idempotency;
- rate abuse;
- secret/token handling.

Hard release invariant:

> A user or device belonging only to Company A must not be able to read, mutate, enumerate or infer Company B's protected business data.

### M4.6 — Real multi-user pilot

Use a real business with at least:

- owner/administrator or accountant;
- second operational role (for example sales or purchasing);
- warehouse/operations role where stock is in scope;
- at least two simultaneously active devices.

Force rather than avoid:

- concurrent edits;
- offline periods;
- concurrent submissions;
- user revocation;
- device replacement;
- backup/restore;
- month-end/report comparison.

---

### M4 status (October 2026)

- **M4.4 production operations.** In the repository: health and readiness,
  correlated structured logs with token redaction, a backup-age monitor
  with a webhook alert, an additive-only migration policy with safe binary
  rollback, secret rotation and incident response (backend
  `docs/OPERATIONS.md`). Still open: configuring the external uptime check
  and alert channel, and proving that they fire.
- **M4.5 security review.** Done with negative tests:
  - cross-tenant access, company-id forgery and confused-deputy probes on
    every route;
  - device-token company binding;
  - revoked user and device;
  - replayed and duplicate submits (idempotency bound to the command);
  - forged ledger rows, lifecycle and provenance on the sync plane.

  Still open: malicious-attachment behaviour beyond the size limits, and
  dependency scanning in CI.
- **M4.1 email, M4.2 payments, M4.3 integrations.** Not verified end to
  end, so not in Team 1.0 (`docs/team/TEAM_1_0_SCOPE_AND_PILOT.md`).
- **M4.6 pilot.** Planned in `docs/team/TEAM_1_0_SCOPE_AND_PILOT.md` §4.
  **Not started.** No pilot is complete until its external evidence exists.

---

## 15. M4 release gate — Atlas Team 1.0

- [ ] Real Team customer migrated successfully.
- [ ] Multiple users/devices operated concurrently for a representative period.
- [ ] Official accounting/stock remained consistent under concurrency.
- [ ] User/device onboarding and revocation were proven.
- [ ] Team backup and clean restore were proven.
- [ ] Monitoring/alerting detected representative failures.
- [ ] Security review has no unresolved critical/high tenant-isolation or posting-authority issue.
- [ ] Transactional email/integration scope is documented and supportable.
- [ ] Payment-provider accounting is reconciled if payment links are marketed.
- [ ] No known critical data-loss/posting/recovery defect remains.

**Milestone output:** `Atlas Team 1.0 — commercially ready`.

---

## 16. Claims that remain separately gated

Commercial readiness of Solo or Team does **not** automatically authorise every marketing claim.

Examples:

### Maltese fiscal POS

Do not claim Atlas itself is an approved Maltese fiscal POS until the required external approval/certification/EXO process is complete. See `docs/MALTA_FISCAL_RECEIPTS.md`.

### High-volume/multi-till POS

Requires its own operational and concurrency acceptance over the Team authority where multiple tills share official stock/accounting state.

### Automated online store integration

Requires the relevant Team connector/webhook/polling implementation, monitoring and accounting reconciliation.

### Customer/accountant portal

Requires explicit authentication, authorisation, privacy and security acceptance; it is not implied by Team sync alone.

---

## 17. Work that must not block commercialisation

Unless selected first customers make them mandatory, the following belong after the core release gates:

- additional vertical packs;
- deeper manufacturing;
- hospitality expansion;
- construction expansion;
- field-service expansion;
- rental/property expansion;
- more AI features;
- more dashboards for their own sake;
- additional report types without a release use case;
- multiple commerce connectors before the first connector is production-proven;
- additional payment providers before the first is reconciled end-to-end.

The priority is depth, reliability and supportability of the product being sold.

---

## 18. Agent execution contract (Claude Code / ChatGPT / Codex)

This section is intentionally prescriptive so an implementation agent can continue the roadmap without re-planning the whole product on each turn.

### 18.1 At the start of every implementation increment

The agent MUST:

1. Fetch current `main` and repository/PR state.
2. Read this document first.
3. Read `docs/ROADMAP_V2_SOLO_TEAM.md` for architectural boundaries.
4. Read any specific companion document referenced by the selected increment.
5. Follow any applicable `AGENTS.md` if present.
6. Preserve unrelated user changes using an isolated branch/worktree where possible.
7. Re-verify whether the stated gap still exists on current `main`; do not implement stale roadmap work blindly.
8. Select the **earliest incomplete work package** whose prerequisites are satisfied.
9. Keep the increment bounded: one coherent acceptance improvement, with code + tests + docs.

### 18.2 Implementation priority

Unless explicitly redirected by the product owner:

```text
M1.1 Commercial acceptance baseline
 -> M1.2 UX/onboarding/mobile
 -> M1.3 Migration/opening data
 -> M1.4 Backup/restore
 -> M1.5 Offline/adversarial QA
 -> M1.6 Release/supportability
 -> M2 real Solo pilot work
 -> M3 Team authority
 -> M4 Team commercial operations
```

Within a work package, fix `BLOCKER-*` items before `PILOT`, and `PILOT` before `POST-GA`.

### 18.3 Definition of done for an increment

An implementation increment is not complete until:

- production code is implemented;
- tests cover the changed invariant/behaviour;
- existing tests remain green or failures are explained and fixed;
- user-visible behaviour is documented where needed;
- this roadmap or a linked acceptance tracker is updated if status changed;
- mock/demo behaviour is not introduced into a production path;
- offline/local-first behaviour is preserved unless the feature is explicitly Team-only;
- no accounting result is delegated to AI;
- no Team security decision is enforced only in the Flutter UI;
- CI/relevant local checks are run;
- a PR is opened with scope, tests and next recommended increment.

### 18.4 Required handoff format

At the end of each implementation increment, report:

1. **Implemented** — exact commercial acceptance gap closed.
2. **Evidence** — tests/files/CI proving it.
3. **Remaining risk** — any known limitation.
4. **Roadmap status** — which M1/M2/M3/M4 gate changed.
5. **Next increment** — one specific next task, not a broad menu.

### 18.5 Forbidden shortcuts

An implementation agent MUST NOT mark a gate complete solely because:

- a DocType or screen exists;
- a unit test exists without an integrated user path;
- a UI button is hidden for unauthorised users;
- a backup file is produced but never restored;
- sync passes only a happy-path single-device test;
- a report produces rows without reconciliation to its accounting source;
- documentation claims a feature that source/tests do not prove;
- a mock backend or fake data source is used in the shipping path.

---

## 19. The next increment

The default next implementation increment is:

### `M1.1 — Atlas Solo commercial acceptance baseline`

Deliver, in one bounded PR:

1. Add a machine-readable or clearly structured Solo 1.0 acceptance inventory/tracker.
2. Map every Solo core capability in §3.1 to current source/tests/routes.
3. Add or consolidate the canonical end-to-end Solo business fixture/tests where feasible.
4. Identify reachable mocks/stubs in the Solo core path.
5. Classify each uncovered gap as `BLOCKER-SOLO-RC`, `BLOCKER-SOLO-GA`, `PILOT` or `POST-GA`.
6. Update this document only with evidence-backed status changes.
7. End the PR with the exact next recommended M1 increment.

Do **not** start a new vertical or Team feature in this increment.

#### Blocker evidence recorded during the M1.2 increment (October 2026)

**Atlas Solo has no backup or restore path.**

- All of a Solo business's books live in one on-device SQLite file (`mercantis_core_ui/lib/src/providers/core_providers.dart`, `mercantis.db` in the app documents directory).
- A search of both repositories finds no backup, export-database or restore code and no test (`grep -ri "backup\|restore"` matches only a Team-connection comment and the chart-of-accounts repair).
- So a lost or reset device loses the books, and the canonical M1.1 journey cannot complete its last two steps ("back up → restore into a clean installation").

This is `BLOCKER-SOLO-RC`. The recommended order is unchanged (M1.1 first), but M1.1's inventory must record this gap, and M1.4 (§ "Backup, restore and disaster recovery") should follow immediately after.

**Update (Solo data-safety increment, October 2026):** backup and restore now exist and pass an automated clean-folder drill (see M1.4 status). The blocker is **narrowed, not closed**. The physical-device drill remains `BLOCKER-SOLO-RC` until it is executed and recorded in [SOLO_ACCEPTANCE_MATRIX.md](SOLO_ACCEPTANCE_MATRIX.md). The other residual issues from that increment are classified there.

---

## 20. Milestone summary

| Milestone | Purpose | Exit product |
|---|---|---|
| **M1 — Solo Product Hardening** | usability, migration, recovery, offline QA, release/supportability | Atlas Solo RC |
| **M2 — Solo Commercial Release** | real customer proof and commercial operations | Atlas Solo 1.0 |
| **M3 — Team Multi-user Authority** | identity, sync, roles, authoritative posting/stock/accounting | Atlas Team RC |
| **M4 — Team Commercial Release** | integrations, operations, security and real multi-user proof | Atlas Team 1.0 |

The roadmap deliberately stops at four milestones. New feature families should be scheduled against these release gates rather than creating new pre-commercialisation phases.
