# Atlas marketing screenshots

Atlas marketing images must be generated from the real Flutter UI, not drawn independently of the product.

The canonical owner-dashboard image is produced by `test/marketing/atlas_owner_dashboard_golden_test.dart`. It renders the production `DashboardResultGrid` with `MercantisTheme.light()` and a deterministic synthetic business dataset. No customer data is used.

The fixture deliberately uses plausible but fictional values and names. Its purpose is visual demonstration, not accounting validation. Product behaviour remains covered by the normal application and engine tests.

## Generate locally

```bash
flutter pub get
flutter test test/marketing/atlas_owner_dashboard_golden_test.dart --update-goldens
```

The generated image is:

```text
test/marketing/goldens/atlas_owner_dashboard_1440x900.png
```

## CI generation

`.github/workflows/marketing-screenshots.yml` regenerates the canonical image on relevant pull requests and can also be run manually. On same-repository branches it commits a changed golden back to the source branch so the screenshot stays versioned alongside the UI that produced it.

## Rules for website use

- Label screenshots as an actual Atlas development build or product UI.
- Use only deterministic synthetic data.
- Do not add controls, cards, workflows or statuses that do not exist in the rendered product component.
- Regenerate screenshots after intentional UI changes instead of editing the PNG manually.
- Treat the screenshot as product evidence, not as a promise that every commercial-release gate is complete.
