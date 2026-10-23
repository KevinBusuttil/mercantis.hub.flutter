# Atlas Solo — accessibility acceptance

Status: 22 October 2026.

- **Automated checks:** run and pass.
- **Manual checks:** **PENDING**. Nobody has used Atlas with TalkBack, VoiceOver or a keyboard only, on a device, and recorded it.

## 1. Automated (CI, `Solo commercial acceptance gate › Accessibility guidelines and responsive layouts`)

`test/accessibility/accessibility_guidelines_test.dart` applies Flutter's platform guidelines to 15 screens:

| Screen | Android tap ≥ 48 dp | iOS tap ≥ 44 pt | Tap targets labelled | Text contrast (WCAG AA) |
|---|---|---|---|---|
| Services home, phone (light) | ✅ | ✅ | ✅ | ✅ |
| Services home, phone (dark) | ✅ | ✅ | ✅ | ✅ |
| Services home, tablet | ✅ | ✅ | ✅ | ✅ |
| Trade home, phone | ✅ | ✅ | ✅ | ✅ |
| Retail home, phone | ✅ | ✅ | ✅ | ✅ |
| Money | ✅ | ✅ | ✅ | ✅ |
| Sales | ✅ | ✅ | ✅ | ✅ |
| Reports | ✅ | ✅ | ✅ | ✅ |
| Setup | ✅ | ✅ | ✅ | ✅ |
| Business type & features | ✅ | ✅ | ✅ | ✅ |
| Profit & loss summary | ✅ | ✅ | ✅ | ✅ |
| Who owes you (AR ageing) | ✅ | ✅ | ✅ | ✅ |
| Balance sheet summary | ✅ | ✅ | ✅ | ✅ |
| First-run setup | ✅ | ✅ | ✅ | ✅ |
| Help & diagnostics, start-up error | ✅ | ✅ | ✅ | ✅ |

**Also automated, from the UX increment:**

- No overflow at 360–1440 px.
- 200 % text on a 360 px phone.
- Report figures carry semantic meaning, not colour only (`test/ux/*`).

**Not covered automatically:**

- Database-backed **list and form screens**: customer, quotation, invoice, payment, expense and credit-note forms, and the bank-reconciliation screen. The widget-test harness has no live database. Run them in the manual pass, or extend the `integration_test/` suite on a device. Tracked as `A11Y-FORMS` (PILOT).
- **Contrast of images and non-text elements** (icons, chart bars). The guideline checks text only.

## 2. Manual matrix (all PENDING)

Run on the signed release candidate. "Pass" means the journey can be completed and every control is announced with a meaningful name, role and state, in a logical order, with no trap.

| # | Check | Android phone + TalkBack | iPhone + VoiceOver | Android tablet | iPad | Mac (keyboard only) | Windows (keyboard only) |
|---|---|---|---|---|---|---|---|
| A1 | First-run setup to "ready to trade" | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING |
| A2 | J1 create customer (form labels, required-field errors announced) | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING |
| A3 | J3 post invoice (line items, totals announced, confirmation dialog) | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING |
| A4 | J4 receive payment | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING |
| A5 | J5 record expense with camera receipt | PENDING | PENDING | n.a. | PENDING | n.a. | n.a. |
| A6 | J6 bank reconciliation | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING |
| A7 | J8/J9 reports: summary figures read with their meaning ("needs attention", not colour) | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING |
| A8 | J10 backup: passphrase fields, typed REPLACE confirmation on restore | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING |
| A9 | Destructive actions (cancel/reverse, delete, restore) always confirmed | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING |
| A10 | Errors understandable without colour (validation, sync failed, postings owed) | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING |
| A11 | Large text: OS font size at maximum, display size at largest. J1, J3, J9 usable with no clipped labels or buttons | PENDING | PENDING | PENDING | PENDING | n.a. | n.a. |
| A12 | Focus order and visible focus ring; every action reachable with Tab, Enter or Space, and Esc closes dialogs | n.a. | n.a. | n.a. | n.a. | PENDING | PENDING |
| A13 | Physical ergonomics: one-handed reach of the phone bar and primary buttons; tap accuracy while standing; glare outdoors | PENDING | PENDING | n.a. | n.a. | n.a. | n.a. |
| A14 | Tablet: landscape and portrait, split-screen and multitasking window, hardware keyboard | n.a. | n.a. | PENDING | PENDING | n.a. | n.a. |
| A15 | Display scaling 150 %/200 % (desktop) | n.a. | n.a. | n.a. | n.a. | PENDING | PENDING |

For each cell, record:

- device and OS;
- Atlas build;
- date;
- tester;
- pass or fail;
- the issue id for every failure.

**Severity:**

- `BLOCKER-SOLO-GA`: a journey cannot be completed with a screen reader or keyboard.
- `PILOT`: a control is unlabelled or in the wrong order, but the journey is completable.
- `POST-GA`: cosmetic.
