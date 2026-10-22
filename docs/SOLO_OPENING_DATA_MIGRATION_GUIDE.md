# Atlas Solo — Opening-data migration guide

Status: October 2026 (M1.3).

- Screen: Setup › Your business › **Move from another system** (`opening-data`).
- Engine: `lib/migration/opening_take_on.dart`, `opening_reconciliation.dart` and `take_on_templates.dart`.
- Tests: `test/opening_take_on_test.dart` (17), `test/solo_acceptance_test.dart`.

The take-on reuses the normal accounting path. It adds no new one.

- Masters are ordinary documents.
- Opening stock is a Material Receipt Stock Entry flagged `is_opening`.
- Open receivables and payables are opening Sales and Purchase Invoices against **Opening Balance Equity**, so later payments settle them like any invoice.
- The trial balance becomes one Opening Entry journal built by the existing `OpeningBalanceBuilder`.

Every validation, posting rule, audit row and the posting outbox apply exactly as for documents typed in by hand.

## 1. Before you start

1. Finish first-run setup and create the financial year that contains the opening date.
2. Pick the **opening date**, normally the last day of a month the old system has closed. Balances are as at the **end** of that day. Enter everything after it in Atlas normally.
3. Make sure every account in the old trial balance exists in Atlas, by its exact name or id. Create the missing ones first.
4. If the book already holds data you need, make a backup.

## 2. The files

Download each template from the screen. Each has a header row and example rows to overwrite. Only the parts you need are required. Atlas maps columns by name and common aliases. **Columns** lets you map an export from the old system directly.

| # | File | Key (how re-imports recognise a row) | Atlas creates | Posts to ledger |
|---|---|---|---|---|
| 1 | Customers | `customer_code` → Customer id | Customer | no |
| 2 | Suppliers | `supplier_code` → Supplier id | Supplier | no |
| 3 | Warehouses | `warehouse_code` → Warehouse id | Warehouse | no |
| 4 | Items and services | `item_code` → Item id (UOMs created as needed) | Item, UOM | no |
| 5 | Opening stock | `OPEN-STK:<item>@<warehouse>` | Stock Entry (Material Receipt, opening): Dr Stock / Cr Opening Balance Equity | **yes** |
| 6 | Open customer invoices | `OPEN-AR:<invoice_no>` | Sales Invoice (opening, no VAT): Dr Debtors / Cr Opening Balance Equity | **yes** |
| 7 | Open supplier bills | `OPEN-AP:<supplier>:<bill_no>` | Purchase Invoice (opening, no VAT): Dr Opening Balance Equity / Cr Creditors | **yes** |
| 8 | Trial balance | `OPEN-GL:<opening date>` | One Opening Entry journal for every account **except** receivable, payable and stock control accounts, balanced against Opening Balance Equity | **yes** |
| 9 | Bank and cash balances | — | nothing: the independent figure the reconciliation checks against | no |

Why the control accounts are not posted from the TB: Debtors, Creditors and Stock are built from the detail in files 5–7. The TB lines for those accounts are **checked** against the detail instead. They must agree to the cent, or the TB is blocked. Posting both would count them twice.

Why opening invoices carry no VAT: the amount brought over is what is still owed, VAT included. That VAT was declared in the old system and must not be reported again.

## 3. Check (dry run)

**Check** validates every file against the books as they are now and **writes nothing**. Each row gets a verdict:

| Verdict | Meaning |
|---|---|
| new | Will be created |
| already imported | The same record is already in Atlas with the same values (a re-import). Nothing to do. |
| to finish posting | An earlier import was interrupted after saving this opening document but before posting it. It will be posted now. |
| checked against detail | A TB control line, or a bank statement balance. Compared, not posted. |
| zero | A zero TB line. Skipped. |
| conflict | In Atlas already with **different** values. Never overwritten. Fix Atlas or the file. |
| rejected | Invalid. The message names the line and what to fix. |

Rows are rejected for, among other things:

- a missing required value;
- a duplicate key (the message points at the first line);
- `/ ? # \` in a code;
- an unknown customer, supplier, item, warehouse or account;
- a group account;
- a service item with stock;
- a date that is not `YYYY-MM-DD`;
- an invoice dated after the opening date;
- a due date before the invoice date;
- a zero or negative outstanding amount (bring credits over as credit notes after opening, so they are not netted silently);
- debit and credit both filled;
- a number that is not plain (see §5);
- opening stock into a position that already holds stock.

The whole migration is refused if no financial year covers the opening date, or if the books are locked through it.

**Rejected rows** downloads the rejected and conflicting rows with a `line` and a `problem` column. Fix them and load the file again.

## 4. Import

- **Masters** (files 1–4) import their valid rows. A rejected customer does not stop the others.
- **Posting sections** (files 5–8) are **all-or-nothing**. One rejected or conflicting row blocks the whole section, because a partial opening position cannot reconcile.
  - The TB is blocked too while a detail file it depends on is blocked: posting it would leave Debtors, Creditors or Stock short.
- Import runs in dependency order. Each document is saved and then submitted through the normal engine.

**Re-running is safe.** Every created document has an id derived from the source key. A second import of the same files creates nothing and posts nothing ("already imported"). After an interruption (app killed, disk full), the next run posts the drafts left behind ("to finish posting") and creates the rest. A file that now says something different is a conflict, never a second posting.

## 5. Precision and rounding rules

- **Money:** plain decimals with **at most 2 decimals**, an optional leading `-`, and no thousands separators or currency symbols (`1234.50`, not `1,234.50` or `€1234.5`). Values are parsed into **integer cents**, totalled in integers, and compared exactly. Anything ambiguous is **rejected, never rounded**.
- **Quantities:** at most 6 decimals, greater than zero.
- **Opening stock value:** the supplied total is authoritative. The unit cost is derived as value ÷ quantity, so qty × rate gives the value back. Atlas never guesses a cost.
- **The trial balance must balance exactly.** A difference, even 0.01, blocks the import with the amount stated. Atlas does not post the difference to suspense or equity.
- **Reconciliation tolerance is zero.** Every comparison is to the cent, and stock quantities to 6 decimals. There is no rounding tolerance because the source data is required to be in cents.
- **Missing data is never invented.** A blank cell stays blank. A blank never overwrites an existing value. A missing TB, AR, AP or stock file whose control balance is non-zero is reported, and not filled in.

## 6. Reconciliation

After import, and any time from **Reconcile**, Atlas compares the files with the ledger **as at the opening date**, so trading after it does not disturb the result:

| Area | Previous system (files) | Atlas |
|---|---|---|
| Trial balance | each account's net debit in file 8 | GL balance per account. Any account Atlas holds a balance on that the file omits is listed too. **Opening Balance Equity must net to zero.** |
| Receivables | file 6 per customer | Receivable-account GL per customer |
| Payables | file 7 per supplier | Payable-account GL per supplier |
| Stock | file 5 per item and warehouse, qty and value | stock ledger qty and value. Also: stock ledger value against the stock control accounts. |
| Bank and cash | file 9 statement balances | GL balance of each bank or cash account |

Every line shows the previous figure, Atlas's figure and the difference, and drills down to the Atlas vouchers behind it. **Differences are reported, never absorbed.** Atlas adjusts nothing. Rows that were rejected still count as the previous system's figures, so anything that did not make it into Atlas appears as a difference.

Exit criterion (M1.3): every area agrees. The automated proof is in `opening_take_on_test.dart › reconciliation` and in the acceptance fixture.
