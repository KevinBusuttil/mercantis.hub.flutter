# 8. Troubleshooting and getting support

**DRAFT.** The support channel, hours and response times are set in the support policy ([SUPPORT_AND_SEVERITY_POLICY.md](../release/policies/SUPPORT_AND_SEVERITY_POLICY.md)), which is a draft until the product owner approves it.

## The diagnostics report

**Settings › Help & diagnostics** (also on the start-up error screen) builds a report support can read without asking you to install anything or open a database.

**It includes:**

- Atlas version, build and source revision;
- device platform and OS version;
- database version, size and an integrity check;
- postings still being completed, and why;
- record counts by type;
- business type and enabled areas;
- backup status;
- sync status;
- the last 20 errors.

**It leaves out:**

- your company name;
- customer, supplier and item names;
- amounts;
- email addresses;
- account numbers;
- file paths;
- passwords and keys.

Error messages are filtered before they are stored, and again before the report is built. Read the report before you send it. Every line is plain text.

To send it:

1. Choose **Save report** (or **Copy report**).
2. Send the file to support, quoting the **Diagnostic id** at the top.

**Clear error history** empties the list of recent errors, after support has seen them.

## Common problems

| Problem | Try |
|---|---|
| Atlas shows **Atlas could not start** | Do not uninstall. **Save report** and contact support. |
| **Update Atlas to open your books** | Update Atlas. See [guide 7](07_UPGRADE.md). |
| "document(s) still…" on **Backup & restore**, or stock movements refused | Free some storage, then restart Atlas, which retries. If it stays, send the report. |
| Device storage full, saving fails | Free space (old photos, other apps). Then restart Atlas. Nothing already saved is lost. |
| A wrong invoice was posted | Cancel or reverse it, or issue a credit note ([guide 4](04_DAILY_OPERATIONS.md)). Posted documents are never edited. |
| Reports disagree with the bank | Reconcile the bank ([guide 5](05_REPORTS_AND_MONTH_END.md)). A missing or duplicated payment is the usual cause. |
| Forgot the backup passphrase | It cannot be recovered. Make a new backup with a new passphrase now. Older backups stay unreadable. |
| Lost or broken device | Restore your most recent backup on a new device ([guide 6](06_BACKUP_AND_RECOVERY.md)). |
| Item or warehouse code refused as "sharing one stock record" | Choose a different code ([guide 2](02_BUSINESS_SETUP.md)). |

## What support will never ask for

- Your backup passphrase.
- Your device PIN.
- Your API keys or passwords.
- A copy of your database or backup file, unless you agree for a specific problem, under the privacy notice.
