# 6. Backup and recovery

**DRAFT. Read this before you enter real data.**

## Your responsibility

Atlas Solo keeps your books **only on this device**. Neuradix does not hold a copy. If the device is lost, broken, reset, or Atlas is uninstalled, the books on it are gone. **Only a backup you made, stored somewhere other than the device, can bring them back.**

- Turn on **Automatic backup** (below). Atlas then backs up every day **while it is open**: when it starts, when you return to it, and hourly. It cannot back up while it is closed. Atlas tells you when the last good backup was made and warns if backups are failing.
- On Android, Atlas switches off the phone's own Google backup for its data. That copy was unencrypted and could clone this device onto another. Use Atlas backups instead.
- On iPhone and iPad, an iCloud device backup includes Atlas. Restoring it onto a **replacement** device is fine. Do not restore it onto a second device you keep using alongside the first.

**Do it weekly, and always:** after month-end, before updating Atlas, and before changing device.

## Turn on automatic backup

1. Open **More › Setup › Preferences › Backup & restore**.
2. Under **Automatic backup**, choose **Turn on automatic backup…**.
3. Pick a folder **outside the phone's Atlas data**: a USB drive or cloud-synced folder on a computer, or `Documents` on an Android phone. Atlas checks it can write there.
4. Choose a **recovery passphrase** and type it again. Write it down and keep it away from the device. **With it, any device can open these backups. Without it, nobody can.**
5. Atlas makes the first backup at once. It keeps the newest 14 and removes older automatic ones. Files you put there yourself are never removed.

If the card says **Automatic backup is failing**, it says why (folder unplugged, no space, no permission). Fix that and choose **Back up now**.

Use **Export recovery copy…** to send the newest backup to Drive, iCloud, email or your accountant as well.

## Make a backup by hand

1. Open **More › Setup › Preferences › Backup & restore**.
2. Choose **Back up now**. Enter a **Passphrase**, then **Type it again**.
   - Use a long passphrase you will not forget. Write it down somewhere safe, away from the device.
   - **Without the passphrase, nobody, including Neuradix, can open the backup.**
3. Keep Atlas open until it says **Backup saved**. Atlas checks the whole file before calling it saved.
4. Choose **Save a copy to another place…** and put it on a cloud drive, USB stick or email it to yourself or your accountant. **Backups on this device** are lost with the device.

The backup is encrypted and contains your books, your attachments (receipt photos) and your settings. It does not contain your receipt-AI key or Team sign-in.

## Restore onto a new or reinstalled device

1. Install Atlas ([guide 1](01_INSTALL_AND_FIRST_RUN.md)). On the first screen choose **Restore from a backup instead**. Do not create a company first. If you already did, use **Backup & restore › Restore from a backup file…** instead.
2. Pick your most recent `.atlasbackup` file (copy it onto the device first if needed) and enter its passphrase. For an automatic backup, that is the recovery passphrase you chose when you turned automatic backup on.
3. Atlas checks the file, then shows **Replace the data on this device?** with the company, the backup date and key figures. Compare them with what you know (last invoice number, bank balance).
4. Type `REPLACE` and choose **Restore**.
5. When you see **Restore complete**:
   - check the bank balance and **Who owes you**;
   - re-enter anything you did after the backup date;
   - **numbers are never issued twice.** On the same device, Atlas continues every series after the last number it issued and lists the documents you entered after the backup, so you can re-enter them. On a **new** device, Atlas cannot know what you issued after the backup: new invoices, receipts and payments wait until you open **Settings › Numbering series** and either **confirm the last numbers issued** (check your sent invoices) or **start a recovery series** (only if your tax authority accepts a separate series);
   - re-enter the receipt-AI key if you used it;
   - turn **Automatic backup** on again on a new device;
   - make a fresh backup.

If the file is damaged, the passphrase is wrong, or the backup was made by a newer Atlas, the restore stops with **Restore stopped, nothing changed**, and your current books are untouched. If the device turns off during a restore, Atlas finishes or undoes it safely when it next starts. The books that were replaced are kept as a safety copy until the next restore. Support can help you recover them.

## Status: proven so far

Restore into an empty installation is tested automatically on every change. **It has not yet been carried out on a physical phone after uninstalling Atlas.** That drill is the first step of the pilot.
