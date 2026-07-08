# Atlas Team — Two-Device Smoke Test (live backend)

**Purpose:** prove, against the production backend at `team.neuradix.app`,
that two devices share one company's books: a change made on device A
appears on device B with balances intact, offline work catches up, and a
revoked/failed exchange recovers cleanly.

**What this validates:** the replication plane (Team milestones 1–3:
`HttpCloudAdapter`, join-team flow, sync loop).
**What it does NOT validate yet:** backend-authoritative posting — official
submits still post locally on each device, Solo-style. That is the next
milestone ([P3] in `ROADMAP_V2_SOLO_TEAM.md`); see *Known limitations*
before drawing conclusions from conflict-ish scenarios.

**You need:** two machines with the app built from hub `main` (once the
milestone-3 PR is merged), the backend healthy
(`https://team.neuradix.app/health`), and ~20 minutes.

---

## 0. Decide which company to test with

Use a **throwaway company** (the walkthrough below creates "Smoke Test Co").
The smoke test pollutes its company with test invoices — don't run it
against real books.

If you instead want to attach a device to the **already-bootstrapped real
company** (`Busuttil Technologies Limited`, created via PowerShell on
2026-07-08): the app has no "sign in with owner token" flow — attachment is
by invitation. Create one with the saved owner token, then use *Join with an
invitation* on the device:

```powershell
$boot = Get-Content atlas-bootstrap.json | ConvertFrom-Json
$headers = @{ Authorization = "Bearer $($boot.token)" }
Invoke-RestMethod -Uri "https://team.neuradix.app/companies/$($boot.company.id)/invitations" `
  -Method Post -ContentType "application/json" -Headers $headers `
  -Body '{"email":"kevin@busuttil-technologies.com","role":"admin"}'
```

---

## 1. Device A — create the company and connect

1. Launch the app; complete onboarding if this is a fresh install (any
   preset; note the seeded data is device-local until pushed).
2. **Setup → Atlas Team**:
   - Team server: `https://team.neuradix.app`
   - Name this device: `Device A`
   - Under *Start a new Team company*: name `Smoke Test Co`, your email,
     your name → **Create company & connect**.
3. Expect: a "Connected to Smoke Test Co" snackbar; the screen shows the
   company card and the **Sync** card.
4. Press **Sync now**. Expect pending to drop to 0 and "Last synced" to
   stamp. This first push ships the entire local history (manifest install +
   seed + anything you did during onboarding) — it can take a moment.

**Server-side check (optional but recommended):**

```powershell
# The audit feed shows device.register and sync.push entries:
Invoke-RestMethod -Uri "https://team.neuradix.app/companies/<COMPANY_ID>/audit?limit=10" `
  -Headers @{ Authorization = "Bearer <token from the create response — see note>" }
```

> The app stores the owner token it received; the company id is on the
> Team screen's card. If you want API access for checks, create the smoke
> company via PowerShell first instead and join device A by invitation —
> or just rely on the in-app Sync card.

On the droplet, the raw mutation log is visible too:

```bash
sudo docker compose exec postgres psql -U atlas -d atlas \
  -c "select count(*), max(sync_version) from mutations where company_id = '<COMPANY_ID>';"
```

## 2. Device A — invite device B's user

1. Team screen → **Invite a teammate** → email (any address you control),
   role **admin** (broadest surface for a smoke test) → **Create
   invitation**.
2. **Copy the token immediately** — it displays once, works once, and
   expires in 7 days.

## 3. Device B — join and bootstrap from history

1. Fresh install (or at minimum: an install that has never joined this
   company). Complete onboarding minimally.
2. **Setup → Atlas Team**: server `https://team.neuradix.app`, device name
   `Device B`, then *Join with an invitation*: paste the token, your name →
   **Join & connect**.
3. Press **Sync now**. First pull starts at cursor 0 and replays the
   **entire company history** — device A's manifest, seed, and documents all
   apply locally. This is the second-device bootstrap working as designed.
4. Verify: open Customers / Items / the Chart of Accounts and confirm
   device A's records are present. Expect duplicate-looking master data too
   — see *Known limitations* below; it's cosmetic for this test.

## 4. The actual smoke scenario

On **device A**:
1. Create a customer `Smoke Customer` and a service item `Smoke Item`
   (rate 100).
2. Raise and **submit** a Sales Invoice: Smoke Customer, 1 × Smoke Item.
3. Wait for auto-sync (a few seconds after the save burst) or press
   **Sync now**.

On **device B**:
4. Press **Sync now** (or wait ≤30 s for the timer).
5. Verify, in order of increasing strictness:
   - the Sales Invoice list shows A's invoice, docstatus Submitted;
   - the customer's account shows the outstanding balance;
   - **Reports → Trial Balance** balances (debits = credits) and shows the
     revenue and receivable — this proves the ledger re-derivation ran
     locally after the pull rather than trusting wire data.

Then the reverse direction:
6. On device B, record a Payment Entry against that invoice; sync.
7. On device A, sync and confirm the invoice's outstanding drops to 0 and
   the Trial Balance still balances.

## 5. Offline catch-up

1. Put device B in flight mode (or stop its network).
2. On device B: create another invoice. The Sync card shows pending > 0 and
   an error state after the next attempt — expected, nothing strands.
3. Restore the network; **Sync now**. Pending returns to 0.
4. On device A: sync; the offline-made invoice appears. This exercises the
   failed-push-returns-to-pending fix directly against real transport.

## 6. Failure-mode spot checks (5 minutes, worth it)

| Check | How | Expect |
|---|---|---|
| Revoked/garbage token | Edit nothing — just observe after deleting the device row server-side, or skip | Sync card shows the server's `unauthorized` message; no crash; reconnecting re-registers |
| Backend down | `sudo docker compose stop backend`, sync, then `start` | Error state with a transport message; next sync recovers; nothing lost |
| Immutability guard | (After posting-authority milestone) editing a submitted invoice and syncing | The 409 message names the document; today, local edits of drafts sync normally |

## 7. Pass criteria

- [ ] Device B received the full company history on first sync (cursor-0 bootstrap).
- [ ] A submitted invoice created on A appears on B with the same totals and docstatus.
- [ ] Trial Balance balances on BOTH devices after each direction of sync.
- [ ] A payment on B settles the invoice on A after sync.
- [ ] Offline changes on B ship after reconnecting; nothing stuck in the queue.
- [ ] Backend audit feed shows `sync.push` / `sync.ack` rows from both devices.

## Known limitations (current milestone — do not file as smoke-test failures)

1. **Duplicate master data after join.** Both devices ran their own
   onboarding/seed before B joined, so each seeded its own Company /
   chart-of-accounts documents; the join replays A's on top of B's. Same-id
   documents (the deterministic account ids like `Bank`, `COGS`) converge;
   generated-id documents (the Company record, fiscal year) can appear
   twice. Cosmetic for the smoke test; the proper fix is a join-time
   "adopt the remote company, skip local seeding" flow — queued for the
   posting-authority milestone alongside Team-mode onboarding.
2. **Document numbering can collide.** Both devices allocate invoice
   numbers from local counters; simultaneous offline invoicing can mint the
   same id on both sides. The conflict resolver keeps books consistent, but
   gap-free, collision-free numbering under concurrency is exactly what the
   Rust backend's posting authority provides ([P3]) — official numbering
   moves server-side in the next milestone.
3. **Official postings are local.** Submits post GL/stock/COGS on each
   device via the local derivation (then replicate). Team-safe official
   postings — where the backend is the single posting authority and the
   sync plane rejects edits to posted documents (the 409 you may see) — is
   the next milestone; the server already enforces its half.

## Resetting between runs

- **Disconnect** on the Team screen forgets the session (local data stays).
  The pull cursor for that company is also device-local; rejoining the same
  company continues where it left off rather than re-pulling history.
- For a truly fresh device: clear the app's data/documents directory (the
  local database and preferences), relaunch, and it's a new device.
- Server-side, a throwaway company can stay — it's isolated by company id —
  or be removed with SQL on the droplet if you want the audit log tidy.
