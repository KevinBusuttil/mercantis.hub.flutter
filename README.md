# mercantis.hub.flutter

Full ERP application shell built on [mercantis.core.flutter](https://github.com/kevinbusuttil/mercantis.core.flutter).

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
