# Contributing to TidyByte

Thank you for your interest in TidyByte. This guide tells you how to set up the
project, which checks your change must pass, and how to send a pull request.

By taking part, you agree to follow the [Code of Conduct](CODE_OF_CONDUCT.md).
To report a security problem, do not open an issue. Follow
[SECURITY.md](SECURITY.md).

## Repository layout

| Folder | Product |
|---|---|
| `ios/` | iPhone and iPad app |
| `macos/` | Mac app |
| `website/` | Marketing site |

Run each command in this guide from the folder it names.

## Find something to work on

- Issues labeled [`good first issue`](https://github.com/360ghar/tidybyte/labels/good%20first%20issue)
  are small and well scoped.
- Issues labeled [`help wanted`](https://github.com/360ghar/tidybyte/labels/help%20wanted)
  are larger.
- For questions and ideas, use
  [Discussions](https://github.com/360ghar/tidybyte/discussions).
- Before you start a large change, open an issue or a discussion first. Then we
  can agree on the approach before you write the code.

## Set up the project

You need:

- macOS with Xcode 26 or later
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`, for the iOS app
- Node.js 22, for the website and the iOS localization and asset scripts
- macOS 26 on Apple silicon, for the Mac app

```bash
git clone https://github.com/360ghar/tidybyte.git
cd tidybyte
```

The iOS `.xcodeproj` is generated from `ios/project.yml` and is not in Git.
Generate it after you clone, and again after you change `project.yml`:

```bash
cd ios
xcodegen generate
npm ci
```

For the website, run `npm ci` in `website/`. The Mac app needs no setup step.

## Build and test

### iOS app (from `ios/`)

Use any installed iPhone simulator. The commands below use `iPhone 17 Pro`;
replace it with a simulator from `xcrun simctl list devices available`.

```bash
xcodebuild build -project Tidybyte.xcodeproj -scheme Tidybyte \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' CODE_SIGNING_ALLOWED=NO

xcodebuild test -project Tidybyte.xcodeproj -scheme Tidybyte \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' CODE_SIGNING_ALLOWED=NO
```

The simulator has a small sample photo library. Work that reads or changes
photos (PhotoKit, iCloud originals, large libraries) needs a physical device.

### Mac app (from `macos/`)

```bash
swift build
swift test
swiftlint lint --strict --baseline .swiftlint-baseline.json
Scripts/build-app.sh direct    # writes .build/Tidybyte.app
```

Destructive tests use fixture folders only. See `macos/README.md` and
`macos/AGENTS.md`.

### Website (from `website/`)

```bash
npm run dev                      # http://localhost:4321
npm run build && npm run check   # what CI runs
```

### Run on your own iPhone

`ios/project.yml` uses the maintainer's signing team, bundle identifiers, and App
Group. To run on your device, change these values locally and do not commit
them:

- `DEVELOPMENT_TEAM` in `project.yml`
- `PRODUCT_BUNDLE_IDENTIFIER` for the app and the widget in `project.yml`
- The App Group `group.com.sakshammittal.tidybyte.shared` in `project.yml`,
  both `.entitlements` files, and `Tidybyte/Shared/Widget/AppGroupStore.swift`

## Checks that CI runs

Every pull request runs the iOS and website checks below. The Mac checks run
when `macos/` changes. Run the ones that apply to your change before you push.
Run each command from the folder in the first column.

| Folder | Check | Command | Run it when you change |
|---|---|---|---|
| `ios/` | Build and unit tests | see [Build and test](#build-and-test) | Swift code |
| `ios/` | String Catalogs are current | `./scripts/localization/refresh.sh`, then `git diff` must show no change to the `.xcstrings` files | user-facing text |
| `ios/` | No unlocalized text | `node scripts/localization/extract.mjs --check` | user-facing text |
| `ios/` | Every key is translated | `node scripts/localization/check.mjs --strict` | user-facing text |
| `ios/` | App Store listing limits | `node scripts/localization/check-listings.mjs --strict` | `docs/appstore/listings.json` |
| `ios/` | No fixed-size layout | `npm run check:duo` | layout code |
| `ios/` | App Store creatives render (separate workflow, runs only when its inputs change) | `npx playwright install chromium`, then `npm run growth && npm run check:growth` | `docs/growth/`, `scripts/growth/`, the String Catalogs, `docs/appstore/listings.json` |
| `website/` | Site builds and passes the audit | `npm run build && npm run check` | `src/`, `public/` |
| `website/` | Localized home pages are current | `node scripts/localization/site/extract-site-strings.mjs && node scripts/localization/site/build-site-translations.mjs`, then `git diff` must show no change | `src/content/pages/index.html` |
| `macos/` | Lint, build, test, MCP end-to-end, app bundle | see [Mac app](#mac-app-from-macos) | Mac code |

`refresh.sh` uses the simulator in the `DESTINATION` environment variable, for
example `DESTINATION='platform=iOS Simulator,name=iPhone 17 Pro'`.

## Code rules

These rules keep the iOS app small, private, and consistent.
`ios/AGENTS.md` has more detail on the architecture. The Mac app has its own
rules in `macos/AGENTS.md`: for example, it uses Sparkle for updates, and an AI
provider is optional and off by default.

- **Apple frameworks only.** Do not add a third-party dependency.
- **All processing stays on the device.** Do not add network calls, analytics,
  or accounts.
- **Services are actors.** Do not use locks or dispatch queues in new service
  code.
- **View models use `@Observable`**, not `ObservableObject`.
- **Strict concurrency is on.** Values that cross an actor boundary must be
  `Sendable`. Fix warnings; do not silence them.
- **All user-facing text goes through a String Catalog.** The app ships in 21
  languages, including Arabic and Hebrew (right to left). Text that does not
  reach the catalog shows in English in every language. See
  [`ios/scripts/localization/README.md`](ios/scripts/localization/README.md).
- **Layout reads the window, not the device.** The app runs on iPhone, iPad,
  and iPhone Duo, and the window can change size at any time. Do not read the
  screen size or the device idiom for layout.

## Send a pull request

1. Fork the repository and create a branch from `main`.
2. Make one change per pull request. Small pull requests get reviewed sooner.
3. Add or update tests for logic changes.
4. In the description, explain:
   - **Why:** the problem, and how to see it.
   - **What changes:** the approach, in a few points.
   - **Tests:** what you ran and on which device or simulator. Give numbers
     for performance work.
   - **Screenshots:** before and after, for UI changes.
5. Make sure CI passes.

Pull requests are merged with squash merge, so the pull request title becomes
the commit message. Write it as a short sentence that says what the change does,
for example "Keep library scans from blocking card images".

Pull requests #6 to #10 are good examples of the format.

## Report a bug

Use the [bug report form](https://github.com/360ghar/tidybyte/issues/new/choose).
Give the app version (Settings in the app), the iOS or macOS version, the device,
and the steps to see the problem.

## License

By contributing, you agree that your contribution is licensed under the
[MIT License](LICENSE).
