# 2. Setting up your business

**DRAFT.**

Open **More › Setup › Setup checklist**. It shows how many steps are done, and which are still needed before you can send an invoice. Steps that do not apply to your business type are hidden.

| Step | What to do | Needed to invoice? |
|---|---|---|
| **Company profile** | Legal name, address, VAT number, contact details. They print on your invoices. | Yes |
| **Logo & branding** | Add a logo for your documents. | No |
| **VAT / tax codes** | Check the rates created for your country. Add any special rates you use. | Yes |
| **Fiscal year** | Atlas creates the current year. Add the next one before the year ends. | Yes |
| **Document numbering** | Choose the prefix and next number for invoices, quotes and so on. If you are moving from another system, continue its numbering here. | No, but set it before your first invoice |
| **Add customers** | At least one. Many at once: see [guide 3](03_MIGRATION_AND_OPENING_BALANCES.md). | Yes |
| **Add items or services** | What you sell, with a price and VAT code. | Yes |
| **Add suppliers** | Who you buy from. | No |
| **Opening balances** | What the business owned and owed on the day you start using Atlas. See [guide 3](03_MIGRATION_AND_OPENING_BALANCES.md). | No, but needed for correct reports |
| **Bank account** | The account payments go in and out of. | No |
| **Stock items** | Only for businesses that keep stock. | No |
| **Send your first quote or invoice** | Done automatically when you post one. | — |

**Setup packs** (Setup › Getting started › Setup packs) add ready-made items, accounts and settings for common business kinds. **Re-run starter setup** on the checklist repairs a missing chart, VAT codes or fiscal year without touching your documents.

## Choosing what you see

**Settings › Business type & features** controls which areas appear (for example stock, projects or the till) and whether you see the **Owner** view (plain business words) or the **Accountant** view (ledger, trial balance, registers and report builder). Turning an area off hides it. It never deletes data.

## Codes for items and warehouses

Atlas refuses an item or warehouse code that would make two stock positions share one record. That can happen when codes contain a hyphen, for example item `A-B` in warehouse `C` and item `A` in warehouse `B-C`. If Atlas refuses a code for this reason, pick a code without the clash, for example without the hyphen. The message names both positions.

## When you are done

- Make your first backup ([guide 6](06_BACKUP_AND_RECOVERY.md)).
- If you are moving from another system, import opening data **before** entering new invoices ([guide 3](03_MIGRATION_AND_OPENING_BALANCES.md)).
