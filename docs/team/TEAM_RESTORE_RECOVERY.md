# Recovering Team devices after a server restore (C4)

Status: implemented and tested against a real backend on PostgreSQL in
containers. **Physical-device run: PENDING.**

## The problem

Before C4, a device decided the server had been restored only when the log
head was behind its cursor. That misses the common case:

- device A has synced through version 120;
- the server is restored to a backup ending at 90;
- new activity takes the log to 125;
- A reconnects: 125 > 120, so A carries on as if nothing happened. Its
  official records 91–120 are gone from the server, the server may have
  given their numbers to other documents, and A's drafts sent after the
  backup are marked synced but no longer exist anywhere else.

A re-pull from zero would not fix this either: it never removes the
records that exist only on the device.

## Detecting a changed history

The backend keeps a hash chain over its replication log (backend
`src/history.rs`, migration 0013):

```
chain(v) = SHA-256(chain(v-1) || v || mutation id || SHA-256(record))
```

- After every successful sync the device stores the server head and the
  chain value at the head as its **checkpoint**
  (`team_history.dart`, preferences, per company).
- Posting responses (`submit-document`, `cancel-document`) carry the head
  too. The device keeps these as **pending** checkpoints, so if the restore
  loses one of its own postings, that is caught as well.
- Before each sync the device asks `GET …/sync/history?at=<checkpoint>`.
  If the value differs, or the log no longer reaches that version, the
  device is marked **diverged**. Nothing is pushed or pulled, and Team
  posting stops, because every Team submit syncs first.
- The value is computed from the log itself, so restoring a backup cannot
  restore a matching value for later versions. A stored generation number
  could be restored along with the backup; this chain cannot.

Compatibility:

- **Older server** (no `sync/history` route, 404): the device keeps the
  previous behaviour, re-pulling when the head is behind its cursor.
- **Older client:** it does not send the check and the server is
  unchanged for it. That client has the previous limitation, so devices
  must be updated before the next restore drill.
- **Rows from before migration 0013:** they are linked into the chain on
  first use, and the result is the same as if they had been chained when
  written (tested on PostgreSQL).
- **A device with no checkpoint yet** (just updated): it adopts the
  server's current value. The only restore it can catch on that first sync
  is a log shorter than its cursor.

## Recovering a device

The Team screen shows **The Team server was restored from a backup** and
**Recover this device…** (`team_recovery_screen.dart`). The steps
(`TeamHistoryRecovery`):

1. **Encrypted copy** of the device's books, with a passphrase the user
   types twice. The recovery does not start without it.
2. **The server's books** are rebuilt in a staging file from the server
   alone, under a separate sync identity so that the device's own records
   are fetched too.
3. **Lost official records.** Every submitted or cancelled official
   document on the device that the server does not have, or whose
   cancellation the server does not have, is listed with its number, date,
   party and total. The list goes to `POST …/commands/report-lost-history`
   (owner, admin or accountant). The server:
   - answers which numbers it has since given to other documents;
   - raises each series past the lost numbers, so they are never issued
     again;
   - writes an audit row.

   Lost documents are **not** re-posted automatically. They are re-entered
   from the paperwork. A till or sales device cannot send the list; its
   report says so and keeps the list.
4. **Work the server never had** is carried into the new book and sent on
   the next sync:
   - unsent drafts and master edits;
   - drafts that had been sent but that the restore removed (sent again as
     new);
   - offline till sales awaiting confirmation (confirmed on the next
     sync).

   An unsent edit to a document that the server now holds as official is
   not applied; it is listed instead.
5. **Checks** on the rebuilt book: the trial balance balances, stock agrees
   with the inventory accounts, and customer and supplier balances agree
   with the ledger. A failure means no switch is offered.
6. **Switch**, with Atlas stopped, using the crash-safe switch from C3. The
   old book is archived first, with `recovery-report.json` beside it. The
   cursor and checkpoint then come from the rebuilt book, and the mark is
   cleared.

Every step before the switch leaves the live book as it is. A recovery that
fails or is interrupted can simply be run again; the staging file is
rebuilt each time.

The screen states the consequence of the RPO: anything entered on the
server after its last backup (at most 24 hours) can be affected.

## Evidence

| Scenario (brief C4.1) | Test | Result |
|---|---|---|
| 1. Restored behind the cursor, no new activity | `test/team_e2e/team_restore_e2e_test.dart` #1 | Pass |
| 2. Restored and advanced to exactly the old cursor | #2 (same numeric head, different history) | Pass |
| 3. Restored and advanced beyond the cursor | #3 and 4 | Pass |
| 4. Conflicting financial transactions (number reissued) | #3 and 4 | Pass |
| 5. Connection drops halfway through recovery | #5 (live book untouched, re-run completes) | Pass |
| 6. Unsent drafts, and sent drafts the restore lost | #6 | Pass |
| 7. Offline till sale awaiting confirmation | #7 | Pass |
| 8. Several devices recover independently | #8 | Pass |
| Chain, backfill, posting checkpoints, lost-history report, permissions | backend `tests/history.rs` (in-memory store and PostgreSQL) | Pass |
| Device-side check, pending checkpoints, older server, sync stops | `test/team_history_test.dart` | Pass |
| Recover screen and report | `test/team_recovery_screen_test.dart` | Pass |
| Recovery on a real phone and desktop after a production-style restore | Physical devices | **PENDING** |

The end-to-end file takes real `pg_dump -Fc` backups and restores them with
`pg_restore --clean`, as `scripts/restore.sh` does, under a running backend.
After each recovery the device's GL, AR/AP and stock must equal those of a
device that joined fresh after the restore. Run it with `tool/team_e2e.sh`,
which runs it on its own after the other files, because it rewinds the
whole database.

Container results are not device or pilot evidence.
