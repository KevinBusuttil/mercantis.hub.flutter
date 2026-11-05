# Moving a Solo book to Atlas Team (C3)

Status: implemented and tested in containers. **Physical-device run: PENDING.**

## Why a conversion and not "connect"

Reproduced in `test/team_e2e/solo_to_team_e2e_test.dart` ("connecting a Solo
book with history directly splits the books"): when a Solo book that already
holds submitted invoices, bills or payments connects to a Team company, the
server refuses every official submit (422, server authority). The device
quarantines those mutations as failed and ships everything else. Teammates
then see the issued invoices as drafts with no ledger, while the phone keeps
them posted. The books are split, and the drafts could be numbered a second
time on the server.

The Team screen now refuses Create and Join for a book with issued
documents and offers **Move these books to Atlas Team…** instead
(`test/team_screen_solo_guard_test.dart`).

## What the move does

1. **Preflight** (`SoloToTeamConversion.preflight`). Blocks if: already
   connected, integrity check fails, no company, owed postings, a numbering
   hold, a document dated after the cut-over, the books lock covers the
   cut-over date, the trial balance does not balance, negative stock, stock
   value without quantity, stock not agreeing with the inventory accounts,
   or receivables / payables not agreeing with the party ledgers. Notes:
   foreign currency, drafts, history count, other devices.
2. **Safety backup**, encrypted with a passphrase the user types twice
   (≥ 10 characters), and checked. Not optional. The passphrase is not
   stored.
3. **Team company** created with the user as owner (`createAndConnect`).
   The credentials go to secure storage under a *pending* key until the
   switch, so an interrupted move resumes the same company.
4. **Publish** the non-official documents (accounts, customers, suppliers,
   items, warehouses, settings, drafts) as ordinary sync mutations with
   deterministic ids (`smig-` + hash of migration id, doctype and id), so a
   retry re-sends the same mutations. Ledger rows and submitted vouchers are
   never published.
5. **Take-on** on the server: `POST /companies/{id}/commands/import-solo-opening`
   (Owner, device token). One Journal Entry `SOLO-OPENING-{migration id}`
   posted by the server's own posting engine with every guard in force
   (period lock, balanced lines, accounts, parties and items must exist,
   stock value per account must equal that account's GL). The server checks
   the trial balance, receivables, payables and stock value against the
   figures the device sent, to the cent. Numbering floors make Team
   continue after Solo's last numbers. Idempotent on the migration id; a
   different package for the same id is refused (409); a second take-on,
   or a take-on into a company that already has postings, is refused.
6. **Team book** built on the device from the server (fresh database, full
   sync), then **reconciled** against the Solo figures: every account,
   customer, supplier and stock line. Any difference stops the move with
   the Solo book live and unchanged.
7. **Switch**, with Atlas stopped: the Solo database (with its WAL) is
   copied to `solo-archive/<migration id>/` and the copy must pass
   `PRAGMA quick_check`; then the Team book is renamed over the live file in
   one step. A crash leaves either the Solo book or the Team book live,
   never neither. Nothing is deleted.

## What does not carry over

- Receivables and payables move as **one balance per customer or
  supplier**, not invoice by invoice. Allocating a later payment to an old
  Solo invoice is done against the opening balance.
- Solo invoices, bills, payments and their attachments stay in the archive
  and the safety backup; they are not in Team.
- Foreign-currency balances move in the base currency (preflight notes
  this).
- Numbers are not rewritten. Team uses its own series format and continues
  after Solo's last number (for example Solo `SINV-.2026.-0002`, Team
  `SINV-00003`). The completion notice lists each series.

## Evidence

| Check | Where | Result |
|---|---|---|
| Server take-on, replay, 409 on changed package, second take-on, company already posted, owner only, 10 malformed packages | backend `tests/solo_migration.rs`, in-memory and PostgreSQL 16 | Pass (container) |
| Preflight, package, publish set (negative: no ledger rows), reconcile, crash-safe switch, damaged archive keeps Solo live | hub `test/solo_to_team_test.dart` | Pass (container) |
| Team screen refuses connect for a book with history | hub `test/team_screen_solo_guard_test.dart` | Pass (container) |
| Reproduction, full conversion against a real backend, replay, second device joins, numbering continues | hub `test/team_e2e/solo_to_team_e2e_test.dart` | Pass (container, real backend + PostgreSQL) |
| Move a real Solo book on a phone and a desktop, kill Atlas mid-move, resume | Physical devices | **PENDING** |

Container results are not device or pilot evidence.
