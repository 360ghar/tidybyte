# iPhone Duo readiness

Internal source of truth for the iPhone Duo work. iPhone Duo (foldable iPhone)
ships **23 October 2026** with **iOS 27.1**; it has two displays and an app is
expected to render correctly on either one, at whatever size the window reports.

**The public copy is written from this document.** Store listings and site copy may
say the app is *built for* / *optimised for* iPhone Duo, because a build made with
the iOS 27.1 SDK is what delivers that. They must not say *tested on* or *verified
on* iPhone Duo, and must not claim the "optimized for iPhone Duo" badge. The
`verified` rows in the §4 ledger as of 2026-10-18 are **simulator-only** — no
physical Duo was used — so they do not license "tested on"/"verified on" copy. That
wording stays barred until a physical Duo run is recorded here.

Status vocabulary used below: `not yet verified` (no run recorded), `verified
<date>` (a run recorded per §3, with its output pasted into this file), `n/a`.

---

## 1. Device, pose and display matrix

| Pose | Active display | `simctl` display selector | Points (portrait) | App Store pixels (portrait) | Status |
|---|---|---|---|---|---|
| Folded (closed) | outer — **only** the outer display is active; the inner port is live but blank (walls) | port UUID matched by size 1398 × 2034 (fallback: `--display=1`, then `internal`) | 466 × 678 | 1398 × 2034 | verified 2026-10-18 (app render, §3 log) |
| Unfolded (flat), inner rotated to portrait | inner — the outer display goes black, so the two families can never be captured in one pose | port UUID matched by size 2007 × 2853 (fallback: `--display=3`, then `internal`) | 669 × 951 | 2007 × 2853 | verified 2026-10-18 (app render, §3 log) |
| Unfolded (flat), inner first comes up landscape | inner, letterboxed in a centred column | port UUID matched by size 2853 × 2007 | — | 2853 × 2007 | verified 2026-10-18 (portrait-only app letterboxes; §3 step 5a) |
| Tent | not documented | not documented | — | — | not yet verified |
| Laptop | not documented | not documented | — | — | not yet verified |

**Pose + orientation recipe, per family (verified 2026-10-18):**

- **Outer display:** boot the Duo **folded** (the `Closed` pose is the boot default). The
  outer display is active; the inner display is a live-but-empty surface whose
  screenshot is a blank wallpaper image. Capture with the 1398 × 2034 port
  (`--display=1`).
- **Inner display:** open the device (`Open` pose) — the app moves to the inner
  display and the outer goes black. The inner display first comes up **landscape**
  (2853 × 2007 px), where a portrait-only app letterboxes in a centred column.
  Click Device Hub's `Rotate Right` to put the inner display at its native
  **portrait 2007 × 2853 px** (669 × 951 pt), where the app fills the screen
  correctly. Capture with the 2007 × 2853 port (`--display=3`).

Notes:

- Both point sizes are exactly 3× the App Store pixel sizes (466 × 3 = 1398,
  678 × 3 = 2034, 669 × 3 = 2007, 951 × 3 = 2853), so a screenshot is the full
  @3x framebuffer with no scaling step.
- The point sizes and the two known poses are recorded in
  `TidybyteUITests/DuoLayoutUITests.swift:16-19`.
- The pixel sizes are Apple's accepted list for the Duo entry, recorded in
  `scripts/growth/shoot-screenshots.mjs:195-213` (outer) and `:214-233` (inner),
  with the `--duo` capture flag documented at `:42` and `--probe` at `:46`.
- **`simctl io <device> enumerate` does not print display names or screen ids.**
  Tested against a booted iPhone 18 Pro on this machine: each `Port:` block
  carries only `UUID`, `Class`, `Port Identifier`, `Power state`, `Display class`,
  `Default width`, `Default height`, `Default pixel format`. There is no
  `deviceName:` field and no `screenID:` field, so the earlier note here — that
  enumerate prints `primary` / `primary-1` and that those work as `--display`
  selectors — was wrong.
- What does work as `--display`, verified on that iPhone 18 Pro: the internal
  port's **UUID** (captures exactly 1206 × 2622), `--display=1`, and
  `--display=internal`. `--display=0` and `--display=3` fail — no such screen on
  that device. Note that a port's `Display class` does not line up with the
  numeric screen id (that device's only real screen is `Display class: 0` while
  its `Screen ID` is 1), which is why the numeric selector is a fallback and not
  the primary path.
- The capture script therefore resolves a Duo display by **matching the expected
  pixel size to an enumerated port and passing that port's UUID**
  (`resolveDisplayArg`, `scripts/growth/shoot-screenshots.mjs:477-498`). A rotated
  match (height × width) is accepted second; then the numeric `screenID` (1 outer,
  3 inner) and `internal`; and if ports parsed but none matches, the run **stops
  with a loud error** rather than screenshotting whatever screen the fallback id
  happens to be (`displayLookupFailure`, `:501-517`). The post-capture size check
  is exact for a Duo family, so a wrong display cannot land quietly.
- **Port UUIDs change on every boot (verified 2026-10-18).** After rebooting the
  Duo, `xcrun simctl io <udid> enumerate` returned *new* port UUIDs, and the old
  ones failed with `Invalid argument`. A resolver must therefore enumerate on every
  run and **never cache a UUID** across boots. The numeric screen ids are stable:
  `--display=1` is the outer display, `--display=3` is the inner display in its
  native portrait orientation, and `internal` is the inner display.
- `node scripts/growth/shoot-screenshots.mjs --probe <udid>` prints the parsed
  display ports and the resolved `--display=` selector per family, and touches
  nothing — no build, no boot, no create, no write (`probe()`, `:1369-1429`). Run it
  first on the Duo once the runtime is installed; it is the cheapest way to see
  which selector the capture will use.
- **Which display is lit in the tent and laptop poses is not documented in
  anything we have.** Apple's Duo material describes the poses but not which
  surface is active in each; the verification run records it (§3 step 5). Only
  the `Closed` and `Open` poses were exercised on 2026-10-18.
- `simctl` has no fold/pose/hinge subcommand (checked on Xcode 27.1, build
  27A9275: `xcrun simctl help` lists no such operation). **Poses are nonetheless
  drivable, and this was verified on 2026-10-18** — the earlier note here, that
  they can only be "driven by hand", is incomplete. Poses are driven only from
  Xcode's Device Hub app (`/Applications/Xcode.app/Contents/Applications/DeviceHub.app`,
  bundle id `com.apple.dt.Devices`); there is no AppleScript or CLI pose interface.
  Device Hub exposes AX-labelled buttons on the device chrome — `Home`,
  `Screenshot`, `Record`, `Rotate Right` — plus a poses group `Closed` /
  `Partially Open` / `Open`. These were reached and clicked through the installed
  `cua-driver` CLI, which drives Device Hub's accessibility tree. A statement that
  a display can be selected purely by `--display` without regard to pose is
  therefore **wrong**: the pose decides which port carries the app, and the inner
  display's orientation (landscape vs portrait) is decided by the `Rotate Right`
  button.
- **Known trap — do not power-cycle a Duo panel with `simctl`.** Running
  `xcrun simctl io screenConfig --display=<outer> power off` is **harmful**:
  after powering the panel back on, screenshots of it stayed fully black until the
  whole simulator was rebooted. Nothing in this repo should call
  `simctl io ... screenConfig power off` on a Duo.

---

## 2. What the code does today, per Apple requirement

Read-only inspection of the working tree. Nothing here is a claim that the
behaviour was observed on a Duo; the rows below describe what the code does, and
the verified status of the Duo run lives in §1 and the §4 ledger. (The Duo
simulator run of 2026-10-18 verified the two display sizes and the app rendering
on both, but not the code-level details in this table.)

| Apple requirement | What the code does today | Where |
|---|---|---|
| **Sizing** — render at whatever size the window reports | Grids are width-driven: one `.adaptive` `GridItem` per grid, so the column count follows the *available width* rather than the size class (the stated reason: a wide iPad pane can still report `.regular`) | `Tidybyte/Shared/Extensions/View+Responsive.swift:15-28`; call sites `Features/Cleanup/Screenshots/ScreenshotCleanerView.swift:17`, `Features/Cleanup/BlurryPhotos/BlurryPhotosView.swift:17`, `Features/Cleanup/SmartCategories/SmartCategoriesView.swift:60`, `Features/Cleanup/MediaCleanerView.swift:73`, `Features/Swipe/AlbumPickerSheet.swift:78`, `Shared/Components/SkeletonView.swift:147` |
| | Text and form content is capped at a readable measure and centred, so a wide window does not stretch it edge to edge | `View+Responsive.swift:47-53`; applied at `Features/Storage/StorageDashboardView.swift:69,148`, `Features/Swipe/SwipeHomeView.swift:150`, `Features/Swipe/SwipeCardDeck.swift:227` (560), `Features/Swipe/SessionCompletionView.swift:118`, `Features/Activity/ActivityView.swift:43`, `Features/Cleanup/LargeFiles/LargeFilesView.swift:54`, `Shared/Components/CleanupToolScaffold.swift:105,208`, `Shared/Components/ActionBarView.swift:25`, `Shared/Components/PhotoPermissionView.swift:78`, `Features/Onboarding/OnboardingView.swift:141,177` |
| | Accessibility text sizes collapse the tool grid to a single column | `Features/Cleanup/CleanupHomeView.swift:19` |
| | The swipe deck is sized from its container (`GeometryReader`), never from a device size | `Features/Swipe/SwipeCardDeck.swift:306`, `Features/Swipe/CardView.swift:152` |
| | **`Shared/Utilities/ScreenMetrics.swift` was deleted** (uncommitted deletion in the working tree), so there is no screen-metrics abstraction left to read. The swipe session's image target now comes from the deck's own geometry: `SwipeCardDeck` publishes `deckSize × displayScale` (`SwipeCardDeck.swift:196-203`, fed by `.onGeometryChange` at `:365-373` and `.onChange(of: displayScale)` at `:374-379`) → `SwipeSessionViewModel.updateRenderTarget` (`SwipeSessionViewModel.swift:568-571`, used for prefetch and cache release at `:607-636`) → `CardView.pixelTarget(for:)` (`CardView.swift:649-651`, consumed at `:434`, `:457` and `:610`). A fold, unfold or resize re-sizes the decode instead of leaving it pinned to a screen. `displayScale` is read from the environment (`CardView.swift:149`, `SwipeCardDeck.swift:194`), so it follows the window | grep for `UIScreen` across `Tidybyte/` returns nothing |
| | Fixed heights that exist are chart/row internals, not window layout: 140 pt trend chart, 180 × 180 donut | `Features/Activity/ActivityView.swift:166`, `Features/Storage/StorageDashboardView.swift:241` |
| **Orientation** — declare what each family supports | iPhone: portrait only. iPad: all four | `project.yml:82` (`INFOPLIST_KEY_UISupportedInterfaceOrientations: UIInterfaceOrientationPortrait`), `project.yml:83` (`..._iPad`: portrait, upside-down, landscape left, landscape right), rationale comment at `project.yml:80-81` |
| | iPhone Duo is an iPhone-family device, so it reads the portrait key, not the `~ipad` one. iPhone stays portrait-only by design (the swipe UX is portrait-centric) | same keys; `CLAUDE.md:15`, `AGENTS.md:15` |
| **Idiom** — stop branching on device | Device family is iPhone + iPad only | `project.yml:13` (base) and `:69`, `:134`, `:150`, `:168` (per target) |
| | `userInterfaceIdiom` no longer identifies the device, so layout keys off the window: `ResponsiveGrid` above, and `horizontalSizeClass` is read in exactly one place, to gate the iPad-only celebration layout | `TidybyteUITests/DuoLayoutUITests.swift:3-10` (the rationale); `Shared/Components/HappyPathCelebrationModifier.swift:16,55` |
| | On a wide window the tab bar becomes a sidebar (iOS 18+), so the four sections are reachable without a compact tab bar | `App/RootView.swift:320` (`adaptiveSidebarStyle()`, renamed from `sidebarAdaptableOnPad`), applied to the `TabView` at `App/RootView.swift:98` |
| **Reserved regions** — never draw under a cutout or a system surface | Safe areas are respected; nothing hardcodes a notch, a cutout or a display dimension. Insets are added where a bar is drawn: bottom notice, top tool bars | `App/RootView.swift:93` (bottom, `RecentlyDeletedNotice`), `Features/Swipe/SwipeSessionView.swift:181`, `Features/Swipe/SessionCompletionView.swift:166`, `Features/Swipe/AlbumPickerSheet.swift:121`, `Features/Cleanup/Screenshots/ScreenshotCleanerView.swift:162`, `Features/Cleanup/Bursts/BurstCleanerView.swift:114`, `Features/Cleanup/LargeFiles/LargeFilesView.swift:156`, `Features/Cleanup/PhotoCompression/PhotoCompressionView.swift:76`, `Features/Cleanup/VideoCompression/VideoCompressionView.swift:66`, `Features/Cleanup/LivePhotos/LivePhotosConverterView.swift:107` |
| | `ignoresSafeArea` appears only where content is meant to bleed: the full-screen media backdrops and the celebration overlay. The two content-level `.ignoresSafeArea(edges: .horizontal)` modifiers that used to sit on the preview content were **removed as part of this work**, so a side-edge system bar cannot overlap the media. The static guard encodes this intent: a bare `.ignoresSafeArea()` (no argument) is the deliberate full-bleed backdrop and is allowed; an argument list that names the horizontal axis — including `[.horizontal, .vertical]`, which also covers the horizontal edge — fails on a content view | `Shared/Components/MediaPreviewView.swift:111`, `Features/Cleanup/LivePhotos/LivePhotoPreviewView.swift:40`, `Shared/Components/HappyPathCelebrationModifier.swift:97` |
| **Bars** — a system bar can be presented vertically on a side edge in some poses | A tripwire test asserts no interactive control intrudes into the edge band, with a documented allowlist for system-placed controls | `TidybyteUITests/DuoLayoutUITests.swift:188` (test), `:21-25` (allowlist: `tabItem` and `toolbar`) |
| **Full screen** — do not letterbox | A valid `UILaunchScreen` dict is supplied by a seed plist, because the generated build setting emits an invalid nested dict; without it iOS letterboxes | `Tidybyte/Info.plist` (`UILaunchScreen`), rationale at `project.yml:72-76` |
| | No `UIRequiresFullScreen` anywhere | absent from `project.yml` and `Tidybyte/Info.plist` |
| **Assets** | The app icon is the single-size universal format on `platform: ios` slots — no idiom-specific slots to add for a new display | `CLAUDE.md` "App icon" bullet; `Tidybyte/Resources/Assets.xcassets` |

---

## 3. Verification on the Duo simulator — exact command sequence

Copy-pasteable, in order. Step 0 reflects the 2026-10-18 run (iOS 27.1 installed);
steps 1-7 are the recipe, and step 5a records the pose/orientation moves that the
run used. The run's actual results are in the Duo simulator verification log below.

```bash
# 0. What this machine has (observed with Xcode 27.1, build 27A9275)
xcrun simctl list devicetypes | grep -i duo   # iPhone Duo (...SimDeviceType.iPhone-Duo)
xcrun simctl runtime list                     # iOS 27.1 now installed and Ready (2026-10-18 run)

# 1. Get the iOS 27.1 runtime (iPhone Duo needs it)
xcodebuild -downloadPlatform iOS -buildVersion 27.1
#    or, if the image was fetched by hand:
xcrun simctl runtime add ~/Downloads/iOS_27.1_Simulator_Runtime.dmg
xcrun simctl runtime list                     # confirm iOS 27.1 is Ready before continuing

# 2. Create and boot the Duo simulator (one device, two displays)
UDID=$(xcrun simctl create "Tidybyte Duo (App Store)" \
  com.apple.CoreSimulator.SimDeviceType.iPhone-Duo \
  com.apple.CoreSimulator.SimRuntime.iOS-27-1)
xcrun simctl boot "$UDID"                     # boots FOLDED: outer display active, inner blank
# Xcode 27.1 does not ship Simulator.app — device management and pose
# visualization live in DeviceHub.app instead (verified: Simulator.app is absent
# from /Applications/Xcode.app/Contents/Applications).
open -a /Applications/Xcode.app/Contents/Applications/DeviceHub.app

# 3. Build for that simulator (succeeded on the Duo destination in the 2026-10-18 run)
xcodebuild -project Tidybyte.xcodeproj -scheme Tidybyte \
  -destination "platform=iOS Simulator,id=$UDID" \
  -derivedDataPath build/dd-duo build CODE_SIGNING_ALLOWED=NO

# 4. Install, grant photo access, add synthetic media, launch on the Swipe home
xcrun simctl install "$UDID" \
  build/dd-duo/Build/Products/Debug-iphonesimulator/Tidybyte.app
xcrun simctl privacy "$UDID" grant photos com.sakshammittal.tidybyte
xcrun simctl addmedia "$UDID" /tmp/duo-test/*.jpg        # synthetic test images
xcrun simctl launch "$UDID" com.sakshammittal.tidybyte -hasCompletedOnboarding YES

# 5. Screenshots, one per display. simctl writes RGBA; App Store Connect rejects
#    alpha, so strip it (the capture script below does that and checks the size).
#
#    enumerate does NOT print display names or screen ids — only UUID, Class,
#    Port Identifier, Power state, Display class, Default width/height, Default
#    pixel format per port block. So pick the port by its pixel size, not by name:
#    Port UUIDs CHANGE ON EVERY BOOT — re-enumerate each run, never cache a UUID.
xcrun simctl io "$UDID" enumerate                      # read the size of each port
xcrun simctl io "$UDID" screenshot --display=<port-uuid-for-1398x2034> /tmp/duo-outer.png
xcrun simctl io "$UDID" screenshot --display=<port-uuid-for-2007x2853> /tmp/duo-inner.png
#    Stable numeric fallbacks on a Duo: --display=1 (outer), --display=3 (inner,
#    native portrait), --display=internal (inner). On an ordinary iPhone the
#    working selectors are the internal port's UUID (exact size), --display=1 and
#    --display=internal; --display=0 fails there.
#    The script resolves this for you and stops loudly on a size mismatch.

# 5a. Pose + orientation, driven ONLY from Device Hub (no simctl verb). Clicked
#     through the installed cua-driver CLI against Device Hub's accessibility tree:
#       - Device chrome buttons: Home, Screenshot, Record, Rotate Right
#       - Poses group:           Closed / Partially Open / Open
#     Folded (Closed)  → outer display carries the app at 1398 × 2034 (--display=1).
#     Open             → app moves to the inner display (outer goes black). The
#                        inner display comes up LANDSCAPE (2853 × 2007), where a
#                        portrait-only app letterboxes in a centred column.
#     Rotate Right     → inner display to native PORTRAIT 2007 × 2853 (--display=3),
#                        where the app fills the screen.
#     DO NOT run `simctl io ... screenConfig --display=<n> power off`: after powering
#     back on, that panel screenshots fully black until the simulator is rebooted.

#    Or the whole flow — build, install, seed the language, pre-approve the
#    tidybyte:// scheme, resolve each display by size, capture both, strip alpha,
#    verify sizes. `--probe` first: it prints the ports and the resolved selector
#    per family and touches nothing.
node scripts/growth/shoot-screenshots.mjs --probe "$UDID"
node scripts/growth/shoot-screenshots.mjs --duo
#    Output: docs/screenshots/duo-outer/ and docs/screenshots/duo-inner/ (capture
#    stays per display; the upload collapses both into ONE App Store Connect row —
#    see §5 item 1)

# 6. Layout tests on the Duo simulator
xcodebuild -project Tidybyte.xcodeproj -scheme Tidybyte \
  -destination "platform=iOS Simulator,id=$UDID" \
  test -only-testing:TidybyteUITests/DuoLayoutUITests

# 7. Clean up
xcrun simctl shutdown "$UDID"
```

The capture script needs `xcodegen generate` to have been run since
`TidybyteUITests/DuoLayoutUITests.swift` was added (it is untracked in the working
tree today), and the runtime from step 1 must be installed before it starts — it
checks for 27.1 up front and refuses to build without it.

### Duo simulator verification log (2026-10-18)

**Simulator only.** These rows ran on a booted **iPhone Duo simulator on iOS
27.1**, on this machine. **No physical Duo hardware was used.** The photo library
was synthetic test images added with `xcrun simctl addmedia`; **photo-library
mutations were not exercised.** Rows here move §1 statuses to `verified
2026-10-18` and upgrade the §4 ledger rows whose precondition is "build + launch
on the Duo simulator".

| What | Command / method | Evidence | Result |
|---|---|---|---|
| Build for the Duo destination | `xcodebuild -project Tidybyte.xcodeproj -scheme Tidybyte -destination 'platform=iOS Simulator,id=<duo-udid>' -derivedDataPath build/dd-duo build CODE_SIGNING_ALLOWED=NO` | — | **BUILD SUCCEEDED** |
| Install + launch, device folded | `xcrun simctl install <udid> …/Tidybyte.app`; `xcrun simctl launch <udid> com.sakshammittal.tidybyte -hasCompletedOnboarding YES` with the Duo in the `Closed` pose | `/tmp/app-d1.png` (1398 × 2034 px) | App rendered correctly on the **outer display at 466 × 678 pt** — the swap screen with its filter list, nothing clipped, safe areas respected |
| Open + rotate to native portrait | Device Hub `Open` pose, then `Rotate Right` | `/tmp/inner-portrait-app.png` (2007 × 2853 px) | App rendered correctly on the **inner display at 669 × 951 pt**, filling the display, bottom tab bar visible, no letterboxing |
| Blank/inactive panel detection | Capture a panel and compare it against the known blank surface | `/tmp/blank-inner-inactive.png`-style artifacts | The inner panel, while inactive, screenshots as a **blank wallpaper image**. One observed md5 during this session was `56e2786878619e2d2c71a71b567d95d5` — that value is **session-specific**, so a check should use the *technique* (compare against the known blank surface) rather than hard-code the md5 |
| Pose + orientation mechanics | Device Hub via `cua-driver` | §1 recipe | The Duo boots **folded** (`Closed`): only the outer display is active, the inner is live but blank. `Open` moves the app to the inner display and blacks the outer. The inner display first comes up **landscape** (2853 × 2007), letterboxing a portrait-only app; `Rotate Right` gives native **portrait** (2007 × 2853). Portrait-orientation capture is `--display=3`; outer is `--display=1` |
| Port UUID instability | `xcrun simctl io <udid> enumerate` after a reboot | — | New UUIDs after reboot; the old ones failed with `Invalid argument`. A resolver must enumerate per run and never cache a UUID |
| All seven surfaces render on the outer display | `simctl status_bar override`, then `simctl openurl` per route, `simctl io screenshot --display=1` | `/tmp/duo-verify/01-swipe-home.png` … `07-activity.png` and the labelled sheet `/tmp/duo-verify/montage.png` | Every surface — Swipe, Cleanup, Duplicates, Screenshots, Blurry, Storage, Activity — drew at 466 × 678 pt with no clipping, and each capture had a **distinct md5**, which is what proves the deep links actually routed. Caveat recorded honestly: the capture taken after each `openurl` lagged the navigation, so in that ad-hoc run the file name does not always match the screen inside it. A capture pipeline must therefore assert that the screen changed and matches the expected surface before accepting the file |
| URL-scheme approval | `simctl openurl tidybyte://…` on iOS 27.1 | — | The first open raises SpringBoard's "Open in TidyByte?" confirmation. Pre-approving the scheme the way `shoot-screenshots.mjs` does **did not suppress it** in this run. The dialog's buttons are exposed to accessibility through Device Hub, so it can be accepted programmatically; until the pipeline handles it, a deep-linked capture is unreliable |

| Duo screenshot capture, both families | `node scripts/growth/shoot-screenshots.mjs --duo --only duoOuter --drive-devicehub` and the same for `duoInner` | `docs/screenshots/duo-outer/` (5 × 1398 × 2034) and `docs/screenshots/duo-inner/` (5 × 2007 × 2853) | Captured through Device Hub pose driving: the outer family folded, the inner family opened and rotated to native portrait. The orchestrator re-checked all ten files independently — every one has real content (distinct colour profiles, none blank) and each file matches the screen named by its filename |
| Duo layout tests on the Duo | `xcodebuild test … -destination 'platform=iOS Simulator,id=<duo-udid>' -only-testing:TidybyteUITests/DuoLayoutUITests` | — | `Executed 4 tests, with 0 failures in 127.9 s` on a booted Duo in the folded pose. The same suite also ran green on an iPad Pro 13-inch (M5) in 53.5 s. §5 item 6 records what the folded pose does and does not exercise |

**Explicitly NOT verified in this run — kept `not yet verified`:** anything under
`publish:*` that talks to the network, the App Store Connect store listing and its
single Duo group id, the StoreKit/upload path, the Screenshots and Blurry tool
screens on the inner display, and the tent and laptop poses.

### Local verification log

**This is not Duo verification.** Everything below ran on this machine against an
**iPhone 18 Pro simulator on the iOS 27.0 runtime**. It proves the build, the
tests and the tooling work; it is separate from the Duo run above.

| What | Command | Result |
|---|---|---|
| Build against the iOS 27.1 SDK | `xcodebuild -project Tidybyte.xcodeproj -scheme Tidybyte -destination 'platform=iOS Simulator,name=iPhone 18 Pro' build` | **BUILD SUCCEEDED** (Xcode 27.1, iOS 27.0 runtime). Re-confirmed independently by the orchestrator |
| Unit tests | same, `-only-testing:TidybyteTests` | **327 tests, 0 failures, TEST SUCCEEDED** (agent run and orchestrator run agree) |
| Static guard (repo) | `npm run check:duo` | `✓ resizability clean — 125 Swift file(s), 8 rules, 0 waiver(s)`, exit 0 (re-run for this pass; the guard was hardened to 8 rules — the 7 original rules plus `scene-screen` — with multi-line statement joining and same-file `UIScreen` typealias resolution) |
| Static guard (planted fixture) | `node scripts/duo/check-resizability.mjs --path /tmp/duo-fixture` | **Fails as intended.** `✗ 4 resizability violation(s)`, exit 1. The fixture's exact contents and the exact finding lines are recorded verbatim below, so the count is reproducible |
| Publish plumbing | `npm run publish:plan` | Unchanged at 371 placements / 14 files / 2 groups; with `--duo` it **fails loudly** until the group id exists |

**Explicitly not run in the local (18 Pro) pass:** any `publish:*` command that
talks to the network, and any store upload. The log above is §3 step 3 (the build)
plus the unit tests and the tooling checks, on the wrong device (an iPhone 18 Pro),
which is why it is labelled as not Duo verification. The Duo build, install, launch
and the `DuoLayoutUITests` pass are recorded separately in the Duo simulator
verification log above.

**Planted fixture for the static guard, recorded verbatim** so the `4 findings`
count is reproducible. The file is `/tmp/duo-fixture/Planted.swift`:

```swift
import SwiftUI
struct Planted: View {
    var body: some View {
        let w = UIScreen.main.bounds.width
        let idiom = UIDevice.current.userInterfaceIdiom
        let iphone = CGSize(width: 390, height: 844)
        Text("\(w)\(iphone)\(idiom)")
            .ignoresSafeArea(edges: .horizontal)
    }
}
```

`node scripts/duo/check-resizability.mjs --path /tmp/duo-fixture` printed:

```
✗ 4 resizability violation(s):
  /tmp/duo-fixture/Planted.swift:4: [screen-main] let w = UIScreen.main.bounds.width
  /tmp/duo-fixture/Planted.swift:5: [device-idiom] let idiom = UIDevice.current.userInterfaceIdiom
  /tmp/duo-fixture/Planted.swift:6: [hardcoded-screen-size] let iphone = CGSize(width: 390, height: 844)
  /tmp/duo-fixture/Planted.swift:8: [ignores-safe-area-horizontal] .ignoresSafeArea(edges: .horizontal)
```

and exited 1.

---

## 4. Claims ledger

Every public statement that depends on Duo work, the precondition that makes it
true, and where it appears. A claim moves off `unverified` only when the
precondition is demonstrated by a run recorded in §3.

| Claim | Precondition | Where the claim appears | Current status |
|---|---|---|---|
| "TidyByte runs on iPhone, iPad, and iPhone Duo — and stays out of your way while it cleans." | Build 8 compiles against the iOS 27.1 SDK and launches on the Duo simulator | `docs/appstore/listings.json` → `description`, all 21 locales (new paragraph after the opening paragraph) | In copy; **verified 2026-10-18 on the Duo simulator** — the 27.1 build succeeded for the Duo destination, and the app installed, launched and rendered on both displays (§3 Duo log). Simulator only; no physical Duo |
| App renders correctly on both Duo displays | Build 8 installed and launched on a booted Duo; outer captured folded, inner captured open at native portrait | New verification row for this document (§3 Duo log) | **verified 2026-10-18 on the Duo simulator** — outer 466 × 678 pt (`/tmp/app-d1.png`, 1398 × 2034 px, nothing clipped, safe areas respected); inner 669 × 951 pt (`/tmp/inner-portrait-app.png`, 2007 × 2853 px, tab bar visible, no letterboxing). Photo library was synthetic `simctl addmedia` images; **photo-library mutations not exercised** |
| "Now built for iPhone Duo: same cleanup, adapted to both displays." | Same, plus the swipe home and each cleanup tool render on both displays | `docs/appstore/listings.json` → `whatsNew` (21 locales); source `scripts/localization/translations/_notes-1.1.1.mjs` | Ships with 1.1.1. **Partially verified 2026-10-18** — outer display: all seven surfaces (Swipe, Cleanup, Duplicates, Screenshots, Blurry, Storage, Activity) rendered, each capture distinct, proving the deep links routed. Inner display: five surfaces captured (Swipe, Cleanup hub, Duplicates, Storage, Activity). Still unmet: the **Screenshots and Blurry tool screens** have not been rendered on the inner display, so "each cleanup tool on both displays" is not yet demonstrated. Simulator only; no physical Duo. The wording says "built for", not "tested on", which is what this ledger supports |
| Hero badge: "Free · iPhone & iPad · iPhone Duo · iOS 17+" | Same | `src/content/pages/index.html:24`, plus the 20 generated `src/content/pages/index.<lang>.html` | In copy; **verified 2026-10-18 on the Duo simulator** (same run as the row above; simulator only) |
| FAQ: "Does TidyByte work on iPhone Duo?" | Same; the answer claims the layout adapts to both displays | `src/content/pages/index.html` FAQ (+ 20 localized copies), `src/content/pages/support.html:130`, `src/data/tools.ts` (photo-cleaner hub FAQ), FAQPage JSON-LD in `src/data/pages.ts` | In copy; **verified 2026-10-18 on the Duo simulator** — the swipe home, the cleanup hub, Duplicates, Storage and Activity all rendered on both displays (outer at 466 × 678 pt, inner at 669 × 951 pt), and the full set of seven rendered on the outer display. Simulator only |
| Device lines: iPhone (portrait) + iPad + iPhone Duo | Same | `README.md:9`, `CLAUDE.md:15`, `AGENTS.md:15`, `docs/prd.md` §13, `docs/GEO-Playbook.md:17` | In copy; **verified 2026-10-18 on the Duo simulator** (simulator only) |
| "optimized for iPhone Duo" App Store badge | Duo screenshots captured at both required sizes **and** uploaded to the single Duo group in App Store Connect | Apple's product page, not ours | **Pending upload.** The screenshots exist (5 outer + 5 inner, verified 2026-10-18) and the group id is now known — `IPHONE_DUO_PROFILE`, resolved 2026-10-19 (§5 item 1) — but the upload has not run. It goes with the 1.1.1 submission: `npm run publish:media -- --duo --replace` |
| Duo screenshot row in the listing doc | `node scripts/growth/shoot-screenshots.mjs --duo` on the 27.1 runtime | `docs/APP_STORE_LISTING.md` §11 | Documented; **verified 2026-10-18** — the capture ran on the 27.1 runtime through Device Hub pose driving and produced `docs/screenshots/duo-outer/` (5 × 1398 × 2034) and `docs/screenshots/duo-inner/` (5 × 2007 × 2853), exactly the sizes Apple accepts. The orchestrator re-checked every file: real content (no blank panels), and each file matches the screen named by its filename |
| Build 8 carries the Duo readiness work | The bump itself is in source; the build/upload are not | `project.yml` (`CURRENT_PROJECT_VERSION: 8`, `MARKETING_VERSION: 1.1.1`) | Build for the Duo destination **verified 2026-10-18** (`CODE_SIGNING_ALLOWED=NO`). Build 8 is what 1.1.1 ships as; it was still free because 1.1.0 went out as build 7 |
| Duo layout tests exist | They compile and pass (they assert window geometry, not Duo-only behaviour) | `TidybyteUITests/DuoLayoutUITests.swift` | Written; **verified 2026-10-18 on the Duo itself** — 4 tests, 0 failures, re-run by the orchestrator on a booted Duo in the folded pose (`Executed 4 tests, with 0 failures in 127.9 s`), and separately on an iPad Pro 13-inch (M5) (53.5 s), which is where the edge-band assertion is live (`window.width >= 600`). §5 item 6 records the folded-pose caveat |

---

## 5. Open items

1. **Resolved 2026-10-19: the Duo group id is `IPHONE_DUO_PROFILE`.** Apple's
   published screenshot specification lists **one** "iPhone Duo" entry carrying all
   four accepted sizes (1398 × 2034 / 2034 × 1398 outer, 2007 × 2853 / 2853 × 2007
   inner) under a single heading, and the live catalog agrees: `publish:verify`
   prints exactly one `APP_SCREENSHOT` group for display class `IPHONE_DUO`, with
   `screenDimensions: ["2853x2007","2034x1398"]`. The blocker was the empty API key,
   which has since been filled, so the `appAssetLibraryRefData` dump now runs.
   `scripts/publish/plan.mjs` pins the id as `DUO_GROUP_ID` and still checks it
   against the catalog before uploading, so an Apple rename fails loudly rather than
   landing media on the wrong display. The single family reads **both** capture
   directories — `dirs: ['duo-outer', 'duo-inner']` — and is still gated by `--duo`.
   No environment variable is needed for the normal path.
2. **Two-group split exists only as an escape hatch, if the live catalog disagrees.**
   Setting **both** `TIDYBYTE_DUO_OUTER_GROUP_ID` and `TIDYBYTE_DUO_INNER_GROUP_ID`
   splits the model into two families, one directory each. Setting only one of the
   two now **throws** (`DUO_SPLIT_HELP`, `plan.mjs`): with the single-group id pinned
   as a default it would otherwise upload to the single group and silently ignore the
   id that was supplied, where before it fell back and failed for lack of any id.
   This remains a documented fallback for the case where `publish:verify` really does
   show two `APP_SCREENSHOT` groups for the Duo displays; the live catalog shows one,
   so one is the default.
3. **Hinge poses ARE drivable in the simulator (verified 2026-10-18) — tent and
   laptop remain unverified.** `simctl` still has no fold/pose/hinge subcommand
   (verified on Xcode 27.1), but poses are driven from Device Hub
   (`com.apple.dt.Devices`) through its accessibility tree, which the installed
   `cua-driver` CLI reached on 2026-10-18: the device chrome exposes `Home`,
   `Screenshot`, `Record`, `Rotate Right`, plus a poses group `Closed` /
   `Partially Open` / `Open`. Only `Closed` and `Open` were exercised, so the tent
   and laptop poses stay unverified — record them here once run rather than leaving
   §1 ambiguous. **Known trap:** `simctl io ... screenConfig --display=<n> power
   off` leaves the panel screenshotting fully black until the simulator is
   rebooted — do not call it.
4. **Screenshots become mandatory for iOS 27.1-SDK apps in April 2027.** Until
   then the Duo screenshot row is optional; from April 2027 an app built with the
   27.1 SDK must supply it. This is why the copy ships now and the capture can
   follow.
5. **The iOS 27.1 runtime IS now installed on this machine (2026-10-18)** and was
   used to boot the Duo for the run in §3. The earlier statement that only 27.0 was
   present is out of date.
6. **The Duo verification run has now happened** (§3 Duo log, 2026-10-18): the two
   display sizes, the app rendering on both displays, the screenshot capture and
   the `DuoLayoutUITests` pass are `verified`. What was not exercised — anything
   that talks to the network, i.e. publishing and the App Store Connect store
   listing with its Duo group id — stays `not yet verified`. Simulator only; no
   physical Duo. One honest caveat on the layout tests: in the folded pose the Duo
   window is 466 pt wide, below the test's `edgeBandApplicableMinimumWidth = 600`,
   so the edge-band assertion is **intentionally inert** there. It is live on the
   iPad Pro 13-inch (M5) run, and it has never been exercised on a Duo panel.
7. **Does the Duo's inner display have to support landscape?** The iPhone
   orientation key locks portrait on both displays (`project.yml:82`), and the
   2026-10-18 run confirms the inner display comes up **landscape** on open, where
   the portrait-only app letterboxes in a centred column until Device Hub's
   `Rotate Right` is clicked. Whether Apple treats a foldable's inner display as a
   resizable window that must accept more orientations is still not documented in
   the material we have; nothing in this repo decides it yet.
8. **The iOS 27.1 simulator runtime is Duo-only, by design (verified
   2026-10-18).** Its profile declares
   `restrictedToDeviceTypes = [com.apple.CoreSimulator.SimDeviceType.V68]`
   (`V68` is the Duo's product class), so `simctl create` refuses every ordinary
   iPhone and iPad device against it — `iPhone 16 Pro`, `iPhone 18 Pro`,
   `iPad Pro 13-inch (M5)` and `iPad mini (A17 Pro)` each fail with
   `An error was encountered processing the command (domain=com.apple.CoreSimulator.SimError, code=403): Incompatible device`.
   Consequence to plan around: **27.1 cannot replace 27.0 for everyday
   simulator work**, so both runtimes are kept installed (14.8 GB total). The
   27.0 runtime was briefly removed on 2026-10-18 to reclaim disk — which
   immediately marked every ordinary iPhone and iPad device
   `unavailable, runtime profile not found` — and was restored the same day with
   `xcodebuild -downloadPlatform iOS -buildVersion 27.0 -architectureVariant arm64`.
   Treat that pair as a set: drop 27.0 only if the Duo is the sole simulator
   work in flight, and expect to wait ~40 minutes and ~8 GB to get it back.
   A second thing to expect on the way back: those stranded devices return to
   `Shutdown` (not lost) as soon as the runtime is present again, so **do not
   recreate them** — recreating leaves duplicate devices with the same names.
