# V8 — Clinic Pack (Medical GP Vertical): Specification

Status: **SPEC ONLY — not scheduled, not implemented.** Drafted 2026-07-12
as the scoping document for a GP-practice offering on Neuradix Atlas.
Trigger to build: a committed clinic prospect (the roadmap's
demand-driven rule). Owner: Busuttil Technologies.

## 1. Positioning

The business side of a medical practice — front desk, billing, books —
as a composed Atlas app. **Atlas is not, and will not become, an
EMR/EHR.** Clinical notes, prescriptions, diagnoses and histories live
in a certified clinical system and reach Atlas only as integration
events (command API + webhooks), per the roadmap doctrine
("integrations, never builds: clinical records"). This boundary is a
selling point, not a limitation: the patient record stays in a system
built for it; the money lives in a system built for that.

The pitch: 80–90% of practice management already exists and is tested;
the remainder is this pack plus two small platform builds.

## 2. What composes as-is (no code)

| Practice need | Existing Atlas mechanism |
|---|---|
| Doctors' diaries, conflict-free booking | S1 Scheduling: doctors are Schedulable Resources; booking screen + schedule board (Phase 4) |
| Front desk: book, take deposit, complete-to-invoice | P4 BookingService (book = slot + S4 deposit in one move; completion invoices at S8 price with deposit auto-applied) |
| Consultation billing, receipts, statements | Selling + Accounting + per-till series if fiscal receipts apply |
| Annual check-up recalls | Maintenance Contract mechanism (standing agreement generating dated follow-ups into a queue) |
| Books, VAT filing, bank rec, accountant handoff | Accounting, Banking, Compliance modules |
| Multi-user practice (reception + doctors) | Team backend tenancy: server-side posting, official numbers, credentials |

## 3. The manifest composition

A dedicated AppManifest (working name `app.mercantis.clinic`) or a
`clinic` BusinessPreset on the Hub manifest:

- **Included**: Setup, Tax, CRM, Selling, Accounting, Compliance,
  Banking, Scheduling, Booking, POS (only if fiscal receipts required —
  see §7).
- **Excluded**: Stock*, Manufacturing, Deliveries, Fulfilment,
  Hospitality, Field Service, Rental, Property, Construction,
  Membership, Channels. (*Stock returns if S7 vaccines option is taken.)
- **Vocabulary**: labels are metadata — workspace and doctype labels
  read "Patients" (Customer), "Consultations" (Appointment/Invoice),
  "Doctors" (Schedulable Resource). Renaming is configuration, not code.

### Clinic Setup Pack contents — ✅ SHIPPED (B-2, built-in pack `clinic`)
- Items: Consultation, Follow-up Consultation, Home Visit (all exempt
  via `VAT-EX-MED`), Medical Certificate / Report (deliberately NO
  code — certificates are not therapeutic care, so the book's default
  standard band applies).
- Tax: `VAT-EX-MED` exempt code with the Article 132(1) exemption
  reason (B-1 categories carry it onto the e-invoice as category E).
- Accounts: Customer Deposits liability (procedure deposits).
- Resource seed: "Doctor" (Person); module toggles: appointments on;
  stock, POS, projects, manufacturing, deliveries off (POS returns if
  §7 answers yes).
- Field guidance per §6.1: the Appointment subject field now carries
  the neutral-wording guidance platform-wide.

## 4. New platform builds (small, priced into the pack)

### 4.1 VAT exemption category (required) — ✅ SHIPPED (B-1)
Medical services are VAT-**exempt** in Malta (not zero-rated).
Delivered platform-wide, ahead of the pack build:
- Tax Code carries `vat_category` (Standard / Zero-Rated / Exempt /
  Reverse Charge / Out of Scope) + `exemption_reason` (BT-120). Blank
  category still derives S/Z from the rate.
- UBL export emits the category per line and per subtotal — E carries
  its TaxExemptionReason; two 0% codes never merge into one subtotal.
- Malta VAT return reports exempt supplies in their own box (M4a),
  outside the rated-supplies sections; UK box 6 keeps including them.
- Seeded Exempt/Zero-Rated bands carry their categories; re-running
  starter setup backfills them into existing books. The clinic Setup
  Pack still owes the medical-specific reason wording (Article 132(1)).

### 4.2 Appointment reminders (required) — ✅ SHIPPED (B-3)
Delivered on the payment-reminder pattern (copy-first; in-app sending
remains a later platform step):
- Neutral visit-reminder text (service + slot, never the reason — §6.1
  enforced by construction: the builder has no field for a reason).
- `AppointmentReminderService.dueReminders` — open appointments in the
  next 48h whose reminder hasn't gone out; `reminder_sent_at` stamps
  the appointment so nobody is nagged twice.
- Booking screen: a "Reminders to send" card (one tap copies + stamps)
  and a mark-no-show action on today's open rows; No Show was already
  a first-class status.
- "Copy visit reminder" is also a document action on any open,
  upcoming Appointment.

### 4.3 S7 batch/expiry (OPTIONAL — only if the practice stocks vaccines)
Vaccines demand batch numbers + expiry on receipt, issue and count.
This is the roadmap's deferred "deepest ledger surgery"; a clinic
client that dispenses is precisely the paying segment the deferral
waited for. Scope and price separately; do NOT fold into the base pack.
- Estimate: 3–4 increments (SLE surgery + UI + tests).

### 4.4 Insurance / third-party billing (OPTIONAL)
An insurer is billable as a Customer today. A claims workflow
(submission batch, per-patient allocation, rejection/partial
settlement) is a separate module — only if the prospect's payer mix
justifies it. Estimate: 2–3 increments.

## 5. Integration contract (the EMR line)

- Outbound webhooks: appointment booked / completed / cancelled;
  invoice posted.
- Inbound commands: create/complete appointment, draft invoice for a
  completed encounter.
- The Customer record carries billing identity ONLY (name, contact,
  payer). No clinical field is ever added to any Atlas doctype — this
  is a review-time rule for all future Clinic Pack work.

## 6. Data protection posture (GDPR, incl. Article 9)

Even without clinical records, a medical appointment book is likely
"data concerning health" — design accordingly:

### 6.1 Free-text discipline
The schema is safe; free text is the risk. Defaults and field guidance
keep visit reasons out of appointment subjects and invoice line
descriptions ("Consultation", never the complaint). Pack-seeded
defaults + a line in the operator guide.

### 6.2 Erasure vs the immutable ledger
Statutory retention (10y Maltese accounting records) lawfully overrides
erasure for posted invoices. Design note to implement WITH the pack:
an anonymise-party action that scrubs the Customer master and expired
appointment history while posted documents survive with a pseudonymised
party reference. Painful to retrofit under a live request — build it
up front.

### 6.3 Roles and papers
GP = controller under Art. 9(2)(h) (care provision under professional
secrecy); Busuttil Technologies = processor: signed DPA, EU hosting
(verify droplet region; DigitalOcean listed as sub-processor),
encryption at rest, breach-notification path. Lightweight DPIA as
good practice; DPO not triggered at single-practice scale — revisit if
hosting many clinics. One hour of data-protection counsel before first
go-live.

## 7. Fiscal receipts (open question for the EXO engagement)

Whether exempt medical supplies trigger the 13th Schedule
fiscal-receipt obligation — and whether mixed practices (exempt
consultations + taxable certificates/cosmetic services) need the
per-till series for the taxable part — must be answered by the
registered auditor during the EXO certification process. The per-till
fiscal machinery exists either way; this decides whether POS enters
the clinic manifest.

## 8. Delivery shape (when triggered)

1. **C-1**: exemption category (tax + UBL E + VAT boxes) — platform-wide
   value, ships even if the prospect stalls.
2. **C-2**: clinic preset + Setup Pack + vocabulary + anonymise-party
   action.
3. **C-3**: appointment reminders.
4. **C-4/C-5 (optional, separately priced)**: S7 vaccines; insurance
   claims.
5. Operational track alongside: DPA template, DPIA, EMR integration
   workshop with the client's clinical-system vendor, auditor question
   (§7).

## 9. Explicit non-goals

Clinical records of any kind; prescriptions; lab results; medical
device classification territory; patient-facing portals with health
content. If a prospect insists on these inside Atlas, the answer is a
partner EMR, not a build.
