# Build and release

Run from `macos/` (the Swift package root) with Xcode command-line tools selected. Publication is a separate action.

## Local builds

```sh
swift build
swift test
swiftlint lint --strict --no-cache
Scripts/build-app.sh direct
Scripts/build-app.sh app-store
```

The direct bundle is `.build/Tidybyte.app`. The App Store bundle is `.build/app-store/Tidybyte.app`. The App Store script passes `-DAPP_STORE` and applies an ad-hoc sandbox signature for local verification. It excludes Advanced navigation and network-client access. Ad-hoc signatures are not distribution signatures.

`Configuration/Direct.entitlements` and `Configuration/AppStore.entitlements` are the channel-specific entitlement inputs. App Store file access depends on user-selected, persistent folder grants. See [Apple sandbox file-access guidance](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox).

## Direct distribution

Supply a Developer ID Application identity and a notarytool keychain profile through the release environment. Do not put credentials in the repository.

```sh
SIGNING_IDENTITY='Developer ID Application: RELEASE IDENTITY' \
NOTARY_PROFILE=tidybyte-notary \
SPARKLE_PUBLIC_KEY=... SPARKLE_PRIVATE_KEY_FILE=/secure/ed25519.key \
Scripts/package-release.sh direct
```

`package-release.sh` performs the whole pipeline itself: it builds the app, signs Sparkle and the bundle inside out, notarizes the ZIP, staples the app, then builds, signs, notarizes, and staples the DMG, and finishes with `spctl --assess`. Do not re-zip or re-submit the artifacts manually afterwards. A dry run without credentials is `SIGNING_IDENTITY=- SKIP_NOTARIZE=1 Scripts/package-release.sh direct`.

The release operator creates the `NOTARY_PROFILE` keychain profile with `xcrun notarytool store-credentials` before submission. Validate the results before publishing: `codesign --verify --deep --strict .build/Tidybyte.app`, `spctl --assess --type open --context context:primary-signature .build/direct/Tidybyte-<version>.dmg`, and launch the DMG's app once. The release artifacts are `.build/direct/Tidybyte-<version>.dmg` and, when Sparkle keys are supplied, `.build/direct/appcast.xml`.

## App Store distribution

Use the bundle identifier and signing assets registered to the release team. Install the App Store provisioning profile where required before signing. Supply application and installer signing identities:

```sh
SIGNING_IDENTITY='Apple Distribution: RELEASE IDENTITY' \
INSTALLER_IDENTITY='3rd Party Mac Developer Installer: RELEASE IDENTITY' \
Scripts/package-release.sh app-store
```

The output is `.build/app-store/Tidybyte.pkg`. Upload it with Transporter using the release account. Complete App Store Connect privacy information, screenshots, Photos-access explanation, and submission review. Apple credentials, certificates, provisioning, and approval are external inputs.

## Release gates

1. Complete the manual native workflow checks in the validation report.
2. Run Photos mutation tests with a disposable System Photos Library and iCloud disabled.
3. Keep the SwiftLint baseline green (strict lint with the baseline is already a CI merge gate).
4. Test the signed sandbox build's folder-grant renewal, relaunch, and Trash recovery on a clean Mac user account.
5. Sign, notarize or upload, and publish only as a separate release action.
