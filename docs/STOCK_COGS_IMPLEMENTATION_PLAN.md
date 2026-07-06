# Stock & COGS Implementation Plan (Track A: Solo/Dart engine · Track B: Team/Rust backend)

**Status:** Accepted direction (pre-implementation)
**Date:** 2026-07-06
**Requirement:** Perpetual inventory accounting is **mandatory and a release blocker** for product, retail, POS, distribution and online-store businesses, in **both editions**. Atlas Solo must post `Dr COGS / Cr Inventory Asset` from its local Dart engine; Atlas Team must post it backend-authoritatively in Rust.
**Relates to:** `docs/FUNCTIONAL_GAP_ROADMAP.md` §7/§15.1, `docs/ATLAS_SOLO_TEAM_BACKEND_DECISION.md` §9, `docs/ROADMAP_V2_SOLO_TEAM.md` Phase 1B/3.

---

## 1. Current state (verified in code)

What is **correct today** (keep, build on):

- Stock vs service item distinction enforced end-to-end (`hub lib/ledger/ledger_values.dart:35-42`; service lines filtered in `ledger_derivation_service.dart:89-109`; negative-stock guard skips them, `hub_interceptors.dart:445-447`).
- Moving-average and FIFO issue costing as pure, tested functions (`hub lib/ledger/stock_costing.dart`; `stock_balance.dart`; tests `stock_costing_test.dart`, `ledger_valuation_test.dart`). Issues are costed at valuation, never selling price (`ledger_derivation_service.dart:202-207`, `_costStockMovements`).
- Append-only Stock Ledger Entries → Bin recompute per (item, warehouse) (`ledger_derivation.dart:637-662` `_sle`; `ledger_derivation_service.dart:355-440`).
- Idempotent, deterministic reversals on cancel (`ledger_derivation_service.dart:126-143`) and returns re-entering at **original** issue cost (`_returnCost`, `:260-276`; test `ledger_returns_stock_test.dart`).
- Negative stock blocked unless `Company.allow_negative_stock` (`hub_interceptors.dart:419-476`). UOM conversion at posting (`ledger_values.dart:50-61`).

The **defect** (the reason this plan exists):

- `_stockDocument` (`ledger_derivation.dart:512-545`) and `_stockEntry` (`:468-510`) emit **Stock Ledger Entries only — zero GL legs**. The seeded "Stock In Hand" account is never posted to.
- `_salesInvoice` (`:129-178`) and `_posInvoice` (`:235-272`) post AR-or-cash / revenue / VAT with **no COGS leg**.
- `_purchaseInvoice` (`:180-229`) posts `Dr expense_account / Cr AP` where `expense_account` **defaults to COGS** via `accountFallbacks` (`:66-68`) → `Company.default_expense_account` → seeded `COGS` (`hub_seeder.dart:176`). Goods are fully expensed on purchase: a periodic model in the GL beneath a perpetual subledger.
- There is **no GRNI account flow** and nothing links Purchase Receipt value to Purchase Invoice value (double-count risk).
- The header comment at `ledger_derivation.dart:43-45` **falsely claims** stock vouchers post COGS/inventory. Correct it in the first commit of this work.
- Telling test gap: no test in either repo asserts a `Dr COGS / Cr Inventory` GL leg — the feature is unbuilt, not regressed.

## 2. Target accounting behaviour (both tracks, identical)

**Item setup.** Each item is exactly one of: Stock item / Service item / Non-stock purchase item (Bundle-kit and Manufactured remain later/optional). Stock items resolve three accounts with fallbacks item → item group (optional) → company defaults: `inventory_account`, `cogs_account`, `stock_adjustment_account`; plus default warehouse, valuation method (**Moving Average default**, FIFO advanced — both already implemented), UOM, optional reorder level and barcode/SKU. Negative stock stays **blocked by default**; the existing company-level override remains the advanced escape hatch.

**Purchase of stock item — two supported shapes:**

- *One-document business* (`update_stock = 1` on Purchase Invoice): `Dr Inventory Asset (net) · Dr Input VAT · Cr Accounts Payable (gross)` + stock receipt SLE at the invoice line rate.
- *Two-document business* (Receipt then Invoice): Receipt posts `Dr Inventory Asset / Cr GRNI ("Stock Received But Not Billed")` at receipt valuation; Invoice posts `Dr GRNI / Dr Input VAT / Cr Accounts Payable`. Invoice-vs-receipt price differences post to a price-variance account (MVP: expense the variance; per-unit revaluation is a later refinement). Guard: an invoice line linked to a receipt line must not post inventory again — linkage via the existing PO/receipt conversion lineage (`hub lib/modules/selling/hub_document_lineage.dart` pattern, already used for remaining-qty logic in `hub_conversion_actions.dart:342`).

**Sale of stock item** (Delivery Note, POS Invoice, or Sales Invoice with `update_stock = 1`):

```text
Dr Accounts Receivable / Cash        (gross)
Cr Sales Revenue                     (net)
Cr Output VAT / Tax Payable
Dr Cost of Goods Sold                (qty × valuation rate at issue)
Cr Inventory Asset
```

COGS amount = the SLE issue cost the runtime already computes — never the selling price.

**Service item sale:** revenue/VAT only. No SLE, no inventory movement, no inventory COGS (the existing service-item filters already guarantee the stock side; the new GL emission must respect the same filter).

**Sales return / credit note:** reverse receivable, revenue, VAT, **COGS and Inventory** — inventory back at original issue cost (existing `_returnCost` machinery supplies the rate). **Purchase return:** reverse AP and inventory/GRNI. **Cancellation:** the existing reversal deriver flips the new GL legs automatically once they are emitted by derivation (it negates whatever the forward derivation produced).

**Stock count / adjustment:** count sheet (snapshot → count → post) generates an adjustment Stock Entry; positive `Dr Inventory / Cr Stock Adjustment`, negative `Dr Stock Adjustment / Cr Inventory`. **Transfers:** two SLEs as today, **no P&L effect**; single inventory account per company in MVP means no GL movement on transfer.

## 3. Track A — Atlas Solo / current Dart engine

Ordered work items (each lands with tests):

- **A0 — Truth first.** Fix the false comment (`ledger_derivation.dart:43-45`). Add the JE balance-guard interceptor (chain at `hub_interceptors.dart:14-25`) — cheap, protects everything that follows.
- **A1 — Accounts & settings.** Add `inventory_account`/`cogs_account`/`stock_adjustment_account` to Item (+ company defaults on Company, extending the existing `accountFallbacks` pattern in `ledger_derivation.dart:65-73`). Seed `Stock Received But Not Billed (GRNI)` and `Stock Adjustment` accounts in `hub_seeder.dart` (account types already exist in the vocabulary, `accounting_module.dart:46`). Add `stock_enabled` product setting (presets/setup packs drive it).
- **A2 — GL from stock movements.** This is the architectural crux. Today the *pure* `LedgerDerivation` cannot price an issue — cost is stamped later by the runtime (`_costStockMovements`). Therefore GL emission for stock moves in `LedgerDerivationService`, **after** costing: for each costed SLE, emit paired GL legs (issue → `Dr COGS/Cr Inventory`; receipt → `Dr Inventory/Cr GRNI-or-AP-side`; adjustment → adjustment account) with the same deterministic id scheme and reversal behaviour as existing legs. Keep the pure derivation pure; the service composes SLE + GL into one derived set so cancel/reverse stays a single mechanism.
- **A3 — Purchase side.** `update_stock` flag on Purchase Invoice (default per setup pack: on for one-document micro-businesses). Rewire `_purchaseInvoice` for stock lines: inventory (or GRNI clearing when linked to a receipt) instead of `expense_account`; **service/non-stock lines keep today's expense behaviour**. Purchase Receipt gains its GRNI GL leg. Duplicate-count guard via receipt↔invoice line linkage.
- **A4 — Sales side.** `update_stock` flag on Sales Invoice (issues stock + COGS directly for businesses that don't run Delivery Notes). Delivery Note and POS Invoice pick up COGS legs from A2 with no document changes. **POS is not accounting-complete for product businesses until this lands** — see the corrected wording in `docs/ROADMAP_V2_SOLO_TEAM.md` §2.
- **A5 — Count & adjustment workflow.** Count sheet UI over a snapshot-count-post flow producing adjustment Stock Entries (GL via A2).
- **A6 — Reports.** Gross Margin by item/customer (revenue vs COGS legs); Stock Valuation total; **Stock↔GL reconciliation report**: Σ Bin `stock_value` vs Inventory account balance, with per-warehouse breakdown — the user-visible trust check.
- **A7 — Tax-inclusive pricing.** Engine is exclusive-only (`hub_tax_engine.dart:67`). Required for retail/POS pricing; schedule inside this phase because it touches the same interceptor/totals path being reworked.
- **A8 — Migration/take-on.** For existing databases: one-time **inventory take-on journal** (`Dr Inventory Asset / Cr Opening Balance Equity` from current Bin values) generated by an upgrade assistant, plus a cutover rule: documents posted before the cutover keep their historical (periodic) GL; only post-cutover documents post perpetual legs. The reconciliation report must show €0.00 difference immediately after take-on.
- **A9 — Manufacturing (bounded).** Keep stock-only manufacturing, but the completion Stock Entry's consumption/production SLEs get inventory GL legs from A2 so the inventory account stays reconciled. WIP/variance accounting remains explicitly deferred.

**Migration risks:** (1) Receipt+Invoice double-count during transition — the linkage guard in A3 is mandatory, not optional; (2) mixed-period books (periodic history + perpetual future) must be explained in the reconciliation report; (3) COGS-by-default `default_expense_account` must be re-pointed for stock lines only, or service purchases would silently change behaviour; (4) existing Bins with zero-cost history (goods received before costing existed) take on at current valuation rate — flag them in the assistant.

## 4. Track B — Atlas Team Rust backend authority

The Rust engine implements the **same behaviour** (Section 2) as the authoritative poster for Team companies. Design points:

- **Command-scoped transactions.** Each official action (`submit-sales-invoice`, `submit-purchase-invoice`, `submit-payment`, `submit-stock-entry`, `close-pos-session`, `cancel-document`) is one PostgreSQL transaction: validate (schema, permissions, period lock, JE balance, **stock availability** under `SELECT … FOR UPDATE` on bins) → allocate official number → compute issue cost from the authoritative SLE history (same moving-average/FIFO semantics as `stock_costing.dart`) → insert SLEs + GL entries + tax transactions + settlements → write audit row → return the official result. Serializable-or-locked per (item, warehouse) and per numbering series; no partial postings ever visible.
- **Schema (authoritative):** `documents`, `document_lines`, `gl_entries`, `stock_ledger_entries`, `bins` (derived, transactionally maintained), `tax_transactions`, `settlements`, `numbering_series`, `posting_batches` (idempotency: adopt the deterministic-id + reversal-linkage semantics of `core src/posting/posting_batch.dart`, which the Dart runtime itself doesn't yet use), `audit_log`.
- **Cancellation/reversal:** backend emits linked reversal batches (negated legs, `is_reversal`), mirroring the Dart service's semantics so fixtures match.
- **Client preview:** the Team client runs Track A's engine locally to *preview* postings on drafts; on submit-confirmation it replaces preview state with the backend's official result arriving through the replication plane. Preview and official results are expected to match — fixture parity (Section 5) is what makes that promise honest.
- **Enforcement the client can't do:** stock availability across concurrent devices, gap-free numbering, period lock across the company, role checks against server-verified identity.

## 5. Shared fixtures — one truth, two engines

Language-neutral JSON fixture suite, versioned in a shared location, run by **both** the Dart test runner (Solo/local engine) and `cargo test` (Team backend) in CI:

```text
fixture = {
  setup:    accounts, items (stock/service, valuation method), opening state
  actions:  [buy, sell, return, cancel, adjust, transfer, pay ...]
  expect:   gl_entries[], stock_ledger_entries[], tax_entries[],
            bin_balances{}, account_balances{}, gross_margin
}
```

**Fixture #1 is the mandatory acceptance scenario:**

```text
 1. Buy 10 × Item A @ €5            → qty 10, inventory value €50
 2.                                  → GL Inventory Asset = €50
 3. Sell 3 @ €12 (VAT-exclusive)    → qty 7, inventory value €35
 4.                                  → Sales Revenue €36, COGS €15, Gross Profit €21
 5.                                  → GL Inventory Asset reduced by €15 (= €35)
 6. Service-item sale               → no SLE, no inventory/COGS movement
 7. Cancel the sale                 → GL + stock fully reversed
 8. Sales return (post-reinstate)   → inventory back at €5/unit, COGS reversed
```

Additional fixtures: FIFO variant; UOM-conversion purchase/sale; GRNI two-document purchase incl. price variance; negative-stock rejection; adjustment up/down; transfer (no P&L); part-payment settlement; tax-inclusive retail sale; POS session close; multi-line mixed stock+service invoice.

**Acceptance criteria (both tracks):** COGS posts automatically on stock sale, valued at valuation cost; inventory value updates in subledger **and** GL; stock ledger and GL inventory account reconcile to zero difference; service items never touch stock; returns and cancellations reverse both sides; gross margin reporting works. The fixture suite passing in both engines is the definition of done — no product-business release (Solo or Team) ships without it green.
