# 3. Moving from another system: opening balances

**DRAFT.** The full reference, including every column and rule, is [SOLO_OPENING_DATA_MIGRATION_GUIDE.md](../SOLO_OPENING_DATA_MIGRATION_GUIDE.md). This page is the short version for owners and their accountants.

## Decide the opening date

Pick the last day of a month that your old system (or your accountant) has closed, for example 30 September. Atlas will hold balances **as at the end of that day**. Everything after it is entered in Atlas.

Before you start:

1. Finish [business setup](02_BUSINESS_SETUP.md), including the financial year that contains the opening date.
2. Make sure every account in the old trial balance exists in Atlas.
3. Make a backup if the book already holds anything.

## Prepare the files

Open **More › Setup › Move from another system** and enter the **Opening date**. For each part you need, choose **Template**, fill it in (or export from the old system), and attach it.

| File | Contains |
|---|---|
| Customers / Suppliers | Names and contact details |
| Warehouses | Stock locations (stock businesses only) |
| Items | Codes, units and prices |
| Opening stock | Quantity and value per item and warehouse |
| Open customer invoices | What each customer owed at the opening date |
| Open supplier bills | What you owed each supplier |
| Trial balance | Every account's balance |
| Bank and cash | Balance per account, as on the statement |

If the old system's column names differ, choose **Columns** and match them up. Save the files as CSV in UTF-8.

## Check, import, reconcile

1. **Check.** Atlas reads every row and writes nothing. Each row gets a verdict. Download **Rejected rows** to see why, fix them in the file, and check again.
2. **Import.** Atlas asks **Import opening data?** and posts each section all or nothing. If it is interrupted, run it again: rows already imported are recognised and never posted twice.
3. **Reconcile.** Atlas shows the **Opening position** at the opening date: trial balance per account, what each customer and supplier owes, stock per item, and bank against your statement. Tap a figure to see the Atlas entries behind it.

**The opening is right only when every line agrees and Opening Balance Equity nets to zero.** Atlas reports differences. It never hides them by posting an adjustment. Ask your accountant to review the reconciliation and keep a copy (**Accountant export**).

## Limits in this version

- Open invoices come across as balances per customer or supplier, not as the original invoices. You can still receive and make payments against them.
- Numbering: set **Document numbering** to continue from your old system before posting new invoices.
