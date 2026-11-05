# Atlas Solo — Backup, restore and disaster recovery

Status: October 2026 (M1.4). Updated 5 November 2026 (C1): automatic Backup Protection (R2, §8) and recovery-safe numbering (R3, §9).

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
- the automatic-backup **device key** (it lives only in this device's secure storage; §8)
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
   - numbers already issued are never issued again (§9);
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
   - re-enter the AI capture API key if you used receipt capture;
   - **numbering:** a new device cannot know what was issued after the backup, so new invoices, receipts and payments are on hold until you confirm the last numbers you issued or start a recovery series (§9);
   - turn **Automatic backup** on again (§8): the folder and the device key belong to the old device.
6. Make a fresh backup from the new device.

Without the passphrase, the books cannot be recovered. Without any backup, the books on the lost device are gone. Keep a recent copy off the device.

## 6. Evidence

| Claim | Proof |
|---|---|
| Format, crypto, tamper and truncation detection, wrong passphrase, path safety, KDF bounds | core `test/backup_restore_test.dart` (24 tests) |
| Interrupted backup leaves no file | core `backup_restore_test.dart` (fault at each backup stage, and a SIGKILL child process); hub `solo_fault_test.dart` (disk full during backup) |
| Interrupted restore at every step rolls back or finishes, never a mix | core `backup_restore_test.dart` (SIGKILL child process at each `RestoreStep`); hub `solo_fault_test.dart` (each step, plus startup recovery, with BusinessSummary equality) |
| A backup whose books do not reproduce their recorded totals is refused | hub `solo_fault_test.dart` |
| Automatic backups: first run, after new transactions, restart, interrupted, unavailable folder, no space, permissions, rotation, integrity, fresh-install recovery with the passphrase only, no plaintext, a sale during the backup, overlap, lost and unavailable secure storage | hub `test/backup_protection_test.dart` (15), core `backup_restore_test.dart › automatic-backup keyring` (7) |
| **Clean-install restore reproduces the books exactly** | hub `test/solo_acceptance_test.dart`. A full business is restored into a **new, empty data folder** with a different device id. Every table except the app manifest is identical row for row. BusinessSummary, TB, P&L, BS, stock valuation, stock↔GL reconciliation and AR/AP ageing are identical. The attachment bytes are identical and checksum-verified. The opening reconciliation still agrees, and a new payment posts normally. |

**What is not yet proven:**

- The clean-install drill has run on Linux through `sqflite_common_ffi` in CI-style automated tests.
- It has **not** yet been run on a physical Android or iOS device: uninstall, reinstall, restore from a file in cloud storage.
- Until that drill is executed and recorded, disaster recovery on mobile is **not** claimed as proven. It is tracked as an RC blocker in [SOLO_ACCEPTANCE_MATRIX.md](SOLO_ACCEPTANCE_MATRIX.md).

## 7. Known limits

- **Speed:** pure-Dart AES-GCM runs at about 8 MB/s. A business with 500 MB of attachments takes about a minute. `cryptography_flutter` (platform AES) is a drop-in POST-GA speed-up.
- **Memory on mobile:** fixed (R8, 5 November 2026). "Save a copy" and "Export recovery copy" hand the file to the system share sheet by path, so the receiving app streams it. Nothing reads the whole backup into memory.
- **Atlas Team:** Team books are restored on the server. Restoring a Solo backup onto a Team-connected device is blocked.

## 8. Backup Protection: automatic backups (R2, 5 November 2026)

Code: Hub `lib/backup/backup_protection.dart` (service), `lib/backup/backup_scheduler.dart` (when it runs), the **Automatic backup** card on the Backup & restore screen. Core `BackupKeyring` / format 2 (`backup_crypto.dart`, `backup_archive.dart`).

### What the operator sets up

1. **Turn on automatic backup…**: choose a folder outside Atlas, then choose a recovery passphrase (entered twice, at least 12 characters).
   - Good folders: a USB drive, a cloud-synced folder (OneDrive, Dropbox, Google Drive for desktop, iCloud Drive on a Mac), or `Documents` / `Download` on an Android phone.
   - A folder inside Atlas's own data folder is refused: it is lost with the device.
   - Atlas writes, reads back and deletes a probe file before accepting the folder.
2. Atlas makes the first backup straight away.

Defaults: every **24 hours**, keeping the newest **14** automatic backups. Backups made by hand and any other file in the folder are never removed.

### When it runs, honestly

| Situation | Backup made? |
|---|---|
| Atlas starts (20 s after the shell opens) and the interval has passed | Yes |
| Atlas comes back to the foreground and the interval has passed | Yes |
| Atlas is open: hourly check | Yes, when the interval has passed |
| **Back up now** | Yes, always |
| **Atlas is closed, or in the background on a phone** | **No.** Android and iOS do not reliably run an app's code in the background, and a second process must not read the books while Atlas writes them. |
| Device connected to Atlas Team | No. Team books are protected on the server; a device backup of them cannot be restored (R11). |

So a business that opens Atlas every working day gets a backup every working day. The freshness status says exactly when the last good one was made.

### Freshness and failures

The card, and **Settings › Help & diagnostics › Backup & recovery**, show:

- **Protected**: the last good automatic backup is within the interval.
- **Backup due**: the interval has passed; the next start, resume or hourly check makes one.
- **No recent backup**: none for more than twice the interval (at most 7 days).
- **Automatic backup is failing**: the last attempt failed, with the reason in plain words.

| Failure | Detected how | What the operator sees |
|---|---|---|
| Folder unplugged, deleted or unreachable | probe before each run; `ENOENT`/`ENOTDIR` | "The backup folder cannot be reached. Reconnect the drive or choose the folder again." |
| No permission | probe; `EACCES`/`EPERM`/`EROFS`, Windows 5 | "Atlas is not allowed to write to the backup folder…" |
| Disk full | `ENOSPC`/`EDQUOT`, Windows 112/39 | "There is not enough free space…" |
| Device key missing from secure storage | key read fails or does not match the slot | "Enter the recovery passphrase to resume automatic backups." Backups stop; Atlas never writes an unencrypted one. |
| Crash, power loss, app killed mid-backup | Core writes `*.partial`, verifies, then renames; leftover partials are removed next run | Nothing that looks like a backup appears; the previous backups stay. |
| Two backups at once | in-process guard plus a lock file in the data folder (stale after 2 h) | The second is skipped. |

Diagnostics also check that the last recorded backup file is still there and reads as an Atlas backup ("last automatic backup file present"). The folder path is not in the report (it can contain a person's name).

### Integrity

Each automatic backup is the same consistent snapshot as a manual one (§1). Before it gets its real name, Core decrypts the whole file and checks every segment's tag and every file's SHA-256. Atlas then re-reads the header from its final place, in case a folder silently dropped the rename. A sale posted while a backup runs is either wholly in the snapshot or wholly not.

### Keys: how a replacement device opens an automatic backup

Automatic backups cannot ask for the passphrase each time. So:

1. When automatic backup is turned on, Atlas makes a random 256-bit **device key** and stores it in the platform's secure storage (`flutter_secure_storage`: Android Keystore-backed encrypted preferences, iOS/macOS Keychain, Windows Credential Manager, libsecret on Linux). Atlas reads it back to prove it was stored; if secure storage is unavailable, automatic backup stays off.
2. Atlas wraps the device key under a key derived from the recovery passphrase (Argon2id, 64 MiB, 3 passes, random salt; AES-256-GCM). This **recovery slot** is not secret: it is useless without the passphrase. It is kept in preferences and copied into the public header of every automatic backup.
3. Each automatic backup gets a fresh random **content key**, wrapped under the device key and stored in the header. The archive is encrypted with the content key exactly as in §2.
4. **Same device:** Atlas opens its own automatic backups with the device key, without asking.
5. **Replacement device:** the passphrase unwraps the device key from the slot in the file, which unwraps the content key. Nothing from the old device is needed.

The header is the associated data of every segment, so editing a slot, the key id or the content key makes the file fail to open. The passphrase is never stored. If secure storage loses the key (OS reset), the operator enters the passphrase once to recover it from the slot. Changing the passphrase makes a new slot; older backups still open with the old passphrase.

### Platform notes and residual risk

- **Desktop (Windows, macOS, Linux):** any folder the user can write to. Cloud-sync folders work because the file is complete before it gets its final name.
- **Android:** the chosen folder is stored as a path. Writing to `Documents/` or `Download/` by path is expected to work on Android 11 and later without a storage permission. Android 7–10 need a storage permission that Atlas does not request (Atlas declares no storage permission), so the probe fails there with a clear message; use **Export recovery copy** instead. After uninstalling Atlas, files it wrote stay in `Documents`, and a new install restores them through the file picker. A new install cannot delete the old install's files, so rotation only removes its own. **None of this has been run on a phone yet: it is part of the R1 device drill.**
- **iOS:** a folder chosen in Files is only reachable while the picker's permission lasts, so after a restart the probe reports the folder as unreachable. On iPhone, rely on **Export recovery copy** to iCloud Drive or Files, and on iCloud device backup (R-iOS-BACKUP). iOS is not in the recommended pilot platform set.

## 9. Document numbering after a restore (R3, 5 November 2026)

Code: Hub `lib/numbering/numbering_recovery.dart`, `lib/screens/numbering_series_screen.dart`. Core `NamingSeriesPolicy` (schema v9) and `CounterBlockAllocator.issuedThrough`.

### The problem

Document numbers are business-facing identifiers (`SINV-2026-0101`). Their counters live in the database, so restoring an older backup used to bring back older counters. On the same device (same device id) Atlas resumed exactly where the backup was and issued numbers again that customers already held. This was reproduced on `main` (`b596937`) before the fix.

Business-facing ("official") series: Sales Invoice (including credit notes), POS Invoice, Payment Entry, Customer Deposit, Delivery Note, Quotation, Sales Order, Purchase Order, Purchase Invoice, Purchase Receipt, Expense, Journal Entry. Internal ids (GL and stock ledger rows, bins, child rows) are not numbering series and are never reused anyway.

### What a restore does now

Inside the restore journal, after the restored books verify and before the restore commits (Core `prepareInstalled`; a failure or crash here rolls the whole restore back):

| Situation | Evidence | Result |
|---|---|---|
| **A. The original device:** the books being replaced are the same business | The replaced books record every number this device issued, including after the backup | Every series moves past the highest number issued. Documents that exist only in the replaced books are listed for re-entry ("Re-enter them with their original details"). No hold. |
| The backup is the newest | Same | Nothing changes. |
| **B. A new or replacement device**, or a different business was on this device | None: Atlas cannot know what was issued after the backup | Every official series is **on hold**. A new invoice, credit note, receipt or payment is refused before any number is drawn (`NamingHoldException`). Master data (customers, items) still saves. |

Atlas never claims continuity it cannot prove. In situation B the operator chooses, in **Settings › Numbering series**:

1. **Confirm the last numbers issued**: from their own records (sent-invoice folder, last printed receipt, accountant), the last number in each series. Each box starts at the restored value. A number lower than what the books hold is refused. The series continue from there.
2. **Start a recovery series**: official documents continue as `SINV-2026-R1-0001`, a distinct series that cannot clash with numbers issued after the backup. Atlas warns that some tax authorities require one unbroken sequence; there, use option 1. A later recovery uses `R2`.

Every step is in the audit log (`doctype = Numbering`): the restore's mode, evidence, series moved and documents missing; the confirmation or recovery series, with the operator and device. **Settings › Numbering series** always states the policy in force: normal, on hold, or recovery series `Rn`. Setting a series' next number by hand can now only move it forward, and is audited.

### Evidence

| Claim | Proof |
|---|---|
| Invoices 1–100, backup, 101–105, restore on the same device: the next invoice is 106; 101–105 and a post-backup payment are listed as missing; the payment series moves too; a cancelled post-backup invoice's number is not reused | hub `test/numbering_recovery_test.dart` |
| Total device loss: invoices, credit notes and payments are refused, nothing is saved, no number consumed; customers still save | same |
| Decision 1 refuses a lower number, then continues at 106 and is audited; decision 2 issues `…-R1-0001`, leaves existing ids untouched | same |
| Restore interrupted at every step leaves the live counters untouched | same, and `solo_fault_test` (every `RestoreStep`, now including `hostPrepared`) |
| A different business on the device is not used as evidence | same |
| Hold and recovery series enforced in Core, a held attempt consumes no number | core `test/naming_series_policy_test.dart` |
