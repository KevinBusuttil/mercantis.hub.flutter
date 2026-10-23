# Atlas Solo — support and severity policy (DRAFT)

> **DRAFT. Not approved by the product owner.** Response targets below are proposals for a small team running a pilot. They are not commitments until the product owner sets them.

## Channel

- **Pilot:** a named contact at Neuradix, by [email address] and [phone/WhatsApp], [hours, time zone].
- **GA:** [support email or portal, hours].

## What to send

1. The **diagnostics report** (Settings › Help & diagnostics › **Save report**) and its **Diagnostic id**.
2. What you did, what you expected, and what happened. Include the screen and a screenshot if possible.
3. Never your passphrase, PIN, passwords or keys.

## Severity levels

| Level | Meaning | Examples | Proposed first response (pilot) | Proposed target to fix or work around |
|---|---|---|---|---|
| **S1 Critical** | Books cannot be opened, data loss, wrong accounting posted silently, or restore fails | Start-up error; a backup that will not restore; totals that do not reconcile with no user error | 4 working hours | Workaround in 1 working day; fix in the next build |
| **S2 High** | A core task cannot be completed, with no workaround | Cannot post invoices; cannot receive payments | 1 working day | 3 working days |
| **S3 Normal** | A task is impaired but there is a workaround | A report layout problem; a confusing message | 2 working days | A planned release |
| **S4 Question** | How-to, or a feature request | — | 3 working days | — |

Any S1 is reviewed by engineering the same day, and recorded with its diagnostic id in the incident log ([FIRST_CUSTOMER_PILOT.md](../FIRST_CUSTOMER_PILOT.md) §7).

## Supported versions and platforms

- The current release and the one before it.
- Platforms marked "Commercially supported" in [PLATFORM_MATRIX.md](../PLATFORM_MATRIX.md). At the pilot, only Android phone is planned.

## Known limitations route

Known issues and their workarounds are published in [the release notes / a known-issues page] for each version, from the residual-issue list in [SOLO_RELEASE_READINESS.md](../SOLO_RELEASE_READINESS.md).

## Data handling

See the privacy notice. Support works from the diagnostics report. A customer backup is accepted only with the customer's written agreement for a specific S1 case. It is deleted when the case closes, and the customer keeps the passphrase.
