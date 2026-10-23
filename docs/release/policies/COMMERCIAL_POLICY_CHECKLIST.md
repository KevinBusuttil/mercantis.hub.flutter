# Atlas Solo — commercial and legal policy checklist

Status: **DRAFT, 22 October 2026. Nothing in this folder has been reviewed by a lawyer or approved by the product owner.** These are working drafts written so a lawyer can review against something concrete. They are not to be shown to customers as final terms. The drafts assume an EU (Malta) seller and EU customers. A lawyer must confirm that assumption.

| # | Decision or document | Needed for | Owner | Status |
|---|---|---|---|---|
| P-1 | **Legal entity** that publishes Atlas: the name in store listings, the Windows publisher (`CompanyName` in `windows/runner/Runner.rc`, currently "Mercantis"), the macOS copyright (`macos/Runner/Configs/AppInfo.xcconfig`), the Apple and Google developer accounts, and the contracting party in the EULA | Pilot (store accounts), GA | Product owner | **OPEN.** The binaries currently say "Mercantis". Changing the Windows `CompanyName` after the first release moves the data folder (platform matrix §4 rule 7), so **decide before the first Windows release** |
| P-2 | Licence / EULA | Pilot (a signed pilot agreement can stand in), GA | Product owner + lawyer | Draft: [EULA_DRAFT.md](EULA_DRAFT.md) |
| P-3 | Privacy notice: what Neuradix processes (support reports, store analytics, optional AI capture and Team) | Store listing (both stores require a privacy URL), GA | Product owner + lawyer / DPO | Draft: [PRIVACY_NOTICE_DRAFT.md](PRIVACY_NOTICE_DRAFT.md) |
| P-4 | Support terms and severity levels | Pilot | Product owner | Draft: [SUPPORT_AND_SEVERITY_POLICY.md](SUPPORT_AND_SEVERITY_POLICY.md) |
| P-5 | Backup responsibility statement, shown at onboarding and in the EULA | Pilot | Product owner + lawyer | Draft: [BACKUP_RESPONSIBILITY_STATEMENT.md](BACKUP_RESPONSIBILITY_STATEMENT.md) |
| P-6 | Data-processing terms (Art. 28 GDPR). Only needed where Neuradix processes customer data: Atlas Team, support with a customer-supplied backup, AI capture through a Neuradix-held key. **Solo with no Team and the customer's own AI key may need none.** | GA if any processing service is sold | Lawyer | Not drafted, pending the lawyer's view on whether Solo needs it |
| P-7 | **Export-compliance answer** for AES-256-GCM backup encryption: the iOS `ITSAppUsesNonExemptEncryption` key and the App Store Connect questionnaire. Standard encryption in a mass-market app is commonly exempt, but this is a legal determination | Any iOS/macOS App Store build | Lawyer | **OPEN.** Deliberately not set in `Info.plist` |
| P-8 | Fiscal-receipt claims (Malta). Atlas is **not** an approved fiscal cash register. Store listing and marketing must not say otherwise. | Store listing, marketing | Product owner | Rule stated in plan §16; copy check required before listing |
| P-9 | Pricing, payment and refund terms (Play billing or direct invoice) | GA | Product owner | Not started |
| P-10 | Store content declarations: Play Data safety form, Apple privacy "nutrition label", content rating | Store listing | Product owner | Not started. The answers follow from P-3 |
| P-11 | Trademark and branding: "Neuradix Atlas" name search, and the icon (G-ICON) | Store listing | Product owner | Not started. The app currently ships the Flutter default icon |
| P-12 | Third-party licences notice (Flutter and pub packages) | GA | Engineering | **Open.** Atlas has no licences page yet. Add Flutter's `showLicensePage` under Settings › About before GA (small change, not done here to keep scope) |

**Rule:** no store listing, public download page or paid sale until P-1, P-2, P-3, P-5, P-7 (for Apple), P-10 and P-11 are closed by the product owner, with legal review where marked.
