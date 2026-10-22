# Atlas Solo — first-customer pilot procedure

Status: 22 October 2026. **Procedure only. No pilot has taken place, and no customer has used Atlas.** This turns plan M2.1–M2.6 into steps with records. Every table below starts empty and is filled only from real events, with dates and names.

**Entry condition:** an accepted release candidate ([SOLO_RC_PACKAGE.md](SOLO_RC_PACKAGE.md) §4, "Distribute to pilot"). **Exit condition:** the M2 gate in [SOLO_RELEASE_READINESS.md](SOLO_RELEASE_READINESS.md) §3 is met, or the pilot is stopped (§10).

## 1. Choose the pilot customer (M2.1)

Choose a customer who meets these:

- an owner-operated services or simple-trade business, with one principal operator;
- a moderate volume (tens, not thousands, of invoices a month);
- no need for a Maltese fiscal cash register, Team multi-user, manufacturing or high-volume POS;
- an accountant willing to review the opening position and the first period;
- an Android phone on the supported list, with a screen lock;
- agrees in writing to the pilot terms, including backup responsibility.

Record the customer **by code (PILOT-01), not by name**, in this repository. The name and contact live in the product owner's customer records only.

| Field | Value |
|---|---|
| Pilot code | PILOT-01 |
| Business kind / profile | PENDING |
| Device / OS | PENDING |
| Accountant engaged | PENDING |
| Agreement signed (date) | PENDING |
| Opening date | PENDING |
| Parallel-run period | PENDING |

## 2. Signed install

1. Install the RC from Play internal testing, or supervised APK install, on the customer's phone. Check the version in **Settings › About** matches the release record.
2. Check that the phone has a screen lock (R5).
3. First run ([guide 1](../solo/01_INSTALL_AND_FIRST_RUN.md)), then business setup ([guide 2](../solo/02_BUSINESS_SETUP.md)) until the setup checklist says ready to invoice.
4. **Agree the backup routine:** weekly plus month-end, copy to the customer's cloud drive. Make the first backup together, and **do a test restore** onto a spare device or a second install profile.

## 3. Migration (M2.2)

1. Export from the old system as at the opening date: customers, suppliers, items, stock, open AR and AP, trial balance, bank.
2. **Setup › Move from another system:** Check. Fix rejected rows **in the files**, never in the database. Then Import.
3. Record every rejected row and its resolution in the exceptions log (§3.1).
4. **No manual database edits.** If something can only be fixed by editing the database, stop: it is a product defect (§7).

### 3.1 Migration exceptions log

| # | File / row | Problem | Resolution | Class (§7) |
|---|---|---|---|---|
| — | — | — | — | — |

## 4. Opening reconciliation pack (M2.2)

Produce the pack and have the customer's accountant sign it off:

| Figure at opening date | Old system | Atlas | Difference | Explained by |
|---|---|---|---|---|
| Trial balance (each account) | | | | |
| AR per customer and total | | | | |
| AP per supplier and total | | | | |
| Stock value per item / total (if stocked) | | | | |
| Bank / cash per account vs statement | | | | |
| Opening Balance Equity nets to zero | n.a. | | | |

Save the Atlas reconciliation (**Accountant export**) and the old system's reports with the pack. The pilot continues only with every difference explained. Signed off by (name, role, date): **PENDING**.

## 5. Daily workflows and parallel period (M2.3)

For one full accounting period (at least one month, including a month-end and, if due, a VAT period), the customer works in Atlas. Where feasible, they also keep the previous process or an independent control running.

- **Weekly check-in** (30 min): review the diagnostics report together. Look at errors, postings owed, the backup age, and the "stock positions sharing one balance record" line. Note any questions (§6).
- **Coverage:** confirm the period exercised quotes, invoices, part payments, credit notes, supplier bills, expenses with receipts, bank reconciliation and, if stocked, receipts, sales and a count.

## 6. Full period validation (M2.3)

At period end, after month-end ([guide 5](../solo/05_REPORTS_AND_MONTH_END.md)), compare:

| Area | Atlas | Control (old process / accountant) | Difference | Class (§7) |
|---|---|---|---|---|
| Sales | | | | |
| Purchases | | | | |
| VAT / tax | | | | |
| Receivables | | | | |
| Payables | | | | |
| Stock quantity / value | | | | |
| Gross margin | | | | |
| P&L | | | | |
| Balance sheet | | | | |
| Bank balance / reconciliation | | | | |

**The milestone cannot close with any unexplained difference.**

## 7. Support incidents

Every question, error or difference becomes a row. Classify each one as:

- **product defect**;
- **migration issue**;
- **setup/configuration issue**;
- **source-system issue**;
- **documentation/training issue**.

Product defects also get a release class (`BLOCKER-SOLO-GA` / `PILOT` / `POST-GA`) in the tracker §6. Severity follows the [support policy](policies/SUPPORT_AND_SEVERITY_POLICY.md).

| # | Date | Diagnostic id | Severity | Summary | Class | Resolution / issue | Closed |
|---|---|---|---|---|---|---|---|
| — | — | — | — | — | — | — | — |

## 8. Backup, restore and upgrade during the pilot

| Event | Date | Build | Result | By |
|---|---|---|---|---|
| Restore drill with the customer's **real** book, onto a spare device (M2-5) | | | PENDING | |
| Upgrade to the next RC on the customer device, after a backup ([guide 7](../solo/07_UPGRADE.md)): books open, trial balance unchanged, diagnostics clean | | | PENDING | |
| Month-end backup copied off the device | | | PENDING | |

## 9. Rollback

A pilot needs a way back at every step. **Before any change, there must be a backup copied off the device.**

| Situation | Rollback |
|---|---|
| Migration wrong | Restore the backup made after setup and before import (or reinstall and redo setup). Fix the files, and import again. The re-import is idempotent. |
| A new RC is broken on the customer's device | Android cannot downgrade in place. Either ship a fixed RC with a higher build number, or uninstall, install the previous RC, and restore the backup made **before** the upgrade. Re-enter anything since. A newer-schema book is refused by the older build, never damaged. |
| Atlas unsuitable for the business | Export with **Accountant export**, and return to the previous system with the period's documents re-keyed or imported there. Keep the final Atlas backup for the retention period. |
| Data loss or wrong postings found | Stop using Atlas for new work, log an S1, keep the device as it is, and send the diagnostics report. Recover from the last good backup only when support agrees. |

## 10. Exit

**Pilot passed:** every table in §2–§8 is filled. Every difference and incident is explained, and every product defect is classified. The customer and accountant have signed the reconciliation and the period comparison. The product owner then updates the M2 gate in the tracker and decides on Solo 1.0 (plan M2.6).

**Pilot stopped:** record the reason and what would need to change.
