# Atlas Solo / Atlas Team — Backend Decision

**Status:** Accepted direction (pre-implementation)
**Date:** 2026-07-06
**Relates to:** `docs/FUNCTIONAL_GAP_ROADMAP.md` (baseline audit), `docs/ROADMAP_V2_SOLO_TEAM.md` (revised roadmap), `docs/STOCK_COGS_IMPLEMENTATION_PLAN.md`

---

## 1. Decision

Neuradix Atlas ships as two editions:

```text
Neuradix Atlas Solo   — local-first, serverless, single-operator
Neuradix Atlas Team   — local-first Flutter client + Atlas Team Rust Backend (Linux)
```

The backend is **Team coordination infrastructure, not generic cloud SaaS**. The correct mental model is:

```text
local-first client  +  backend coordination authority
```

The Flutter client keeps working locally on drafts, masters, capture and preparation work. The **Atlas Team Rust Backend** (also referred to as the **Atlas Team Linux Coordination Backend**) is the authority for official postings, numbering, identity, and everything that requires an always-on network endpoint.

## 2. Why Atlas Team needs a backend

The audit established that the current architecture is deliberately serverless: sync is a mutation log pushed through a `CloudAdapter` whose only real implementation is `FileSystemCloudAdapter` — its own doc-comment says *"There is no central server"* (`mercantis.core.flutter/packages/mercantis_core/lib/src/sync_engine/file_system_cloud_adapter.dart`). That is a sound design for one operator. It cannot deliver the Team promises, because each of these requires an always-on, addressable, trusted party:

| Requirement | Why a shared folder can't do it |
|---|---|
| Payment provider webhooks (Stripe et al.) | Providers must POST to a URL; there is nothing to receive it |
| Online store connectors (webhook mode) | Same — real-time order push needs an endpoint |
| Customer portal / accountant portal | A browser needs a server to talk to |
| Invitations, memberships, real identity | Folder sync has no authentication authority; today every operator is a device-local passcode profile with the `System Manager` role (`hub lib/auth/auth_store.dart`) |
| Official document numbering without gaps | The current `CounterBlockAllocator` hands each device a disjoint block — deliberately **not** gap-free (`core src/naming/counter_block_allocator.dart:8-11`). Only a single allocator can produce a strict legal sequence |
| Safe concurrent official postings | Last-write-wins folder merge cannot serialize two devices submitting against the same stock bin or invoice outstanding amount |
| Central roles/permissions | The granular permission engine exists in core but needs a trusted identity source to mean anything |
| Server-side audit, backup/restore | A folder is not an audit authority and backup is whatever the user's Dropbox does |

## 3. Why Atlas Solo remains serverless

- The single-operator segment (freelancers, owner-operators) gets no benefit from a backend and real costs: accounts, subscriptions, connectivity dependence, hosting.
- The local engine is the **most proven part of the product** — document engine, ledger derivation, stock costing, VAT, guided payments are real and tested. Solo ships on that strength.
- Solo's constraints are honest: manual/polled imports instead of webhooks, share/email sending from the device, local backup/export, one authority (the single user's device) so numbering and posting authority are trivially consistent.
- Solo must still be **accounting-correct**. Stock businesses on Solo get full perpetual inventory (Dr COGS / Cr Inventory Asset) from the local engine — see `docs/STOCK_COGS_IMPLEMENTATION_PLAN.md`, Track A. "Solo" limits coordination, never correctness.
- Solo may *optionally* call out to Neuradix services for downloads only: signed setup packs, templates, updates. Daily operation never depends on them.

## 4. Why Rust for the Team backend

Company policy: *Neuradix should incline toward Rust wherever practical.* Here it is practical, and independently the right call:

1. **The backend's job is correctness under concurrency.** Posting authority means serialized financial transactions, idempotent replays, careful state machines. Rust's type system (sum types for document states, no nulls, exhaustive matching) and ownership model are a strong fit for code where a silent bug corrupts books.
2. **Operational profile.** A micro-business backend must be cheap to host — including self-hosted on a small VPS. A single static Rust binary with predictable memory (no GC pauses, no JIT warmup) behind a reverse proxy is about as small as an always-on ERP authority can get.
3. **Ecosystem maturity is sufficient and stable:** Axum + Tokio + SQLx + PostgreSQL is a boring, well-trodden stack; SQLx gives compile-time-checked SQL against the authoritative schema.
4. **Long-term convergence (Option B).** If the posting engine is ever shared across server and clients, Rust compiles to every target Atlas cares about (Linux server, and via FFI/WASM to desktop/mobile if that day comes). Neither Dart-on-server nor Python offers that path as credibly.

**Why not Dart on the server** (the tempting choice, since the posting logic already exists in Dart): server-side Dart is a niche deployment target with a thin ecosystem for the things this backend is mostly made of (Postgres pooling, migrations, webhook verification, job queues, observability). It would also encourage lifting the *client* engine — with its sqflite/device assumptions — into a role it wasn't designed for, rather than designing a proper multi-tenant authority. The Dart engine's real value is preserved differently: as the Solo engine and as the **reference implementation** the Rust engine must match through shared fixtures (Section 9).

**Why not Python:** acceptable later for narrow, non-authoritative workers (AI/OCR experiments, one-off integration utilities) where its ecosystem genuinely helps. It must not be the authoritative posting engine: dynamic typing and runtime surprises are the wrong trade for double-entry correctness, and the deployment/runtime footprint is worse than a static binary.

## 5. Stack and deployment

| Layer | Choice |
|---|---|
| Language / runtime | Rust, Tokio |
| Web framework | Axum |
| Database access | SQLx (compile-time checked queries), Postgres-native migrations |
| Database | **PostgreSQL — the authoritative store for Team companies** |
| Attachments | Object/file storage (S3-compatible for hosted; local volume or MinIO for self-hosted), content-addressed by SHA-256 to match the existing blob contract |
| Deployment | Linux, Docker Compose (backend + PostgreSQL + proxy + object store) |
| Reverse proxy / TLS | Caddy (default, automatic TLS) or Nginx |
| Backups | Scheduled `pg_dump`/WAL archiving + object-store snapshot; restore drill scripted and documented |
| Jobs/scheduling | In-process Tokio tasks + a Postgres-backed job table (no extra broker for MVP) |

**Hosted vs self-hosted:** the same Compose stack serves both. Neuradix-hosted is the default commercial offering (Neuradix operates upgrades, backups, TLS). Self-hosted is a first-class option for the segment that wants data on-premise — which the local-first ethos attracts. Constraints: single-server assumption for MVP (no HA/clustering), versioned upgrade path required, licence/entitlement check for Team features.

## 6. Authority model

PostgreSQL under the Rust backend is the **single source of truth for a Team company's official state**: submitted documents, GL entries, stock ledger entries and bins, tax transactions, settlements, allocated numbers, identities, memberships, roles, audit log, setup pack versions, consent records.

Client SQLite databases become **replicas plus drafting surfaces**. Everything a client shows is either (a) replicated official state, or (b) local draft/preparation state clearly marked as such.

### Allowed offline/local in Team (drafting plane)

Create/edit draft quotations, draft sales invoices, draft purchase bills; prepare draft stock counts; edit customers/suppliers/items (where safe — see conflicts below); capture receipts; add notes; queue attachments; prepare any non-posted work.

### Backend-required in Team (authority plane)

Submit sales/purchase invoice; post payment; submit stock entry; close POS session; allocate an official document number; post COGS and Inventory Asset movements; reconcile a bank line; process payment webhooks; import an online-store order as an official sale; close a period; official cancellation/reversal.

**No offline official posting in Team MVP.** The client may *preview* totals, tax and expected COGS using its local engine, but the backend response is the official result. A "reserved-authority" offline mode (device pre-authorised to post within limits, reconciled later) is explicitly deferred until designed as its own feature — it must not be promised or half-built in the MVP.

## 7. Sync model

The existing client machinery is reused, not replaced. Two planes:

**Replication plane (drafts, masters, replicated official state).** The client's `SyncEngine` already produces `MutationRecord`s carrying `deviceId`, `userId`, `syncVersion` and a typed payload, against an abstract `CloudAdapter` (`push / pull(afterSyncVersion) / acknowledge` + content-addressed `pushBlob/pullBlob/hasBlob` — `core src/sync_engine/cloud_adapter.dart`). The Team integration is a new **`HttpCloudAdapter`** implementing that same contract against the Rust backend, which persists the mutation log per company in Postgres and serves incremental pulls. Conflict policy stays as today (per-DocType LWW / version-checked merge) **for drafts and masters only**.

**Authority plane (official actions).** Official actions are **not** LWW mutations. They are explicit commands over HTTPS:

```text
client                                Atlas Team Rust Backend
------                                ------------------------
POST /companies/{c}/commands/submit-document
  {doctype, local_draft_id,           validate (schema, permissions, period lock,
   payload, idempotency_key}    →     stock availability, JE balance)
                                      allocate official number
                                      post GL + stock + tax + settlements
                                      write audit row
                               ←      {official_id, number, postings, new balances}
client marks local doc submitted; result state flows to all
devices through the replication plane as backend-authored mutations
```

Properties: idempotency keys make retries safe on flaky connections; commands are serialized per company (Postgres transactions, `SERIALIZABLE` or explicit locking on bins/counters); rejected commands return machine-readable reasons the client surfaces on the draft. The client-side seam already exists — `DocumentEngine.submit()` takes an injectable `inTransaction`/`UnitOfWork` hook (`core src/document_engine/document_engine.dart:595-659`), which in Team mode becomes "send command, await confirmation" instead of "post locally".

**Numbering:** in Team, the backend allocates official numbers at submit time — enabling **strictly sequential, gap-free numbering** where a jurisdiction requires it (resolves the audit's compliance concern about the per-device block allocator). Solo keeps the offline-safe block allocator.

## 8. Identity, roles, audit

- Company / user / device model: users authenticate to the backend (email invitation → account → device registration); devices hold revocable tokens.
- Memberships carry role profiles (Owner/Admin, Sales, Purchasing, Stock, POS, Accountant, Read-only Advisor) which compile down to the **existing core permission-rule model** — the granular engine already present in `core src/permissions/permission_engine.dart` finally gets a real identity source. The backend enforces the same rules server-side on every command (client checks are UX, server checks are law).
- Every command writes an audit row: company, user, device, action, timestamp, before/after references. This supersedes the client-only `audit_log` for official actions; the existing client audit diffs remain for local drafting history.

## 9. Shared correctness: two engines, one truth (Option A)

Decision: **Option A now, Option B later.**

- **Option A (adopted):** Solo keeps the Dart local posting engine (it also remains the Team client's *preview* engine). Team official postings run on the Rust engine. Consistency is enforced by a **shared accounting fixture suite** — language-neutral JSON fixtures (input documents → expected GL entries, stock ledger entries, tax entries, balances, gross margin) executed by both the Dart test runner and the Rust test runner in CI. The mandatory stock/COGS acceptance scenario is fixture #1. Divergence fails both builds. See `docs/STOCK_COGS_IMPLEMENTATION_PLAN.md` §5.
- **Option B (deferred):** if fixture-maintained parity becomes costly, port the posting core to Rust and reuse it server-side first, later evaluating sharing with clients (FFI/WASM). Not now — it would stall the roadmap behind a rewrite, which the audit explicitly warns against.

## 10. Risks

1. **Dual-engine drift** — the central risk of Option A. Mitigation: fixtures are the contract; no posting behaviour ships in either engine without a fixture; fixture suite reviewed as an accounting artefact, not a test detail.
2. **Offline UX cliff in Team.** Users will try to submit invoices in a dead spot. Mitigation: honest UI ("draft queued — needs connection to post officially"), fast retry, and the preview engine showing exactly what will post.
3. **Scope gravity: backend becomes a generic SaaS.** Mitigation: the backend's remit is the authority-plane list in §6 plus portals/integrations — resist moving drafting or reporting logic server-side without cause.
4. **Solo→Team migration.** A Solo company graduating to Team needs take-on: upload documents, re-key or map numbering series, establish opening authority state. Must be designed with the Team MVP, not discovered later.
5. **Self-hosting support burden.** Compose + Caddy + scripted backup/restore keeps it survivable; publish a support matrix (single server, Linux x86-64/arm64) and refuse exotic setups.
6. **Rust capacity.** Smaller talent pool than Dart in-house. Mitigation: the backend MVP surface is deliberately small (mutation log store, command API, identity, audit); the hard accounting semantics arrive with fixtures already written.
7. **Webhook security** (Stripe/store callbacks): signature verification, replay windows and idempotent processing are MVP requirements, not hardening.
8. **Two numbering regimes** (Solo blocks vs Team sequential) must be explicit in docs and in the setup checklist, or accountants will be confused by the difference.

## 11. What this decision does NOT change

- No rewrite of the Flutter apps. The document engine, ledger derivation spine, conversions, guided payments, capture, seeder and banking logic all stay and keep shipping value in Solo and in the Team client.
- Solo is not a demo tier. It is a complete, accounting-correct product for single-operator businesses, including stock/COGS.
- The Phase 1A/1B product work (see `docs/ROADMAP_V2_SOLO_TEAM.md`) proceeds on the existing codebase in parallel with backend design — it is needed by both editions.
