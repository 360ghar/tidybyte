# Build and release

Run from the repository root with Xcode command-line tools selected. Publication is a separate action.

## Local builds

```sh
swift build
swift test
swiftlint lint --strict --no-cache
Scripts/build-app.sh direct
Scripts/build-app.sh app-store
```

The direct bundle is `.build/macOS-Cleaner.app`. The App Store bundle is `.build/app-store/macOS-Cleaner.app`. The App Store script passes `-DAPP_STORE` and applies an ad-hoc sandbox signature for local verification. It excludes Advanced navigation and network-client access. Ad-hoc signatures are not distribution signatures.

`Configuration/Direct.entitlements` and `Configuration/AppStore.entitlements` are the channel-specific entitlement inputs. App Store file access depends on user-selected, persistent folder grants. See [Apple sandbox file-access guidance](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox).

## Direct distribution

Supply a Developer ID Application identity through the release environment. Do not put credentials in the repository.

```sh
SIGNING_IDENTITY='Developer ID Application: RELEASE IDENTITY' Scripts/package-release.sh direct
xcrun notarytool submit .build/direct/macOS-Cleaner.zip --keychain-profile RELEASE_PROFILE --wait
xcrun stapler staple .build/macOS-Cleaner.app
xcrun stapler validate .build/macOS-Cleaner.app
ditto -c -k --keepParent .build/macOS-Cleaner.app .build/direct/macOS-Cleaner.zip
```

The release operator configures `RELEASE_PROFILE` in Keychain before submission. Verify the notarization result before publishing the ZIP.

## App Store distribution

Use the bundle identifier and signing assets registered to the release team. Install the App Store provisioning profile where required before signing. Supply application and installer signing identities:

```sh
SIGNING_IDENTITY='Apple Distribution: RELEASE IDENTITY' \
INSTALLER_IDENTITY='3rd Party Mac Developer Installer: RELEASE IDENTITY' \
Scripts/package-release.sh app-store
```

The output is `.build/app-store/macOS-Cleaner.pkg`. Upload it with Transporter using the release account. Complete App Store Connect privacy information, screenshots, Photos-access explanation, and submission review. Apple credentials, certificates, provisioning, and approval are external inputs.

## Release gates

1. Complete the manual native workflow checks in the validation report.
2. Run Photos mutation tests with a disposable System Photos Library and iCloud disabled.
3. Resolve the existing repository-wide SwiftLint violations before using strict lint as a release gate.
4. Test the signed sandbox build's folder-grant renewal, relaunch, and Trash recovery on a clean Mac user account.
5. Sign, notarize or upload, and publish only as a separate release action.
