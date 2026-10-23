# 7. Updating Atlas

**DRAFT.**

## Before every update

1. Finish any document you are editing.
2. **Back up** and save a copy off the device ([guide 6](06_BACKUP_AND_RECOVERY.md)). This is your way back if anything goes wrong.
3. Note your Atlas version: **Settings › About**.

## Update

- **Android (Google Play):** update Atlas from Google Play like any app. Never uninstall first: uninstalling deletes the books.
- **Other platforms:** not yet supported. Support will give instructions with each pilot build.

When Atlas next opens, it upgrades your books to the new version automatically. This can take a few seconds. Do not force-close it during that time. Each step is all-or-nothing, so an interruption leaves the books as they were and the upgrade runs again at the next start.

## After the update

- Check **Settings › About** shows the new version.
- Open **Help & diagnostics** if anything looks wrong. It shows the database version and any errors.

## If something goes wrong

| What you see | What it means | What to do |
|---|---|---|
| **Update Atlas to open your books** | The books were written by a **newer** Atlas than this one, for example after a restore from a newer device. Atlas will not open them, so they cannot be damaged. | Update Atlas to the latest version. **Do not uninstall.** |
| **Atlas could not start** | Something stopped Atlas from opening the books. | Do not uninstall. Choose **Save report** and send it to support ([guide 8](08_TROUBLESHOOTING_AND_SUPPORT.md)). |
| The update itself is broken | — | Updates cannot be undone in place. Support will either ship a fixed version, or help you restore the backup you made before updating into the previous version. |

## Several devices

If you share books between devices through a folder, every device must run the same Atlas version. Update them all on the same day.
