# Malta Fiscal Receipts — Phase 3 Precondition (V2 Hospitality POS)

Verified 2026-07-12 as the roadmap's Phase 3 gate. Verdict: **proceed** —
software-side compliance is achievable with what Atlas already has; the
outstanding item is a certification *process*, not a code blocker.

## What the law requires (13th Schedule, VAT Act)

1. **Every B2C supply needs a fiscal receipt at the time of the
   transaction.** Restaurants, snack bars and catering are explicitly in
   the 13th Schedule's scope, alongside retail.
2. **A software POS may only issue fiscal receipts after prior written
   approval by the Commissioner (Malta Tax and Customs Administration).**
   The application is supported by a compliance certificate from a
   registered auditor; approval grants an **EXO number** that must be
   printed on every fiscal receipt the system issues.
3. **Technical expectations the auditor certifies:** sequential receipt
   numbering that cannot be overridden, data-integrity safeguards that
   prevent retroactive alteration of issued receipts, and a complete audit
   trail of every transaction.
4. **Mandatory receipt content:** business identity with VAT registration
   number, EXO number, date, sequential receipt number, description of the
   goods/services, amounts, and the VAT breakdown.
5. **Outage fallback:** when the register/POS is out of order, a manual
   MTCA fiscal receipt book must be used per supply until it is repaired.

## How Atlas lines up

| Requirement | Atlas mechanism |
|---|---|
| Unbreakable sequential numbering | Per-till receipt series (`POS-.{till_series}.-.####`, Phase 0.1) on ADR-042 counter blocks — offline-safe, never reused after delete |
| No retroactive alteration | Submitted documents are immutable (docstatus lifecycle); Team mode adds the 409-immutable sync plane; official numbering is server-side and gap-free |
| Complete audit trail | `audit_log` rows for create/update **and** submit/cancel/amend/delete (Phase 0.8), plus the append-only ledger spine |
| Receipt content | 80mm builder prints business name, VAT No, receipt id, date, lines, VAT breakdown, tenders; **EXO number line added in V2-1** (`POS Profile.exo_number`) |
| Outage fallback | Operational procedure (manual receipt book) — documented for operators, nothing to build |

## What this means for Phase 3

- Build the hospitality features (tables, tabs, modifiers, kitchen
  tickets, splits, void/comp audit) on the existing POS spine — nothing in
  the law forbids it.
- Keep every sale on the fiscal rails: tabs are *pre-sale* working state;
  money and the fiscal receipt exist only when the tab settles into a POS
  Invoice with its sequential per-till number.
- Voids/comps must leave an audit trail (V2-5) — this is also what the
  auditor will look for.
- **Before a Maltese customer goes live issuing fiscal receipts from
  Atlas POS**, Busuttil Technologies needs the EXO approval: engage a
  registered auditor to certify the system against the Thirteenth
  Schedule and apply to the MTCA. Until then, operators can lawfully use
  approved fiscal cash registers or MTCA receipt books alongside Atlas.

## Sources

- Zampa Partners — EXO Numbers: https://zampapartners.com/insights/exo-numbers-article
- MTCA — Fiscal Receipts, Invoices and Credit Notes: https://mtca.gov.mt/business-tax/vat1/vat-compliance/fiscal-receipts--invoices-and--credit-notes/fiscal-receipts--invoices-and-credit-notes
- MTCA — Tax Invoice and Fiscal Receipts FAQs (PDF): https://mtca.gov.mt/docs/default-source/documents/business-tax/vat/faqs/tax-invoice-and-fiscal-receipts---faqs.pdf
- VATupdate — Official Methods for Issuing Fiscal Receipts in Malta (2026-05-18): https://www.vatupdate.com/2026/05/18/official-methods-for-issuing-fiscal-receipts-in-malta-cash-registers-pos-systems-or-receipt-books/
- iLabPOS — Registering your POS System with the VAT Department (PDF): http://ilabmalta.com/ilabposmanual/iLabPOS_VAT_Regulations.pdf
