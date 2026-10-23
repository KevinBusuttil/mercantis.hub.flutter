# Release signing and secrets

Status: 22 October 2026. Nothing in this repository is a real key, certificate, password or account. **Never commit one.** CI fails the `Secret and dependency scan` job if a keystore, provisioning profile, `.p12`/`.p8`, `key.properties` or Google/Firebase service file is committed, and gitleaks scans the whole history.

Who does what:

- **Product owner:** creates the store and developer accounts, generates and keeps the keys, approves every signed run.
- **CI:** reads the secrets only inside the protected `release` environment and never prints them.
- **Developers:** never hold the upload key unless the product owner decides so.

## 1. GitHub environment `release` (one-time)

1. In the repository, open **Settings › Environments › New environment**, and name it `release`.
2. Under **Required reviewers**, add the product owner. Every signed run then waits for an explicit approval.
3. Under **Deployment branches and tags**, choose **Selected branches and tags**, and allow `main` and tags `atlas-v*`.
4. Add the secrets below as **environment** secrets, not repository secrets, so that pull-request workflows can never read them.

The repository is **public**. Environment secrets are not exposed to workflows triggered from forks, and the signed job runs only from `workflow_dispatch`.

## 2. Android

### 2.1 Create the upload key (product owner, once, offline)

```bash
keytool -genkeypair -v \
  -keystore atlas-upload.jks -storetype JKS \
  -keyalg RSA -keysize 4096 -validity 10000 \
  -alias atlas-upload
```

- Store `atlas-upload.jks` and both passwords in a password manager, plus one offline copy. **Losing the upload key** with Play App Signing is recoverable through Play support; losing an app-signing key without Play App Signing is not.
- Enrol the app in **Play App Signing** when creating the Play listing for `com.neuradix.atlas`. Google then holds the app-signing key, and this file is only the upload key.

### 2.2 Environment secrets

| Secret | Value |
|---|---|
| `ATLAS_ANDROID_KEYSTORE_BASE64` | `base64 -w0 atlas-upload.jks` |
| `ATLAS_ANDROID_KEYSTORE_PASSWORD` | keystore password |
| `ATLAS_ANDROID_KEY_ALIAS` | `atlas-upload` |
| `ATLAS_ANDROID_KEY_PASSWORD` | key password |

### 2.3 How the build uses them

`android/app/build.gradle.kts` reads, in this order, the `ATLAS_ANDROID_*` environment variables, then `android/key.properties` (git-ignored; template `android/key.properties.example`).

| Situation | Result |
|---|---|
| All four values present | Release signed with the upload key |
| None present (pull requests, forks, a fresh clone) | Release **unsigned**: it compiles but cannot be installed or uploaded |
| `ATLAS_REQUIRE_RELEASE_SIGNING=true` and any value missing | **Build fails.** The signed CI job sets this, so it can never ship an unsigned or debug-signed artifact by accident |
| `ATLAS_ANDROID_DEBUG_SIGN_RELEASE=true` (developer machine only) | Debug-signed release for a local device test. Never distributable. Refused together with the require flag |

The signed job (`Release builds › Android (signed upload build)`) runs only when a maintainer starts **Release builds** manually with **signed** ticked, and the `release` environment approves it. It:

- writes the keystore to the runner's temp folder;
- builds the AAB and APK;
- verifies the signature (`jarsigner`, `apksigner --print-certs`);
- writes `SHA256SUMS.txt`;
- deletes the keystore;
- uploads the files as a **workflow artifact** (30 days).

**It does not upload to Google Play.** Uploading to the internal-testing track is a manual product-owner step until store publishing is authorised.

## 3. Apple (iOS, iPadOS, macOS): not yet configured

**Prerequisite:** an Apple Developer Program membership, owned by the business. Without it nothing below can be done, and iOS/macOS stay "buildable, unsigned".

| Need | Platform | Create in | Proposed secret |
|---|---|---|---|
| Apple Distribution certificate (.p12) | iOS | Certificates, IDs & Profiles | `ATLAS_APPLE_DIST_CERT_P12_BASE64`, `ATLAS_APPLE_DIST_CERT_PASSWORD` |
| App Store provisioning profile for `com.neuradix.atlas` | iOS | Profiles | `ATLAS_IOS_PROFILE_BASE64` |
| Developer ID Application certificate (.p12) | macOS outside the Mac App Store | Certificates | `ATLAS_MAC_DEVID_CERT_P12_BASE64`, `ATLAS_MAC_DEVID_CERT_PASSWORD` |
| App Store Connect API key (.p8), for notarisation and TestFlight upload | both | App Store Connect › Users and Access › Integrations | `ATLAS_ASC_KEY_ID`, `ATLAS_ASC_ISSUER_ID`, `ATLAS_ASC_KEY_P8_BASE64` |
| Team id | both | Membership page | `ATLAS_APPLE_TEAM_ID` (not secret, but kept with the rest) |

**Procedure when the account exists** (to be automated as a `release`-environment job, then verified):

1. Create a temporary keychain on the macOS runner and import the certificate. Install the profile.
2. Set `DEVELOPMENT_TEAM` and manual signing at build time with `xcodebuild` overrides (`flutter build ipa --export-options-plist=<generated>`). Do not commit the team id into `project.pbxproj` unless the product owner prefers it.
3. iOS: run `flutter build ipa --release`, then upload to TestFlight with Transporter or `xcrun altool --upload-app` using the API key (manual until authorised).
4. macOS:
   - run `flutter build macos --release`;
   - run `codesign --deep --options runtime --timestamp` with the Developer ID certificate;
   - zip with `ditto -c -k --keepParent`;
   - submit with `xcrun notarytool submit --wait` using the API key;
   - staple with `xcrun stapler staple`;
   - check with `spctl -a -vv`.
5. Delete the keychain.

**Open decision P-7 (legal):** the export-compliance answer for AES-256-GCM backup encryption (`ITSAppUsesNonExemptEncryption`).

## 4. Windows: not yet configured

| Need | Proposed secret |
|---|---|
| Code-signing certificate. Either Azure Trusted Signing (recommended: no hardware token), or an OV/EV certificate in a cloud HSM | Trusted Signing: `ATLAS_AZURE_TENANT_ID`, `ATLAS_AZURE_CLIENT_ID`, `ATLAS_AZURE_CLIENT_SECRET`, account and profile names. OV/EV: the provider's signing credentials |

When available:

- sign `mercantis_hub_app.exe` and the installer with `signtool sign /fd SHA256 /tr <timestamp-url> /td SHA256`;
- check with `signtool verify /pa`.

**Packaging:** MSIX is recommended, for clean install, upgrade and uninstall, and Windows treats it as a trusted package once signed. It needs a publisher name matching the certificate subject, so the legal entity (policy item P-1) must be settled first.

## 5. Rules

- Secrets only ever come from the `release` environment. They are never echoed or written into artifacts, logs or the repository.
- A signed artifact is produced only from `main` or an `atlas-v*` tag, with a product-owner approval.
- **No store upload or public GitHub release** happens without the product owner's written authorisation for that version.
- Rotate a secret immediately if it ever appears in a log, and record the rotation in the release record.
