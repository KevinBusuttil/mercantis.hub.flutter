# Neuradix — Domain and Brand Architecture

**Status:** Adopted. This document governs every future naming, URL, and DNS
decision across all Neuradix product families. Companion documents:
`ROADMAP_V2_SOLO_TEAM.md` (Atlas product roadmap),
`ATLAS_SOLO_TEAM_BACKEND_DECISION.md` (Team backend stack),
`ATLAS_SETUP_LIBRARY_AND_RULE_FIRST_AI.md` (setup packs and rule-first AI).

Neuradix is the **parent technology brand** — not an ERP company, not a
robotics company. It must hold, without strain, both of its product
families: business operations software and autonomous-systems engineering.
Every rule below exists to keep that umbrella broad while keeping each
family unmistakable.

---

## 1. Domain ownership summary

Four domains are owned. Each has exactly one job:

| Domain | Job | One-line test |
|---|---|---|
| `neuradix.com` | Parent brand + product-family **marketing** | "Would a prospect read this before buying?" |
| `neuradix.app` | **Live product access** — apps, portals, payment links, sync/connect services | "Does a logged-in user or a webhook hit this?" |
| `neuradix.io` | **Developer/technical** — docs, API references, registries, status | "Would an engineer bookmark this?" |
| `neuradix.eu` | **EU/Malta trust** — compliance, data residency, regional campaigns | "Does this exist to earn EU credibility?" |

A URL that fails its domain's test belongs somewhere else. No exceptions
get created ad hoc; extending this scheme means amending this document.

---

## 2. Product-family brand architecture

```text
Neuradix                                   (parent brand)
├── Neuradix Atlas                         (business operations / ERP)
│   ├── Atlas Solo                         (local-first, serverless, owner-operator)
│   └── Atlas Team                         (local-first client + Rust/PostgreSQL backend authority)
└── Neuradix Robotics Platform             (Rust-first autonomy framework)
    ├── Runtime · Contracts · Registry · Bridge
    ├── Sim · Record/Replay · Safety Authority
    └── Swarm · Fleet · Studio XR
```

Naming rules that follow from this tree:

1. **Neuradix** is the only brand that appears at domain roots.
2. **Atlas** and **Robotics** are peer families; neither may squat on a
   generic name the other could plausibly need (`portal.`, `api.`,
   `registry.`, `dashboard.` are the dangerous ones — see §18).
3. Where a subdomain could be ambiguous, it is **product-qualified**:
   `portal.atlas.neuradix.app`, never `portal.neuradix.app`.
4. A genuinely shared service (e.g. a single status page, a single docs
   site) lives at the parent level with product paths beneath it:
   `docs.neuradix.io/atlas`, `docs.neuradix.io/robotics`.

---

## 3. `neuradix.com` — parent brand and marketing

### Root

`neuradix.com` (and `www.`) is the product-family gateway. It must present
both families with equal weight:

> **Neuradix builds trustworthy software platforms for autonomous systems
> and business operations.**
>
> **[Neuradix Atlas]** Local-first business operations software for micro
> and small businesses.
>
> **[Neuradix Robotics Platform]** Rust-first autonomy framework for
> robotic systems.

Plus corporate pages: about, contact, legal, careers. The root never
deep-links into product UI; it routes to the family subdomains.

### Atlas marketing — `atlas.neuradix.com`

```text
atlas.neuradix.com               product family landing (Solo vs Team chooser)
atlas.neuradix.com/solo          Solo edition: local-first, serverless, one price
atlas.neuradix.com/team          Team edition: shared books, backend authority
atlas.neuradix.com/features      cross-edition feature tour
atlas.neuradix.com/pricing       pricing for both editions
atlas.neuradix.com/setup         guided setup, setup packs, rule-first AI explained
atlas.neuradix.com/stock-cogs    perpetual inventory / real COGS story
atlas.neuradix.com/pos           point of sale
atlas.neuradix.com/online-store  channels: CSV, WooCommerce, Shopify
atlas.neuradix.com/services      services-business preset story (projects, time, billing)
atlas.neuradix.com/distribution  trade/distribution preset story
atlas.neuradix.com/retail        retail preset story
atlas.neuradix.com/download      installers (delivery itself may serve from solo.neuradix.app)
```

### Robotics marketing — `robotics.neuradix.com`

```text
robotics.neuradix.com            platform landing
robotics.neuradix.com/platform   architecture overview
robotics.neuradix.com/runtime    deterministic runtime
robotics.neuradix.com/contracts  contract-driven development
robotics.neuradix.com/sim        simulation
robotics.neuradix.com/record     record/replay
robotics.neuradix.com/safety     safety authority
robotics.neuradix.com/swarm      swarm coordination
robotics.neuradix.com/fleet      fleet operations
robotics.neuradix.com/studio-xr  Studio XR visualization
robotics.neuradix.com/marine     domain pages
robotics.neuradix.com/aerial
robotics.neuradix.com/ground
robotics.neuradix.com/space
```

Core promise for all robotics copy: *let engineers build, test, explain,
deploy and trust robotic systems from simulation through real-world
operation.*

---

## 4. `neuradix.app` — live product access

`.app` is where products run. Two namespaces, one per family, plus a rule:
**Atlas operational services are qualified under `atlas.`** because Atlas
has many customer-facing surfaces (portals, payments, connectors) that
robotics may later mirror.

### Atlas

| Domain | Meaning |
|---|---|
| `atlas.neuradix.app` | Atlas product access / edition selector |
| `solo.neuradix.app` | Optional Solo services (see §7) — never required for daily work |
| `team.neuradix.app` | Atlas Team workspace + hosted backend entry point |
| `sync.atlas.neuradix.app` | Team sync API for local-first clients |
| `portal.atlas.neuradix.app` | Customer/accountant portal (§11) |
| `pay.atlas.neuradix.app` | Invoice/quote payment links (§12) |
| `connect.atlas.neuradix.app` | Integrations + webhook receivers (§13) |
| `api.atlas.neuradix.app` | App-facing Team API, if ever split from `team.` |
| `files.atlas.neuradix.app` | Hosted attachments/PDFs/receipts, if needed |

### Robotics

| Domain | Meaning |
|---|---|
| `studio.neuradix.app` | Studio XR / operator visualization |
| `fleet.neuradix.app` | Fleet management, robot registry, mission dashboards |
| `sim.neuradix.app` | Simulation access, scenarios, digital twins |
| `record.neuradix.app` | Recording/replay, telemetry review, mission reconstruction |
| `registry.neuradix.app` | User-facing registry UI, only if one is ever needed (technical registry lives on `.io`, §5) |

None of the robotics services exist today. The names are **reserved by
this document** so Atlas never takes them and vice versa.

---

## 5. `neuradix.io` — developer and technical

| Domain | Meaning |
|---|---|
| `docs.neuradix.io` | All technical documentation, product-pathed |
| `api.neuradix.io` | Public API reference documentation |
| `registry.neuradix.io` | Technical artifact registry (robotics-first; see below) |
| `packages.neuradix.io` | Package/crate/SDK distribution, if self-hosted distribution is ever needed |
| `status.neuradix.io` | Service status across everything hosted |

### Docs structure

```text
docs.neuradix.io/atlas                    Atlas technical home
docs.neuradix.io/atlas/api                Team API guide
docs.neuradix.io/atlas/webhooks           webhook formats + verification
docs.neuradix.io/atlas/setup-packs        pack format, rule schema, signing
docs.neuradix.io/atlas/team-backend       self-hosting, backup/restore, ops
docs.neuradix.io/atlas/shopify            connector guides
docs.neuradix.io/atlas/woocommerce
docs.neuradix.io/atlas/payments
docs.neuradix.io/atlas/banking

docs.neuradix.io/robotics                 Robotics technical home
docs.neuradix.io/robotics/contracts
docs.neuradix.io/robotics/runtime
docs.neuradix.io/robotics/data-plane
docs.neuradix.io/robotics/sim
docs.neuradix.io/robotics/record
docs.neuradix.io/robotics/bridge
docs.neuradix.io/robotics/registry
docs.neuradix.io/robotics/studio-xr
docs.neuradix.io/robotics/safety
docs.neuradix.io/robotics/swarm
```

### API reference

`api.neuradix.io` is **documentation**, not a serving endpoint (serving
endpoints are `.app`). Product paths when needed:
`api.neuradix.io/atlas`, `api.neuradix.io/robotics`.

### Registry

`registry.neuradix.io` is primarily the **Robotics** technical registry:
contracts, components, capability definitions, drivers, bridge adapters,
runtime packages.

Atlas setup packs do **not** start here. Pack *documentation* lives at
`docs.neuradix.io/atlas/setup-packs`; pack *delivery* is a product
service on `solo.neuradix.app` / `team.neuradix.app`. Only if setup packs
become partner/developer-published artifacts does
`registry.neuradix.io/atlas/setup-packs` open — and that is a deliberate
future decision, not a default.

### Status

`status.neuradix.io` covers, as they come online: Atlas Team, Atlas
Connect, payment links, portals, and robotics Studio/Fleet/Sim services.
One status page for the whole company — trust is shared.

---

## 6. `neuradix.eu` — EU/Malta trust and compliance

| Domain | Meaning |
|---|---|
| `neuradix.eu` | EU-facing brand landing (may redirect to `.com` initially) |
| `atlas.neuradix.eu` | Atlas EU/Malta positioning |
| `robotics.neuradix.eu` | Robotics EU positioning |
| `privacy.neuradix.eu` | Privacy policy, data-processing terms |
| `compliance.neuradix.eu` | Compliance statements, certifications, data residency |

### Atlas EU pages

```text
atlas.neuradix.eu/malta              Malta small-business focus
atlas.neuradix.eu/eu-small-business  EU micro/SME campaigns
atlas.neuradix.eu/gdpr               GDPR-aware setup and data handling
atlas.neuradix.eu/local-first        local-first privacy positioning
atlas.neuradix.eu/vat                VAT/tax regional campaigns (Malta + UK layouts ship today)
atlas.neuradix.eu/accountants        accountant channel (portal, GL export, VAT returns)
```

### Robotics EU pages

```text
robotics.neuradix.eu/eu              EU institutional credibility
robotics.neuradix.eu/research        research collaboration
robotics.neuradix.eu/marine          regional domain focus
robotics.neuradix.eu/safety          robotics safety posture
robotics.neuradix.eu/compliance      GDPR/data processing for robotics telemetry
```

The `.eu` sites carry messaging, not product functionality. Live services
stay on `.app` regardless of where the visitor came from.

---

## 7. Atlas Solo domain behaviour

**Product promise (verbatim, everywhere):**

> Atlas Solo runs locally and does not require a hosted backend for daily
> operation.

Solo may *optionally* call `solo.neuradix.app` for:

- licence activation;
- update checks;
- **signed setup pack downloads** (cached locally; verified offline);
- template downloads;
- optional manual backup;
- support links;
- optional AI-assisted setup, only if the user enables it.

Hard rules:

1. Every Solo feature above degrades gracefully offline. No daily
   workflow — invoicing, stock, COGS, VAT, reports — touches the network.
2. Solo marketing never shows a login wall; `atlas.neuradix.com/solo`
   leads to a download, not a signup.
3. If AI-assisted setup is used: AI is optional, setup packs work without
   it, and the user continues fully offline after setup (per the
   rule-first AI doctrine in `ATLAS_SETUP_LIBRARY_AND_RULE_FIRST_AI.md`).

---

## 8. Atlas Team domain behaviour

Atlas Team is the connected edition and may honestly require
authentication, sync, and backend authority for shared postings.

- `team.neuradix.app` — the Team workspace and hosted backend entry point.
- Team's customer-facing satellites are always product-qualified:
  `portal.atlas.neuradix.app`, `pay.atlas.neuradix.app`,
  `connect.atlas.neuradix.app`, `sync.atlas.neuradix.app`.

Self-hosted Team deployments (the supported single-server Compose stack)
use the customer's own domain — this architecture governs **Neuradix-hosted**
services. Docs for self-hosting live at `docs.neuradix.io/atlas/team-backend`.

---

## 9. Atlas Team Rust Backend — logical domains vs physical deployment

The backend today is **one Axum binary** (auth, membership, sync, blobs,
posting authority — see `ATLAS_SOLO_TEAM_BACKEND_DECISION.md`). The domain
architecture is logical: initially, several names can be CNAMEs to the
same deployment, with the reverse proxy routing by host. This keeps URLs
stable while the deployment topology evolves.

| Logical domain | Serves | Initial physical reality |
|---|---|---|
| `team.neuradix.app` | Workspace + API entry | the backend |
| `sync.atlas.neuradix.app` | `POST/GET /companies/{id}/sync/*` | same backend (CNAME) |
| `pay.atlas.neuradix.app` | payment-link pages + redirects | same backend (CNAME) |
| `portal.atlas.neuradix.app` | portal web app | same backend or static host + API |
| `connect.atlas.neuradix.app` | webhook receivers, connector jobs | same backend (CNAME) |
| `api.atlas.neuradix.app` | reserved | only if API is ever split from `team.` |
| `files.atlas.neuradix.app` | blob/PDF serving | reserved; blobs serve via sync API today |

Webhook paths under `connect.` are fixed now so provider registrations
never need to change:

```text
connect.atlas.neuradix.app/webhooks/stripe
connect.atlas.neuradix.app/webhooks/paypal
connect.atlas.neuradix.app/webhooks/woocommerce
connect.atlas.neuradix.app/webhooks/shopify
```

Splitting a service out later (e.g. `connect.` becomes its own process for
webhook burst isolation) is a DNS/proxy change only — no client, provider,
or document changes.

---

## 10. Atlas Setup Library domain usage

| Concern | Domain |
|---|---|
| Explaining guided setup / packs / rule-first AI to customers | `atlas.neuradix.com/setup` |
| Solo signed-pack download (optional, cached, offline-after) | `solo.neuradix.app` (or `atlas.neuradix.app`) |
| Team setup profile, pack application, rule sync, team-wide versioning | `team.neuradix.app` |
| Pack format, rule schema, partner/developer guidance | `docs.neuradix.io/atlas/setup-packs` |
| Partner-published pack registry (future, only with a real ecosystem) | `registry.neuradix.io/atlas/setup-packs` |

The registry endpoint is explicitly deferred: do not introduce it before
there are third-party pack publishers. Premature registry = maintenance
surface with no ecosystem behind it.

---

## 11. Customer/accountant portals

`portal.atlas.neuradix.app`, with role-scoped paths:

```text
portal.atlas.neuradix.app/customer
portal.atlas.neuradix.app/accountant
```

**Customer portal:** view quotation · accept/reject quotation · view
invoice · pay invoice (hands off to `pay.`) · download PDF · view
statement · upload requested documents.

**Accountant portal:** access authorised client companies · review P&L,
Balance Sheet, VAT, GL, bank reconciliation · export data (the GL journal
export already shipped in-app is the same artifact) · review audit log ·
optionally post adjustments where authorised.

**Rule:** no generic `portal.neuradix.app` unless a genuine cross-family
product selector exists someday. Robotics will plausibly need operator
portals/dashboards; the qualified name prevents the collision now.

---

## 12. Payment links

`pay.atlas.neuradix.app`, short and printable:

```text
pay.atlas.neuradix.app/i/INV-2026-00045          invoice payment
pay.atlas.neuradix.app/q/QUOTE-2026-00012/deposit quote deposit
```

Payment links are a **Team** capability: automatic payment-status
callbacks require the backend's webhook handling (`connect.`) and
backend-authoritative payment posting. Atlas Solo may still generate
manual payment instructions and share invoice PDFs — but live callbacks,
auto-allocation, and paid-status flips are Team functionality, and
marketing must draw that line exactly.

---

## 13. Online store / connector services

`connect.atlas.neuradix.app` is the single home for integrations:
WooCommerce, Shopify, Stripe, PayPal, Square, bank connectors, payment
webhooks, online order sync, SKU mapping, channel sync logs.

Edition split (consistent with the shipped channel pipeline):

| Capability | Solo | Team |
|---|---|---|
| Manual CSV order import | ✅ (shipped) | ✅ |
| Polling while the app is open (WooCommerce) | ✅ (shipped) | ✅ |
| Webhooks / payment callbacks | — | ✅ via `connect.` |
| Scheduled server-side polling | — | ✅ |
| Central SKU mapping + shared inventory sync | — | ✅ |
| Backend-authoritative stock/COGS posting | — | ✅ |
| Payout/fee reconciliation (CSV) | ✅ (shipped) | ✅ (+ automatic via callbacks) |

---

## 14. Robotics Platform domain usage

- Marketing: `robotics.neuradix.com` (§3).
- Technical docs: `docs.neuradix.io/robotics` (§5).
- User-facing services: `studio.` / `fleet.` / `sim.` / `record.`
  on `neuradix.app` (§4).
- Technical registry: `registry.neuradix.io` — contracts, drivers,
  capability definitions, components, adapters, runtime packages.

Separation rules (absolute):

- No Atlas name is reused for a robotics service; no robotics name for an
  Atlas service.
- `sim.`, `fleet.`, `studio.`, `record.`, `swarm.` are robotics-reserved
  on every domain, even where unused today.
- `registry.neuradix.io` is robotics-first; Atlas only ever appears under
  a `/atlas/` path there (§10), never as the registry's identity.

---

## 15. Developer/API/registry/documentation rules

Quick routing table for all future written material:

| Content | Home |
|---|---|
| Product marketing | `atlas.neuradix.com` / `robotics.neuradix.com` |
| Technical docs | `docs.neuradix.io/atlas` / `docs.neuradix.io/robotics` |
| API reference | `api.neuradix.io/atlas` / `api.neuradix.io/robotics` |
| Serving APIs | `.app` domains only |
| Artifact registry | `registry.neuradix.io` |
| Service status | `status.neuradix.io` |
| EU trust/compliance | `neuradix.eu` family |

---

## 16. EU trust/compliance structure

Summarised from §6; the operating rule is: **`.eu` earns trust, `.app`
does work.** Compliance claims made on `.eu` pages must always reflect
what the `.app` services actually do (data location, processors,
retention) — `compliance.neuradix.eu` and `privacy.neuradix.eu` are the
single sources of truth linked from every product footer.

---

## 17. Future naming and reservation notes

- **Reserve early, launch late.** DNS entries cost nothing; renaming a
  live service costs trust. Everything in §22 gets a DNS record now, even
  if it parks on a redirect.
- **Names not yet assigned but predictably needed** — reserve the meaning,
  don't create the service: `swarm.neuradix.app` (robotics),
  `safety.neuradix.io` (robotics safety-authority docs anchor),
  `packages.neuradix.io` (SDK distribution), `id.neuradix.app`
  (single sign-on, only if accounts ever unify across families).
- **Never mint one-off campaign domains** (`neuradix-atlas.com`,
  `atlaserp.eu`, …). Campaigns live at paths under the owned four.
- **Email:** transactional mail should send from the family it serves
  (`@atlas.neuradix.com` or `@neuradix.com`) — never from `.app` hosts.
  Set SPF/DKIM/DMARC on all four roots even where mail isn't sent
  (a locked-down DMARC `reject` on unused domains prevents spoofing).

## 18. Risks of brand/domain confusion — and the mitigations

| Risk | Consequence | Mitigation |
|---|---|---|
| Root `.com` reads as "ERP company" | Robotics looks like a side project to partners/investors | Gateway homepage holds both families at equal weight (§3) |
| Generic subdomains claimed by whichever family ships first | Renames later, broken links, retrained users | Product-qualified names mandated where ambiguity is possible (§2 rule 3) |
| Solo looks cloud-dependent | Undermines the core Solo promise and its differentiation | Solo network touchpoints are enumerated and optional-only (§7) |
| Payment links on an unfamiliar host | Customers hesitate to pay; phishing-shaped URLs | One stable, printable host forever: `pay.atlas.neuradix.app` (§12) |
| Webhook URLs change after providers registered them | Silent integration breakage across customer base | Webhook paths frozen in §9 before any provider registration |
| `registry.` means different things per audience | Developer confusion between robotics artifacts and Atlas packs | `.io` registry is robotics-first; Atlas packs only under `/atlas/` path, and only when an ecosystem exists (§5, §10) |
| `.eu` claims drift from `.app` reality | Compliance/credibility damage in the EU market | §16 single-source rule: `.eu` mirrors what `.app` does, reviewed together |

## 19. DNS/subdomain reservation checklist

Legend: **LIVE** = build a real page/service now · **REDIRECT** = create
DNS + redirect to the right existing page · **RESERVE** = DNS record
parked (or just documented here), no content yet.

### neuradix.com

| Record | Now | Later |
|---|---|---|
| `neuradix.com` / `www` | **LIVE** — family gateway | — |
| `atlas.neuradix.com` | **LIVE** — Atlas marketing | grows pages per §3 |
| `robotics.neuradix.com` | **REDIRECT** → `neuradix.com` robotics section | LIVE when robotics marketing is ready |

### neuradix.app

| Record | Now | Later |
|---|---|---|
| `atlas.neuradix.app` | **REDIRECT** → `atlas.neuradix.com/download` | LIVE product selector |
| `solo.neuradix.app` | **RESERVE** | LIVE with pack downloads/updates |
| `team.neuradix.app` | **LIVE** when hosted Team launches | — |
| `sync.atlas.neuradix.app` | **RESERVE** (CNAME → team backend at launch) | — |
| `portal.atlas.neuradix.app` | **RESERVE** | LIVE with portal MVP |
| `pay.atlas.neuradix.app` | **RESERVE** | LIVE with payment links |
| `connect.atlas.neuradix.app` | **RESERVE** | LIVE with first webhook connector |
| `api.atlas.neuradix.app` | **RESERVE** | only if API splits from `team.` |
| `files.atlas.neuradix.app` | **RESERVE** | only if blob serving splits out |
| `studio.neuradix.app` | **RESERVE** (robotics) | — |
| `fleet.neuradix.app` | **RESERVE** (robotics) | — |
| `sim.neuradix.app` | **RESERVE** (robotics) | — |
| `record.neuradix.app` | **RESERVE** (robotics) | — |

### neuradix.io

| Record | Now | Later |
|---|---|---|
| `docs.neuradix.io` | **LIVE** — start with `/atlas/team-backend` (self-hosting docs exist) | grows per §5 |
| `api.neuradix.io` | **REDIRECT** → `docs.neuradix.io` | LIVE when a public API reference exists |
| `registry.neuradix.io` | **RESERVE** | LIVE with robotics registry |
| `packages.neuradix.io` | **RESERVE** | only if self-hosted distribution is needed |
| `status.neuradix.io` | **LIVE** cheap hosted status page as soon as anything is hosted | — |

### neuradix.eu

| Record | Now | Later |
|---|---|---|
| `neuradix.eu` | **REDIRECT** → `neuradix.com` | LIVE EU landing when campaigns start |
| `atlas.neuradix.eu` | **REDIRECT** → `atlas.neuradix.com` | LIVE with Malta/EU campaigns |
| `robotics.neuradix.eu` | **RESERVE** | LIVE with EU research/procurement pages |
| `privacy.neuradix.eu` | **LIVE** — privacy policy must exist from day one | — |
| `compliance.neuradix.eu` | **REDIRECT** → `privacy.neuradix.eu` | LIVE as certifications accumulate |

Also on day one, on all four roots: SPF/DKIM/DMARC records (DMARC
`p=reject` on any domain that never sends mail), and CAA records limiting
certificate issuance to the chosen CA(s).

---

## 20. Binding rules for all future recommendations

1. Neuradix is the parent brand; the root stays broad enough for both families.
2. Atlas is the ERP/business-operations family; Robotics Platform is a separate autonomy family.
3. `.com` markets, `.app` operates, `.io` documents, `.eu` earns EU trust.
4. Atlas Solo must never appear cloud-dependent; its network touchpoints are §7's list, all optional.
5. Atlas Team openly uses backend/app domains.
6. Product-qualified subdomains wherever ambiguity is possible.
7. Atlas and Robotics never compete for a subdomain meaning; §14's reserved names hold on every domain.
8. Atlas Setup Library: marketing at `atlas.neuradix.com/setup`, delivery on `solo.`/`team.` `.app`, docs at `docs.neuradix.io/atlas/setup-packs`, registry only with a real partner ecosystem.
9. Payment links: `pay.atlas.neuradix.app`. Portals: `portal.atlas.neuradix.app`. Webhooks: `connect.atlas.neuradix.app/webhooks/{provider}` — frozen.
10. Atlas technical docs: `docs.neuradix.io/atlas`. Robotics technical docs: `docs.neuradix.io/robotics`.
11. No generic URLs that conflict with this architecture, in any future document, plan, or implementation.
