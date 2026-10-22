# Atlas Solo — Data integrity, storage audit and threat model

Status: October 2026. Covers Atlas Solo, the single-device edition. It also covers Atlas Team devices while they are offline. Atlas Team's server-authoritative posting was out of scope and **was not changed**.

Related documents:

- [SOLO_BACKUP_AND_RECOVERY.md](SOLO_BACKUP_AND_RECOVERY.md): the backup format and the restore procedure.
- [SOLO_OPENING_DATA_MIGRATION_GUIDE.md](SOLO_OPENING_DATA_MIGRATION_GUIDE.md): the opening-data import.
- [SOLO_ACCEPTANCE_MATRIX.md](SOLO_ACCEPTANCE_MATRIX.md): the test evidence and the release-gate classification.

## 1. Where the books live

| Data | Location | Format | Protection at rest |
|---|---|---|---|
| All business records: documents, child rows, GL, stock ledger, audit log, sync queue, posting outbox, numbering | `<app support dir>/mercantis.db` (`atlasDatabaseFileName`, `mercantis_core_ui/.../core_providers.dart`) | SQLite through sqflite (mobile) or sqflite_common_ffi (desktop) | **Not encrypted by Atlas.** Relies on the OS (see §3). |
| Attachments (receipts, signed invoices, photos) | `<app support dir>/attachments/<doc>/<id>` | Plain files. The DB's `attachments` table holds metadata and a SHA-256. | Not encrypted by Atlas. Same reliance on the OS. |
| Device preferences (theme, saved queries, capture settings, folder-sync choice) | SharedPreferences | Plain key/value | Not encrypted. |
| AI capture API key | SharedPreferences (`capture.ai.settings`) | **Plaintext** | None beyond the OS sandbox. Classified BLOCKER-SOLO-GA (R4), see §5. |
| Atlas Team session token | flutter_secure_storage (Keychain / Android Keystore-backed) | OS secure storage | OS-encrypted. |
| Operator passcodes | In the DB: salted SHA-256, 100 000 rounds | Hash only | Included in backups as a hash, never in plaintext. |
| Backups | Wherever the user saves them (`.atlasbackup`) | AES-256-GCM, key from Argon2id of the user's passphrase | **Encrypted**, see the backup doc. |

Secure storage protects **only** the Team session credential. The database is not encrypted merely because secure storage exists. It is a plain SQLite file inside the app sandbox.

## 2. Audit findings (before this increment)

Each row was found by reading the code. Each fix has a test that fails without it.

| # | Defect | Consequence | Fix | Test |
|---|---|---|---|---|
| 1 | `DocumentEngine.save` wrote the header, then deleted and re-inserted child rows, with no transaction | A crash or error mid-save lost invoice lines | Each of save, delete, submit, cancel and applyOnSubmitUpdate is now one `_db.transaction`, including its audit row and sync mutation | core `crash_safety_test.dart` |
| 2 | Submit and cancel changed `docstatus`, then wrote audit and sync separately | A submitted document could have no audit row or sync mutation | Same transaction. Interceptors get `inLifecycleTransaction` to write inside it. | core `crash_safety_test.dart` |
| 3 | GL, stock and party ledgers were derived after submit, through separate saves, and errors were swallowed | A kill, a full disk or one failed write left a **submitted invoice with no or partial GL**, and nothing recorded it | **Posting outbox.** A `pending` posting batch is committed in the submit/cancel transaction. Derivation marks it `posted` or `failed`. Startup re-runs every batch that is not posted. Derived rows have deterministic ids, so a re-run overwrites and never duplicates. | hub `posting_outbox_test.dart` (6 tests) |
| 4 | Migrations ran step by step with no transaction | A crash mid-upgrade left a half-migrated schema | Each step runs in a transaction and records its version in that transaction. Steps are idempotent. | core `migration_safety_test.dart` |
| 5 | Opening a DB written by a **newer** Atlas silently ran against an unknown schema | Possible corruption after a downgrade | `UnsupportedSchemaVersionException`. The DB is closed untouched. | core `migration_safety_test.dart` |
| 6 | Attachments were written in place | A kill left a truncated file whose metadata row claimed it was complete | Write to `<id>.partial`, then an atomic rename. Partials are swept at start. | core `crash_safety_test.dart` |
| 7 | No backup or restore existed (BLOCKER-SOLO-RC from M1.2) | A lost or reset device lost the business | Encrypted backup and journalled restore | core `backup_restore_test.dart`, hub `solo_acceptance_test.dart`, `solo_fault_test.dart` |
| 8 | `outstanding_amount` was computed in binary floating point | 141.60 − 100 stored as 41.599999999999994. An invoice fully paid in parts could keep a sub-cent balance and never pass the "Mark as Paid" guard (`outstanding_amount <= 0`). | Rounded to the cent | hub `ledger_values_test.dart`, `solo_acceptance_test.dart` |

## 3. Threat model

| Threat | What protects the books today | Residual risk | Class |
|---|---|---|---|
| **Device lost or stolen** (unlocked or no device PIN) | OS sandbox. Android FBE / iOS Data Protection protect files **only while the device is locked** and only when a PIN is set. | A thief with an unlocked device, or a device with no PIN, can read the books. Atlas has no app-level DB encryption. Recovery comes from the encrypted backup (backup doc §5). | PILOT. Advise customers to set a device PIN. App-level DB encryption (SQLCipher) is POST-GA. Not introduced here, because it would need a re-keying migration and a tested key-custody story. |
| **Desktop laptop lost** | FileVault / BitLocker if the customer enabled it. Otherwise only the OS user account. | Without full-disk encryption the DB file is readable. | PILOT (installation guidance) |
| **Stolen backup file** | AES-256-GCM. Argon2id key derivation (64 MiB, 3 passes). The header holds only salt and KDF settings, with no business data. The passphrase is never stored (test asserts it is not in the file). | Weak passphrases. Atlas requires at least 12 characters. An offline guessing attack still pays about 64 MiB and 3 passes per guess. | Acceptable for RC |
| **Corrupt or tampered backup** | Every 1 MiB segment is authenticated (GCM tag, nonce bound to segment index and final flag, AAD = header). Truncation, reordering and appending are detected. Each file's SHA-256 is in the manifest. The staged DB gets `integrity_check`, table counts, and a business-summary recompute that must match to the cent. | None known | — |
| **Corrupt live file** | `quickCheck()`. Every write is transactional. | A hardware fault can still corrupt SQLite. Recovery is from backup. | — |
| **Failed write** (I/O error, constraint, trigger) | Transactions: nothing partial is committed. Posting failures are recorded and retried. | — | — |
| **Low storage** (SQLITE_FULL) | Same as a failed write. Backup writes `.partial` and renames only after verifying. | The app shows the SQLite error text. Friendlier copy is PILOT. | PILOT (copy) |
| **Process killed** (save, submit, posting, attachment write, backup, restore) | Transactions, posting outbox, `.partial` attachments, restore journal with state-aware rollback. Proved with SIGKILL of child processes in core. | — | — |
| **Unsupported upgrade or downgrade** | Newer-schema guard on open. Restore refuses a backup from a newer schema or format with a clear message. | — | — |
| **Restore over the wrong books** | Typed confirmation (`REPLACE`). Restore is blocked while connected to Atlas Team. The previous books are kept in `pre-restore-copy/`. Folder sync settings are cleared. | Restoring an old backup resets document-number counters to the backup point. Numbers issued after the backup **can be issued again**. The confirm dialog says so. | GA. Store last-issued numbers outside the DB, or bump series on restore. |
| **Two devices share one identity after restore** | The device id is **not** in the backup, so the restored device draws its own number blocks. | — | — |

## 4. Startup and shutdown

1. **Before the DB opens:** `AtlasBackupService.recoverInterruptedRestore` (core_providers DB provider). It rolls back an interrupted restore or finishes a committed one.
2. **Open:** `MercantisDatabase.open` refuses a newer schema, then migrates in transactions.
3. **Attachment store:** sweeps `*.partial` files.
4. **Ledger:** `LedgerDerivationService.recoverPendingPostings()` re-derives every outbox batch that is not `posted`. The screen shows "owed postings" if any remain.
5. **Shutdown:** no special step is needed. Every committed transaction is durable, and nothing relies on a clean exit.

## 5. Residual issues (classified)

The same list is in [SOLO_ACCEPTANCE_MATRIX.md](SOLO_ACCEPTANCE_MATRIX.md#residual-issues), which is the gate tracker.
