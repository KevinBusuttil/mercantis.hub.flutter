# mercantis.hub.flutter

Full ERP application shell built on [mercantis.core.flutter](https://github.com/kevinbusuttil/mercantis.core.flutter).

## Commercialisation roadmap

The canonical implementation sequence for taking Atlas to commercial readiness is:

- [`docs/COMMERCIALISATION_IMPLEMENTATION_PLAN.md`](docs/COMMERCIALISATION_IMPLEMENTATION_PLAN.md) — current four-milestone execution plan: Atlas Solo RC → Atlas Solo 1.0 → Atlas Team RC → Atlas Team 1.0.
- [`docs/ROADMAP_V2_SOLO_TEAM.md`](docs/ROADMAP_V2_SOLO_TEAM.md) — strategic Solo/Team architecture and edition boundaries. Its older implementation-phase ordering is superseded by the commercialisation plan above.

Implementation agents (Claude Code, ChatGPT/Codex, or maintainers) should read the commercialisation plan first, re-verify the stated gap against current `main`, and implement the earliest incomplete work package whose prerequisites are satisfied.

## Platforms

Application id `com.neuradix.atlas` on every platform. Support levels are defined, with evidence, in [`docs/release/PLATFORM_MATRIX.md`](docs/release/PLATFORM_MATRIX.md). As of October 2026, **no platform is yet commercially supported**: each builds in CI, none has been tested on hardware.

| Platform | Min version | Release build in CI | Commercially supported |
|----------|-------------|---------------------|------------------------|
| Android phone / tablet | 7.0 (API 24) | Yes (unsigned; signed job behind the `release` environment) | Not yet (pilot target) |
| iOS / iPadOS | 17.0 | Yes (no codesign) | Not yet |
| macOS | 14.0 | Yes (ad-hoc signed) | Not yet |
| Windows | 11 (10 1809+ untested) | Yes (unsigned zip) | Not yet |

Release, signing and readiness: [`docs/release/`](docs/release/) — start with [`SOLO_RELEASE_READINESS.md`](docs/release/SOLO_RELEASE_READINESS.md). User guides: [`docs/solo/`](docs/solo/README.md).

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
flutter pub get --enforce-lockfile
flutter run
```

## Architecture

Hub registers its DocTypes and workflows by calling `AppInstaller.install(HubManifest.build())`
during app boot. All document storage, sync, workflow, and expression evaluation is handled
by the `mercantis_core` package.
