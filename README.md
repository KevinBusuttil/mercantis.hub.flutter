# mercantis.hub.flutter

Full ERP application shell built on [mercantis.core.flutter](https://github.com/kevinbusuttil/mercantis.core.flutter).

## Commercialisation roadmap

The canonical implementation sequence for taking Atlas to commercial readiness is:

- [`docs/COMMERCIALISATION_IMPLEMENTATION_PLAN.md`](docs/COMMERCIALISATION_IMPLEMENTATION_PLAN.md) — current four-milestone execution plan: Atlas Solo RC → Atlas Solo 1.0 → Atlas Team RC → Atlas Team 1.0.
- [`docs/ROADMAP_V2_SOLO_TEAM.md`](docs/ROADMAP_V2_SOLO_TEAM.md) — strategic Solo/Team architecture and edition boundaries. Its older implementation-phase ordering is superseded by the commercialisation plan above.

Implementation agents (Claude Code, ChatGPT/Codex, or maintainers) should read the commercialisation plan first, re-verify the stated gap against current `main`, and implement the earliest incomplete work package whose prerequisites are satisfied.

## Platforms

| Platform | Min version |
|----------|-------------|
| iOS | 17.0 |
| iPadOS | 17.0 |
| macOS | 14.0 |
| Windows | 11 |

## Modules

| Module | DocTypes |
|--------|----------|
| CRM | Lead, Opportunity, Contact, Customer |
| Selling | Quotation, Sales Order, Sales Invoice |
| Buying | Supplier, Purchase Order, Purchase Invoice |
| Stock | Item, Item Group, Warehouse, Stock Entry |
| Accounting | Account, Journal Entry, Payment |
| Setup | Company, Currency, Fiscal Year |

## Getting started

```bash
flutter pub get
flutter run
```

## Architecture

Hub registers its DocTypes and workflows by calling `AppInstaller.install(HubManifest.build())`
during app boot. All document storage, sync, workflow, and expression evaluation is handled
by the `mercantis_core` package.
