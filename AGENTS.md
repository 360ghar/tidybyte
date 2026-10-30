# AGENTS.md

This repository is a monorepo with three products. Each folder builds on its
own. Run a folder's commands from inside that folder.

| Folder | Product | Read first |
|---|---|---|
| `ios/` | iPhone and iPad app (Swift, SwiftUI, XcodeGen) | `ios/AGENTS.md` |
| `macos/` | Mac app (SwiftPM, Swift 6) | `macos/AGENTS.md` |
| `website/` | Marketing site (Astro, Tailwind) | `website/DEPLOY_CHECKLIST.md` |

Toolchain: Xcode 26+ (CI pins `Xcode_26.3`), XcodeGen, Node 22.12+, macOS 26
on Apple silicon.

## Commands

Run these from inside each folder:

- `ios/`: `xcodegen generate` first — the `.xcodeproj` is not in git, so
  regenerate it after any `project.yml` change. Build and test with
  `xcodebuild -project Tidybyte.xcodeproj -scheme Tidybyte -destination
  'platform=iOS Simulator,name=<installed iPhone>' CODE_SIGNING_ALLOWED=NO`.
  Release, App Store, and creatives tooling is npm scripts in
  `ios/package.json` (`npm run growth`, `archive`, `publish:*`); there is no
  fastlane.
- `macos/`: `swift build`, `swift test`, `swift run Tidybyte`. Lint with
  `swiftlint lint --strict --baseline .swiftlint-baseline.json` — the baseline
  hides old violations, so don't add new ones. `Scripts/build-app.sh` and
  `Scripts/package-release.sh [direct|app-store]` build and sign releases.
- `website/`: `npm ci && npm run dev` (port 4321), `npm run build`, and
  `npm run check` (asset-hash, SEO, and OG-card verification) before pushing.

## Conventions

- Apple frameworks only; no third-party dependencies, network calls,
  analytics, or accounts in the apps.
- Strict concurrency everywhere — fix warnings, don't silence them. macOS
  targets are Swift 6: services are actors, state is `@Observable`.
- All user-facing strings go through the String Catalogs. iOS ships 21
  languages (including RTL); the Mac app's catalog is English-only in this
  release and CI has no Mac localization gate yet. On iOS,
  `Localizable.xcstrings` (app) and `AppShortcuts.xcstrings` (Siri phrases)
  are not interchangeable.
- Layout reads the window or view size, never the device — enforced on iOS by
  `npm run check:duo`.
- Squash merges; the PR title becomes the commit message.

## Links between folders

- `ios/scripts/growth/build-assets.mjs` reads the Fredoka fonts from
  `website/public/assets/fonts/`.
- `ios/Tidybyte/Scripts/GenerateAppIcon.swift --sync-site` writes the site icons
  to `website/public/assets/img/`. Run it from `ios/`.
- The Mac app's Sparkle feed is `https://tidybyte.360ghar.com/mac/appcast.xml`.
  The site serves it from `website/public/mac/appcast.xml`. Replace that file
  with the `appcast.xml` that `macos/Scripts/package-release.sh` writes for each
  release.
- Netlify builds the site from `website/`. The root `netlify.toml` sets
  `base = "website"`.

## CI

- `.github/workflows/ci.yml`: `build-and-test` (iOS) and `site` (website). Both
  are required checks on `main`, so they run on every pull request.
- `.github/workflows/growth.yml`: iOS App Store creatives, when their inputs
  change.
- `.github/workflows/macos.yml`: the Mac app, when `macos/` changes.
- CI diffs generated files and fails on drift: iOS localization catalogs must
  be byte-identical after `ios/scripts/localization/refresh.sh`, website
  localized pages and `site-strings.json` must match their sources, and growth
  manifests must match the rendered creatives.
- The `site` job also runs `ios`'s `npm run check:duo` on Linux, so a
  website-only PR can fail on iOS layout rules.
- `macos.yml` also builds the `tidybyte-mcp` server, runs
  `Scripts/mcp-e2e.py`, builds the `APP_STORE=1` variant, and fails if it
  links Sparkle.

## Releases

- iOS: tags `v*`, published through App Store Connect (`ios/scripts/publish/`).
- Mac: tags `mac-v*`, a notarized DMG on GitHub Releases plus the appcast above.
