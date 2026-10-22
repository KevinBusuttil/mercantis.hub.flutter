# Atlas Solo — supported-platform matrix

Status: 22 October 2026 (Solo release-candidate increment, plan M1.6). Owner: product owner (Kevin Busuttil).

Commercial support must be explicit. A folder in the repository is not a supported platform. Each platform below is rated on four separate levels, and a level is only claimed with evidence.

| Level | Meaning | Evidence required |
|---|---|---|
| **Implemented** | Platform project and runner code exist in source control | The files |
| **Buildable** | A clean checkout compiles a **release** build in CI with no manual step | A green `Release builds` job |
| **Tested** | The app was installed and exercised on that platform, and the result recorded | A dated row in [SOLO_RELEASE_READINESS.md](SOLO_RELEASE_READINESS.md) or the device tables below |
| **Commercially supported** | Signed, installable by a customer, upgrade path proven, and support will accept tickets | Signed artifact, install and upgrade drill, product-owner acceptance |

## 1. Summary

| Platform | Implemented | Buildable (CI release build) | Tested on real hardware | Commercially supported |
|---|---|---|---|---|
| **Android phone** | Yes | **Yes**: unsigned AAB on every platform change (`Release builds › Android`) | **No.** Pending the physical-device drills (R1, performance, TalkBack) | **No.** Needs the upload key, a signed install, a device drill and Play listing decisions |
| **Android tablet** | Yes (same build; layouts verified 1024 px in widget tests) | Yes (same AAB) | **No** | **No** |
| **iPhone** | Yes, **from this increment.** No Xcode project was in source control before, so a clone could not build iOS | **Yes**: `Release builds › iOS (release, no codesign)`, green on PR #194 (run 39866746736) | **No** | **No.** Needs an Apple Developer account, signing, TestFlight and a device drill |
| **iPad** | Yes (same project; iPad orientations declared) | Same as iPhone | **No** | **No** |
| **macOS** | Yes. The Xcode project was also missing and is now committed | **Yes**: `Release builds › macOS`, ad-hoc signed, not notarised | **No** (CI compiles, nobody has run the CI artifact) | **No.** Needs Developer ID signing and notarisation |
| **Windows** | Yes | **Yes**: `Release builds › Windows`, unsigned zip | **No** | **No.** Needs code signing and an installer decision |
| Linux, web | Not targets | — | — | Not offered |

**Recommendation for the first pilot (product-owner decision):** support **one** platform first, **Android phone**, signed through Play internal testing, with Windows or macOS as the owner's second device only if the pilot customer needs it. Android is the only platform whose release signing is implemented end to end in CI. iOS additionally needs an Apple account and App Review. Do not market iOS, macOS or Windows until each reaches "Tested" and has its signing in place.

## 2. Per-platform facts

### Android (phone and tablet)

| Item | Value | Source |
|---|---|---|
| Application id | `com.neuradix.atlas` (permanent; product-owner decision 22 Oct 2026) | `android/app/build.gradle.kts` |
| Display name | Neuradix Atlas | `AndroidManifest.xml` |
| Minimum OS | Android 7.0 (API 24), Flutter 3.44's floor | `minSdk = flutter.minSdkVersion` |
| Target / compile SDK | Flutter 3.44 default target; compile 36 | `build.gradle.kts` |
| Release signing | Upload key from `key.properties` or `ATLAS_ANDROID_*` secrets. **Unsigned** without a key; the build **fails** if `ATLAS_REQUIRE_RELEASE_SIGNING=true` and no key. The debug key is never used for a release unless a developer opts in locally (`ATLAS_ANDROID_DEBUG_SIGN_RELEASE=true`). | `build.gradle.kts`, [RELEASE_SIGNING_AND_SECRETS.md](RELEASE_SIGNING_AND_SECRETS.md) |
| Distribution | Google Play (recommended: Play App Signing, internal-testing track for the pilot). Direct APK only for a supervised pilot device. | — |
| Permissions declared by Atlas | `INTERNET` only (Team, AI capture and store connectors; Solo bookkeeping works offline). Camera and files go through system pickers. CI prints the merged release manifest's permissions. | `AndroidManifest.xml`, `Release builds › Android` summary |
| OS backup | **Off** (`allowBackup=false`, data-extraction rules exclude cloud backup and device transfer). Reason: Android Auto Backup copied the unencrypted books to Google Drive and restored this install's device id onto a second phone, which can duplicate document numbers. Atlas's encrypted backup is the supported route. | `res/xml/data_extraction_rules.xml` |
| Data location | App-private storage (`getApplicationSupportDirectory`): `mercantis.db`, `attachments/`, `backups/`, `diagnostics/` | Core `core_providers.dart` |
| Upgrade | In place through the store (same id and signing key, increasing `versionCode`). Schema migrations run on first start; a database from a newer build is refused untouched. | Core `migration_runner.dart` |
| Uninstall | **Deletes the books.** Users must back up first (installation guide). | — |
| Icon | **Flutter default icon.** A branded icon is required before a store listing (GA blocker G-ICON). | `res/mipmap-*` |

### iOS and iPadOS

| Item | Value |
|---|---|
| Bundle id | `com.neuradix.atlas` |
| Display name | Neuradix Atlas (home-screen label may truncate; brand decision) |
| Minimum OS | iOS / iPadOS 17.0 (project deployment target and Podfile) |
| Privacy strings | `NSCameraUsageDescription` and `NSPhotoLibraryUsageDescription` **added in this increment**. Without them iOS terminates the app the moment receipt or proof-of-delivery capture opens the camera, and App Review rejects the build. |
| Lifecycle | Flutter 3.44 UIScene template (`SceneDelegate`) |
| Signing | Not configured in CI. Needs an Apple Developer Program membership, a distribution certificate and an App Store provisioning profile (see the signing doc). CI proves compilation with `--no-codesign`. |
| Encryption export compliance | Atlas encrypts backups with AES-256-GCM. The `ITSAppUsesNonExemptEncryption` answer is a **legal/product decision** (policy checklist item P-7); it is deliberately not set. |
| OS backup | iCloud/iTunes device backup includes app data by default. A device-to-device migration restores the same device id, which is acceptable only when the old device is retired. Documented in the backup guide; excluding the books from iCloud backup is a PILOT decision (R-iOS-BACKUP). |
| Distribution | TestFlight for the pilot, then the App Store |

### macOS

| Item | Value |
|---|---|
| Bundle id | `com.neuradix.atlas`; product name "Neuradix Atlas" |
| Minimum OS | macOS 14 Sonoma (`MACOSX_DEPLOYMENT_TARGET`, Podfile, Info.plist) |
| Sandbox | App Sandbox on; network client; user-selected files read/write; keychain group |
| Signing | CI build is ad-hoc ("sign to run locally"). Distribution needs a Developer ID Application certificate, hardened runtime and **notarisation** (`notarytool`), then stapling. The `keychain-access-groups` entitlement needs a real team id: an ad-hoc build may not be able to use the keychain (Team session storage). Verify on hardware. |
| Distribution | Notarised DMG or ZIP from `atlas.neuradix.com/download` (or the Mac App Store, a separate decision) |

### Windows

| Item | Value |
|---|---|
| Executable | `mercantis_hub_app.exe`, product name "Neuradix Atlas", company "Mercantis" (legal entity to confirm, policy item P-1) |
| Minimum OS | Windows 10 version 1809+ / Windows 11, 64-bit (Flutter's floor). README previously said Windows 11 only; only Windows 11 is proposed for support until Windows 10 is tested. |
| Signing | Unsigned in CI. Needs an Authenticode certificate (OV/EV or Azure Trusted Signing) to avoid SmartScreen warnings. |
| Packaging | CI produces a zip of the release folder. A proper installer (MSIX recommended, for clean upgrade and uninstall) is a GA item, not started. |
| Data location | `%APPDATA%\Mercantis\Neuradix Atlas` (path_provider builds it from the `CompanyName` and `ProductName` in `windows/runner/Runner.rc`; verify on hardware before documenting for customers). **Changing either string after release moves the data folder, so an upgraded app would open empty.** |

## 3. Device and layout classes to test

| Class | Example | Why |
|---|---|---|
| Low/mid Android phone | 3–4 GB RAM, eMMC/UFS 2.x, Android 11–13 (e.g. Samsung Galaxy A1x/A2x, Xiaomi Redmi) | Performance budgets are set for this class |
| Current Android phone | 8 GB, Android 15/16 | Upper reference |
| Android tablet | 10–11" | Tablet layout |
| iPhone | iPhone SE (2nd/3rd gen) for the small screen, plus a current model | VoiceOver and small-screen ergonomics |
| iPad | 10th gen | Tablet layout, keyboard |
| Mac | Apple silicon, macOS 14 | Desktop, keyboard-only |
| Windows PC | Windows 11, 1366×768 and 1920×1080 at 100 %/150 % scaling | Desktop scaling |

## 4. Upgrade compatibility rules

1. The application/bundle id and Android signing key never change after the first published build.
2. `versionCode` / `CFBundleVersion` strictly increase: the pipeline uses `1000 + workflow run number`.
3. Every schema change goes through Core `MigrationRunner` (one transaction per step) and is covered by `migration_safety_test` (upgrade from v1 to the latest).
4. A database written by a newer build is refused, never opened (`UnsupportedSchemaVersionException`), and the start-up screen tells the user to update rather than reinstall.
5. A backup from a newer build is refused by an older build.
6. Devices sharing a company folder must run the same Atlas version (stated in the upgrade guide).
7. On Windows, `CompanyName`/`ProductName` in `Runner.rc` are part of the data path and must not change after release (rule 1 for Windows). On macOS the sandbox container is keyed by the bundle id.
8. **Changing to `com.neuradix.atlas`** means a development build installed under the old id `com.mercantis.mercantis_hub_app` installs **beside** the new app, not over it. Move data with an Atlas backup and restore. No customer has the old id.
