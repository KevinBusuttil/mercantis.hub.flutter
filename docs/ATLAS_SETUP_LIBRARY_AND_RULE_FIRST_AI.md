# Atlas Setup Library & Rule-First AI Strategy

**Status:** Accepted direction (pre-implementation)
**Date:** 2026-07-06
**Principle:**

```text
Rule-based setup by default
→ AI only when useful
→ user confirms
→ deterministic rule/configuration is stored
→ future execution uses rules, not AI
```

Atlas is **rule-first, not AI-first**: *AI-assisted setup, rule-based execution*. AI is never called continuously during normal ERP operation, and never decides accounting outcomes.

**Relates to:** `docs/ROADMAP_V2_SOLO_TEAM.md`, `docs/ATLAS_SOLO_TEAM_BACKEND_DECISION.md`, baseline audit `docs/FUNCTIONAL_GAP_ROADMAP.md` (§4 "presets are cosmetic", §15.2/15.4).

---

## 1. Why a Setup Library

The audit found the current presets are recorded and then discarded — four hard-coded objects whose enable-flags have no readers (`hub lib/onboarding/business_preset.dart`, `onboarding_screen.dart:37-58`). Meanwhile the seeding machinery underneath is genuinely good: `HubSeeder` idempotently lays down chart of accounts, jurisdiction tax bands (MT/UK/IE/generic), fiscal year and company defaults, with tests. The Setup Library generalises that proven mechanism instead of multiplying hard-coded presets: micro-businesses get a guided, opinionated setup; Neuradix gets one catalogue to maintain and improve across both editions.

## 2. Setup packs

A **setup pack** is a versioned, signed, declarative bundle that configures Atlas for a business shape. Packs are **composable**:

```text
Base Pack:   Malta Small Business            (jurisdiction: CoA, VAT bands, fiscal year, numbering, templates)
+ Module Pack: Stock and COGS                 (stock settings, inventory/COGS/GRNI/adjustment accounts, valuation default)
+ Module Pack: POS                            (POS profile, cash accounts, Z-report card, receipt template)
+ Module Pack: WooCommerce                    (channel defaults, SKU-mapping rules, clearing/fee accounts)
+ Module Pack: Accountant Access (Team)       (accountant role, review dashboard, export defaults)
```

Initial catalogue: Malta service business; Malta retail/POS shop; trade/distribution with stock+COGS; online seller (WooCommerce); online seller (Shopify); freelancer/consultant; light manufacturing; POS-only shop; generic EU VAT-registered micro-business; non-VAT small service business.

A pack may contribute: visible modules/workspaces; chart of accounts (base or delta); VAT/tax setup; default accounts; stock/COGS settings; document numbering; invoice/quotation templates and branding slots; dashboard cards; setup checklist items; recommended roles; workflows; default expense categories; payment methods; POS settings; online store defaults; reports; and **rules** (Section 3).

Pack format: a manifest (id, semantic version, signature, edition requirements, dependencies/conflicts) plus declarative payload sections that map onto existing machinery — seeder-style masters, DocType defaults, checklist definitions, rule sets. **Applying a pack is idempotent and produces a recorded diff** ("what this pack changed") the user can inspect; the same recorded diff powers version upgrades.

**Distribution.** *Solo:* remains serverless — packs are downloaded as **signed bundles** from Neuradix (or side-loaded/imported), cached locally, applied offline; export/import of a company's setup profile is supported; daily work never needs the catalogue. *Team:* the Atlas Team Rust Backend hosts the catalogue for the company, applies packs centrally, versions every setup change, syncs the result to all devices, and can roll controlled setup updates. Onboarding asks a handful of plain-language questions (jurisdiction, VAT-registered?, sells products?, keeps stock?, sells online?, counter sales?) and **deterministic selection rules** propose the pack composition — no AI in the standard path.

## 3. Atlas Setup Rule Engine

One deterministic rule engine, used at setup time *and* as the normal execution layer for repetitive judgement afterwards. It builds on what exists: the sandboxed expression engine in core (`core src/expression_engine/`) evaluates conditions; rules and rule-sets are stored as ordinary DocTypes so they sync, diff and audit like any other document; the bank-matching (`hub lib/modules/banking/bank_matcher.dart`), capture merchant→supplier learning (`Capture Rule`, `hub lib/modules/capture/capture_module.dart:50-68`) and import machinery become rule *consumers* rather than isolated heuristics.

**Rule types:** setup pack selection; module visibility; default accounts; tax treatment; document numbering; dashboard cards; import column mapping; supplier/category mapping; bank transaction categorisation (contains/reference/amount/direction → account/party/tax, optional auto-create expense/transfer, auto-match threshold); receipt categorisation; SKU/item mapping; payment provider fee rules; online channel mapping.

**Every rule is:** deterministic (same input → same output); versioned; explainable ("matched because description contains 'GO' "); auditable; editable by authorised users; exportable/importable; **provenance-marked** — `built-in | user-created | accountant-created | AI-suggested`; and testable where accounting-critical (accounting-affecting rule types carry example cases that run in CI and on edit).

**Tracked per rule:** source/provenance, version, who accepted it, when applied, what it changed, and an `affects_accounting` flag that forces review-before-apply and inclusion in the audit trail.

## 4. Split AI model

### 4.1 Neuradix-paid AI — product-level setup intelligence only

Used sparingly, for: unclear business type; unusual setup requests; new business patterns not covered by packs; choosing/explaining a pack composition; improving the Setup Library itself (aggregate, not per-customer). Data sent is **minimal and structural**, e.g.:

```text
Business description: small shop selling snacks and drinks in Malta
Employees: 3 · Sells products: yes · Keeps stock: yes · Sells online: no · VAT registered: yes
```

Never sent without explicit consent: ledgers, bank files, price lists, customer/supplier lists, document contents.

### 4.2 Customer-private data — deterministic first, consent ladder after

For messy imported spreadsheets, bank transactions, supplier/category mapping, receipt batches, store product mappings, customer/supplier cleanup, private price lists, opening balances:

```text
1. No AI — deterministic rules and pack defaults        (always available, the default)
2. Explicit, per-task customer consent to Neuradix AI   (scoped, revocable, logged)
3. Customer-provided AI provider (bring-your-own-key)
4. Local/private model                                   (future option, if practical)
```

The user chooses; Atlas **never** auto-sends customer-private data to Neuradix-paid AI. Where AI is used on files, inputs are minimised: sample rows rather than whole files, masked values where the task allows (e.g. classify by description pattern, not amounts+parties together).

**Existing precedent to generalise:** the receipt-capture LLM extractor already implements the right pattern — off by default, bring-your-own-key (Anthropic or OpenAI-compatible), invoked only when local confidence is low, monthly quota, silent fallback to local parsing (`hub lib/capture/llm_receipt_extractor.dart`, `capture_settings.dart`, `capture_settings_providers.dart:47-95`). Adopt this as the product-wide provider abstraction. **Required fix:** the API key currently sits in plain SharedPreferences (`capture_settings_providers.dart:57-62`) — move to platform secure storage/keychain before widening AI use.

## 5. AI is never the posting authority

AI must never directly post or decide: GL entries; COGS; VAT/tax; stock valuation; document numbering; payment allocation; official document submission; bank reconciliation finalisation; period close; fiscal year close. These remain deterministic, testable, explainable — enforced structurally: **there is no code path from an AI response to the posting engine.** AI can only produce *suggestions*; suggestions can only produce *proposed rules or proposed values*; only accepted rules/values reach execution.

```text
AI suggests → Atlas validates (schema, account exists, rule syntax, affects_accounting?)
→ user reviews (diff + reason + confidence shown)
→ deterministic rule is created (provenance: AI-suggested, accepted-by: <user>)
→ rule engine executes it from then on — no AI in the loop
→ audit log records suggestion, acceptance and every application
```

Worked example:

```text
AI suggestion  : "Map supplier GO plc to Telecommunications Expense." (confidence 0.86, reason: telecom brand)
Proposed rule  : IF supplier_name CONTAINS "GO" THEN expense_account = Telecommunications
Validation     : account exists; rule flagged affects_accounting → mandatory review
User           : tightens pattern to "GO plc", confirms
Future imports : rule engine applies it deterministically; audit rows reference rule id + version
```

## 6. Safeguards

- AI is **optional**; a company can disable it entirely and Atlas remains fully functional.
- Usage is **metered and budget-limited** (per-company quota; the capture module's monthly-quota counter is the model).
- Customer-private data never goes to Neuradix AI without explicit, per-task, logged consent; imported files are minimised/sampled/masked where possible.
- Every suggestion is reviewable before applying; accepted suggestions become deterministic rules; rules are explainable and provenance-marked.
- Accounting-critical behaviour stays deterministic and covered by the fixture suite (`docs/STOCK_COGS_IMPLEMENTATION_PLAN.md` §5).
- Suggestions carry **confidence and reason**; low-confidence suggestions are visually distinct.
- **Prompt-injection:** imported files and captured documents are untrusted input. AI processing of them runs with no tools/actions, schema-constrained outputs (the capture extractor already forces JSON-schema output), and outputs are treated as data — validated against the rule schema, never executed. Text in an uploaded CSV can propose a mapping; it cannot instruct Atlas.
- AI cannot execute arbitrary actions — the only sinks are "proposed rule" and "proposed field value".
- Provider configuration (which provider, which key, what's enabled) is visible to owner/admin; consent records are inspectable.

## 7. Backend and edition responsibilities

**Atlas Team Rust Backend manages:** setup pack catalogue and versions; company setup profile; applied-setup change history; setup rule versions; rule approval workflow (who may accept `affects_accounting` rules — e.g. Owner/Accountant roles only); AI suggestion logs; consent records; customer AI provider settings (where supported); AI usage metering and budgets.

**Atlas Solo:** downloads and caches signed pack bundles; applies them locally and offline; stores local setup rules; exports/imports its setup profile; optionally calls AI **only if the user enables it** (BYOK or consented Neuradix AI); remains fully functional with AI off and no backend.

## 8. Acceptance criteria

1. Atlas completes standard setup (all catalogue business shapes) **without any AI call**.
2. AI is optional, not mandatory — full function with AI disabled.
3. Solo can download a setup pack, apply it, then run fully offline.
4. Team applies setup packs centrally and syncs them to all devices.
5. Setup pack versions are tracked; upgrades are explicit.
6. Users can see exactly what a setup pack changed (recorded diff).
7. AI recommendations are always reviewable before applying.
8. Accepted AI suggestions become deterministic rules — subsequent executions involve no AI.
9. Every rule displays its provenance: built-in / user-created / accountant-created / AI-suggested.
10. Customer-specific data is never sent to Neuradix AI without explicit consent (verified by an auditable consent record per task).
11. Users can connect their own AI provider for private-data assistance where supported.
12. Normal ERP operation after setup makes zero AI calls.
13. Accounting-critical operations never depend on AI (no code path exists).
14. AI usage is measurable and limited by quota/budget controls visible to the owner.
