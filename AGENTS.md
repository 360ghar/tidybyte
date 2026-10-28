# AGENTS.md

This repository is a monorepo with three products. Each folder builds on its
own. Run a folder's commands from inside that folder.

| Folder | Product | Read first |
|---|---|---|
| `ios/` | iPhone and iPad app (Swift, SwiftUI, XcodeGen) | `ios/AGENTS.md` |
| `macos/` | Mac app (SwiftPM, Swift 6) | `macos/AGENTS.md` |
| `website/` | Marketing site (Astro, Tailwind) | `website/DEPLOY_CHECKLIST.md` |

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

## Releases

- iOS: tags `v*`, published through App Store Connect (`ios/scripts/publish/`).
- Mac: tags `mac-v*`, a notarized DMG on GitHub Releases plus the appcast above.
