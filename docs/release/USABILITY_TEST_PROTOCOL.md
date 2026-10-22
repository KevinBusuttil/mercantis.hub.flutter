# Atlas Solo — observed usability test protocol (non-technical users)

Status: 22 October 2026. **No session has been run. Every observation below is PENDING.** Widget tests and screenshots are not usability evidence (plan M2.4). This protocol is what makes the observations comparable and honest.

## 1. Purpose and pass rule

The aim is to show that representative owner-operators complete the ten critical Solo journeys **without developer coaching**.

A journey **passes for the release** when all of these hold:

- at least 4 of 5 participants complete it unaided;
- the median time is within the target;
- no participant loses data or posts something wrong without noticing.

Anything a participant repeatedly hesitates over, misreads or asks about becomes a tracked issue, classified `BLOCKER-SOLO-GA`, `PILOT` or `POST-GA` in [SOLO_RELEASE_READINESS.md](SOLO_RELEASE_READINESS.md) (§6).

## 2. Participants

- **5 participants** for the release candidate (finds most severe issues), and 3 more after fixes.
- **Profile:**
  - runs or keeps the books of a small business (services or simple trade);
  - uses a smartphone daily;
  - is **not** a developer, ERP consultant or accountant (at most one bookkeeper among the five);
  - has never used Atlas.
- **Exclude** people who helped build Atlas.
- **Consent:** written consent for observation and notes. Record the screen only, never the face. Use no real customer data: the participant works in the prepared demo book.
- **Accessibility:** if possible, include at least one participant who habitually uses large text and one who is over 60.

## 3. Set-up

- **Device:** a signed release-candidate build on a mid-range Android phone (platform matrix §3). Repeat with an iPhone when iOS reaches "Tested".
- **Book:** restore `pilot-demo.atlasbackup` before each session. It is a Services profile with:
  - 10 customers (2 with overdue invoices);
  - 5 services;
  - 3 suppliers;
  - a bank account with an imported statement of 12 lines.
  Create it once with the setup packs and record its SHA-256 here: `PENDING`.
- **Facilitator script:** read the task card aloud and hand it over. Do not demonstrate, point or name a button. If the participant is stuck for 60 s, or asks, give the **standard prompts** in order. Each prompt counts as assistance:
  1. "What are you looking for?"
  2. "Where would you expect to find it?"
  3. Name the area only ("It's under Money").
  4. Show it. The journey is then *not completed unaided*.
- **Think-aloud:** ask the participant to say what they are looking for. No leading questions.
- **Timing:** from "start" until the participant says "done" or gives up. A 10-minute cap per journey.
- **After each journey:** "How easy was that, 1 (very hard) to 5 (very easy)?", then "Was any word unclear?"

## 4. The ten journeys (task cards)

| # | Task card (read aloud) | Success criterion (checked in the book afterwards) | Target median |
|---|---|---|---|
| J1 | "Add a new customer: Seaview Dental, email accounts@seaview.example." | Customer exists with that name and email | 1 min |
| J2 | "Seaview asked for a price. Prepare a quote for 3 hours of consulting." | Finalised quotation for Seaview, 3 × consulting | 2 min |
| J3 | "They accepted. Turn it into an invoice and make it official." | Posted sales invoice linked to the quote; GL rows exist | 2 min |
| J4 | "Seaview paid half by bank transfer today. Record it." | Payment allocated to the invoice; outstanding = half | 2 min |
| J5 | "You bought printer ink for €24.60 with the business card. Record it, and photograph the receipt." | Posted expense of 24.60 with the receipt attached | 3 min |
| J6 | "Match this week's bank statement lines with what is in Atlas." | At least 10 of the 12 lines matched; no wrong match | 6 min |
| J7 | "A customer returned one item from invoice SINV-…. Give them credit." | Credit note against that invoice; outstanding reduced | 3 min |
| J8 | "Which customers owe you money for more than 30 days, and how much in total?" | Says the right names and total (from AR ageing) | 1 min |
| J9 | "Did the business make a profit this year? How much?" | Says the right P&L figure | 1 min |
| J10 | "Make a backup of the business and keep a copy off this phone." | A new `.atlasbackup` exists and a copy was saved outside the app | 3 min |

The bank-reconciliation screen (J6) has **not** been redesigned for phones (UX matrix §6 ⛔). Expect it to fail on a phone. Run J6 on a tablet too, and record both.

## 5. Capture sheet (one row per participant per journey)

Copy into a spreadsheet. Every cell stays `PENDING` until observed.

| Field | How to record |
|---|---|
| Participant id | P1…P5 (no names) |
| Journey | J1…J10 |
| Completed | Unaided / with prompts (1–3) / shown (4) / gave up |
| Time | mm:ss |
| Wrong taps / navigation | Count of taps into a wrong area before the right one; list the areas |
| Assistance | Highest prompt level used (0–4) and what was asked |
| Confusing terms | Exact words the participant asked about or misread |
| Errors | Anything posted, saved or deleted wrongly; validation messages seen |
| Recovery | Did the participant notice and correct the error themselves? yes / no / n.a. |
| Ease rating | 1–5 |
| Comment | Verbatim quote |

## 6. Results

| Journey | P1 | P2 | P3 | P4 | P5 | Median time | Unaided | Issues raised |
|---|---|---|---|---|---|---|---|---|
| J1 Create customer | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING | — |
| J2 Quotation | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING | — |
| J3 Post invoice | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING | — |
| J4 Receive payment | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING | — |
| J5 Record expense | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING | — |
| J6 Reconcile bank | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING | — |
| J7 Credit / return | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING | — |
| J8 Overdue debt | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING | — |
| J9 Read P&L | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING | — |
| J10 Back up | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING | — |

Session log (date, device, facilitator, participant profile, build): **none yet**.

## 7. After the sessions

1. Turn each repeated problem (2+ participants) into an issue with the evidence (journey, quote, count).
2. Classify it. A problem that leads to a wrong posting or lost data is at least `BLOCKER-SOLO-GA`.
3. Fix, then rerun the affected journeys with 3 new participants.
4. Update the M2 row "Critical UX tasks do not require developer coaching" in the readiness tracker only when §1's pass rule holds for all ten journeys.
