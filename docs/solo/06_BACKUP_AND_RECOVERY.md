# 6. Backup and recovery

**DRAFT. Read this before you enter real data.**

## Your responsibility

Atlas Solo keeps your books **only on this device**. Neuradix does not hold a copy. If the device is lost, broken, reset, or Atlas is uninstalled, the books on it are gone. **Only a backup you made, stored somewhere other than the device, can bring them back.**

- Atlas does **not** back up automatically in this version. You must press **Back up now**. Atlas warns when the last backup is more than 7 days old.
- On Android, Atlas switches off the phone's own Google backup for its data. That copy was unencrypted and could clone this device onto another. Use Atlas backups instead.
- On iPhone and iPad, an iCloud device backup includes Atlas. Restoring it onto a **replacement** device is fine. Do not restore it onto a second device you keep using alongside the first.

**Do it weekly, and always:** after month-end, before updating Atlas, and before changing device.

## Make a backup

1. Open **More › Setup › Preferences › Backup & restore**.
2. Choose **Back up now**. Enter a **Passphrase**, then **Type it again**.
   - Use a long passphrase you will not forget. Write it down somewhere safe, away from the device.
   - **Without the passphrase, nobody, including Neuradix, can open the backup.**
3. Keep Atlas open until it says **Backup saved**. Atlas checks the whole file before calling it saved.
4. Choose **Save a copy to another place…** and put it on a cloud drive, USB stick or email it to yourself or your accountant. **Backups on this device** are lost with the device.

The backup is encrypted and contains your books, your attachments (receipt photos) and your settings. It does not contain your receipt-AI key or Team sign-in.

## Restore onto a new or reinstalled device

1. Install Atlas ([guide 1](01_INSTALL_AND_FIRST_RUN.md)). On the first screen choose **Restore from a backup instead**. Do not create a company first. If you already did, use **Backup & restore › Restore from a backup file…** instead.
2. Pick your most recent `.atlasbackup` file (copy it onto the device first if needed) and enter its passphrase.
3. Atlas checks the file, then shows **Replace the data on this device?** with the company, the backup date and key figures. Compare them with what you know (last invoice number, bank balance).
4. Type `REPLACE` and choose **Restore**.
5. When you see **Restore complete**:
   - check the bank balance and **Who owes you**;
   - re-enter anything you did after the backup date;
   - **set Document numbering** to continue after the last invoice you actually issued. A restore brings numbering back to where it was at backup time, so invoices issued after the backup could get their numbers again;
   - re-enter the receipt-AI key if you used it;
   - make a fresh backup.

If the file is damaged, the passphrase is wrong, or the backup was made by a newer Atlas, the restore stops with **Restore stopped, nothing changed**, and your current books are untouched. If the device turns off during a restore, Atlas finishes or undoes it safely when it next starts. The books that were replaced are kept as a safety copy until the next restore. Support can help you recover them.

## Status: proven so far

Restore into an empty installation is tested automatically on every change. **It has not yet been carried out on a physical phone after uninstalling Atlas.** That drill is the first step of the pilot.
