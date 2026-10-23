# 4. Day to day: invoicing, buying, stock and payments

**DRAFT.** Screens below are named as they appear in the **Owner** view. The **Accountant** view uses engine terms (for example "Submit" and "Sales Invoice").

## How documents work

Every sales or purchase document starts as a **draft**, which you can change freely. When you post it (**Post invoice**, **Post bill**, **Record payment** and so on), Atlas asks you to confirm, then records it in the accounts, stock and customer balances. A posted document cannot be edited. To correct one, cancel or reverse it and create a new one, or issue a credit note. Atlas keeps the full history.

## Selling

| Task | Where |
|---|---|
| Add a customer | **Customers** › **New customer** |
| Quote | **New quote**, add lines, then **Finalise quote**. The quote is then ready to send. |
| Invoice | **Invoices** › **New invoice**, or turn a finalised quote into an invoice. Check the totals, then **Post invoice**. |
| Send or print | Open the posted invoice and choose **Print preview**, then print or share from there. |
| Credit or return | **New invoice**, tick **Is Return (Credit Note)**, choose the original in **Return Against**, enter the returned lines, then post. Returned stock goes back at its cost. |
| Customer statement | **Customers** › the customer › statement |

## Getting paid

**Money › Receive payment.** Pick the customer, the amount, the date and the bank or cash account, and allocate it to the invoices it pays. Part payments are fine: the invoice stays open for the rest. **Money › Who owes you** lists what is outstanding by how late it is.

## Buying and expenses

| Task | Where |
|---|---|
| A supplier bill | Enter the bill, then **Post bill** |
| A small expense (fuel, ink, parking) | **Record expense**. Attach the receipt photo. |
| A paper receipt | **Scan receipt** photographs it. Optional AI reading needs your own API key and the internet. Check every field before you record the expense. |
| Pay a supplier | **Money › Pay supplier** |

## Stock (trade and retail)

- **Receive goods** increases stock at the bill's cost. Sales take stock out at the average cost (the cost of goods sold is recorded for you).
- **Count stock** records a physical count and posts the difference.
- **Low stock** lists items below their reorder level.
- Atlas refuses a sale that would take stock below zero.

## Bank

**Money › Reconcile bank** matches statement lines with payments in Atlas. Do it at least monthly. On a phone this screen is cramped. A tablet or computer is easier for now.

## If Atlas says a posting is still being completed

Occasionally (for example, after the device ran out of storage) a document is saved but its accounting entries could not be completed. The **Backup & restore** screen shows "document(s) still…" and Atlas retries every time it starts. While a stock posting is outstanding, Atlas refuses new stock movements so costs stay right. Restart Atlas, and if the message stays, contact support ([guide 8](08_TROUBLESHOOTING_AND_SUPPORT.md)).
