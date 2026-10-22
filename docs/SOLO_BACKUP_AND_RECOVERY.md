# Atlas Solo — Backup, restore and disaster recovery

Status: October 2026 (M1.4).

- Code: `mercantis_core/lib/src/backup/` (format, crypto, staged and journalled restore) and Hub `lib/backup/` (business summary, preferences, guards).
- Screen: Setup › Preferences › **Backup & restore**, also reachable from Settings.

## 1. What a backup contains

A `.atlasbackup` file holds everything needed to rebuild the business on a new device:

| Entry | Content |
|---|---|
| `database/mercantis.db` | A **consistent snapshot** of the whole database. Every row is read inside one transaction on the live connection and written to a fresh file, which must pass `integrity_check`. It is never a byte copy of an open file. WAL content is included because it is read through SQLite, and it works on old Android SQLite builds that lack `VACUUM INTO`. Setup packs, numbering, audit log, posting outbox and the sync queue are all in the DB. |
| `attachments/…` | Every attachment the snapshot references, each checked against the SHA-256 recorded in the books **when it is read**. A missing or damaged file is listed in the manifest and shown to the user. It is never silently dropped. |
| `config/preferences.json` | Non-secret preferences only: theme, saved queries, capture settings. |
| Manifest (encrypted) | Format, producer, app version and commit, **schema version**, SQLite `user_version`, row counts per table, file list with sizes and SHA-256, missing attachments, and the **business summary**: document counts, every account's balance, AR, AP, stock value and quantity, bank and cash, attachment count. |

**Never included:**

- the device id (a restored device must draw its own document-number blocks)
- the AI capture API key
- the Atlas Team session
- the company sync folder path
- **the backup passphrase**

## 2. Encryption (no home-made cryptography)

Atlas uses `package:cryptography` 2.9.0, a maintained, widely used library. Primitives:

- **Key derivation:** Argon2id with a 16-byte random salt, 64 MiB memory, 3 passes, parallelism 1 (RFC 9106's second recommended profile). When reading a header, the parameters are bounds-checked, so a crafted file cannot make the restore allocate gigabytes.
- **Cipher:** AES-256-GCM, applied in the standard STREAM construction over 1 MiB segments.
  - Each segment nonce is a 7-byte random prefix, a 32-bit segment counter and a last-segment flag.
  - Each segment is authenticated with the cleartext header as associated data.
  - Reordering, truncation, appending and header edits all fail authentication.
- **Header (cleartext):** magic `ATLASBAK`, format version, creation time, producer, cipher name, segment size, nonce prefix and KDF parameters. It holds **no business data**.

The passphrase belongs to the user alone:

- It is at least 12 characters, entered twice.
- It is never written anywhere.
- **If it is lost, the backup cannot be opened by anyone, including Neuradix.**

The screen says this before the first backup.

## 3. Making a backup

1. Choose **Back up now** and enter the passphrase twice.
2. Atlas writes the backup to `<app data>/backups/` as `<name>.atlasbackup.partial`. It decrypts and verifies the whole file, then renames it. An interrupted or failed backup never leaves a file that looks complete.
3. Choose **Save a copy…** and put the backup somewhere other than this device: a USB drive, cloud drive, email to yourself, or the accountant.
   - Desktop uses a save dialog and copies the file.
   - Mobile uses the system share/save sheet.

The status card shows:

- the last backup time, flagged when older than 7 days;
- any **owed postings**, meaning documents whose ledger rows are still being completed. Back up after they clear.

## 4. Restoring

A restore is staged first and changes nothing live until the user confirms:

1. **Validate:** read the header and reject anything that is not a backup, or a newer format.
2. **Decrypt and verify** into `restore-staging/`. Every segment is authenticated, every file's SHA-256 is checked, and the DB gets an integrity check. A wrong passphrase gives a clear error. If the backup's schema is newer than this app supports, the user is told to update Atlas first.
3. **Explain:** show the company, backup date, app version, document counts, AR/AP/bank figures and any missing attachments. State the implications:
   - everything on this device is replaced;
   - work since the backup is lost unless re-entered;
   - document numbers continue from the backup;
   - folder sync must be chosen again.
4. **Confirm** by typing `REPLACE`. Restore is refused while the device is connected to Atlas Team.
5. **Swap atomically** under a journal (`restore-journal/`). The steps are prepared, then live moved aside, then staged installed, then verified, then committed.
   - Verification re-opens the installed DB and recomputes the **business summary**. It must equal the one recorded at backup time **to the cent**, or the restore is rolled back.
6. **Recover** from an interrupted restore at the next start, before the DB opens:
   - not yet committed: the previous data is put back exactly;
   - committed: cleanup finishes.
7. **Keep a safety copy:** the replaced books are kept in `pre-restore-copy/` until the next restore.
8. **Resume:** the app restarts its provider scope on the restored books. Posting recovery runs, and new documents save, submit and number normally.

An invalid, damaged, incompatible or tampered backup **never touches the live books**. This is tested at every step (§6).

## 5. Recovering after losing the original device

The customer, or support, does this:

1. Install Atlas on the new device and open it. Do **not** create a company. On the first screen, choose **Restore from a backup instead**. If a company was already started, Setup › Preferences › Backup & restore replaces it the same way.
2. Copy the most recent `.atlasbackup` onto the new device: from the cloud drive, USB, email or the accountant's copy.
3. Choose **Restore from a backup…**, pick the file and enter the passphrase.
4. Check the summary against what you know: last invoice, bank balance. Type `REPLACE`.
5. After the restart:
   - check the trial balance and bank balance;
   - re-enter anything done after the backup date;
   - set up folder sync again if you used it;
   - re-enter the AI capture API key if you used receipt capture.
6. Make a fresh backup from the new device.

Without the passphrase, the books cannot be recovered. Without any backup, the books on the lost device are gone. Keep a recent copy off the device.

## 6. Evidence

| Claim | Proof |
|---|---|
| Format, crypto, tamper and truncation detection, wrong passphrase, path safety, KDF bounds | core `test/backup_restore_test.dart` (24 tests) |
| Interrupted backup leaves no file | core `backup_restore_test.dart` (fault at each backup stage, and a SIGKILL child process); hub `solo_fault_test.dart` (disk full during backup) |
| Interrupted restore at every step rolls back or finishes, never a mix | core `backup_restore_test.dart` (SIGKILL child process at each `RestoreStep`); hub `solo_fault_test.dart` (each step, plus startup recovery, with BusinessSummary equality) |
| A backup whose books do not reproduce their recorded totals is refused | hub `solo_fault_test.dart` |
| **Clean-install restore reproduces the books exactly** | hub `test/solo_acceptance_test.dart`. A full business is restored into a **new, empty data folder** with a different device id. Every table except the app manifest is identical row for row. BusinessSummary, TB, P&L, BS, stock valuation, stock↔GL reconciliation and AR/AP ageing are identical. The attachment bytes are identical and checksum-verified. The opening reconciliation still agrees, and a new payment posts normally. |

**What is not yet proven:**

- The clean-install drill has run on Linux through `sqflite_common_ffi` in CI-style automated tests.
- It has **not** yet been run on a physical Android or iOS device: uninstall, reinstall, restore from a file in cloud storage.
- Until that drill is executed and recorded, disaster recovery on mobile is **not** claimed as proven. It is tracked as an RC blocker in [SOLO_ACCEPTANCE_MATRIX.md](SOLO_ACCEPTANCE_MATRIX.md).

## 7. Known limits

- **Speed:** pure-Dart AES-GCM runs at about 8 MB/s. A business with 500 MB of attachments takes about a minute. `cryptography_flutter` (platform AES) is a drop-in POST-GA speed-up.
- **Memory on mobile:** "Save a copy" reads the whole backup into memory for the system save sheet. Very large backups (hundreds of MB) should be copied over USB or desktop instead. Streaming the copy is PILOT.
- **Atlas Team:** Team books are restored on the server. Restoring a Solo backup onto a Team-connected device is blocked.
