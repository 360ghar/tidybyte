# Publishing to App Store Connect

Everything needed to put a build, its media, and its store copy into App Store
Connect, without the web UI.

## What you need first

An **App Store Connect API key**. It can only be created from your account —
there is no API for creating API keys, so this is the one step that cannot be
automated.

### 1. Create the key

**Team key** (needs an Admin account, works for any app on the team):

> App Store Connect → **Users and Access** → **Integrations** tab →
> **App Store Connect API** → **Team Keys** → **+** → name it, pick a role → **Generate**

**Individual key** (works with any account; access follows your own role):

> App Store Connect → click your **profile** (top right) → scroll to
> **Individual API Key** → **Generate API Key**

Use a **Team key with the App Manager role** if you can. App Manager covers
everything the pipeline does — upload builds, edit App Store details, create
in-app events, submit apps — without the user-management power that Admin adds.
Individual keys cannot use the provisioning, sales-and-finance, or `notaryTool`
endpoints; this pipeline needs none of those, so an individual key is a fine
fallback.

### 2. Download the private key — once

The download link appears only until you click it. **Apple keeps no copy**, so if
the `.p8` is lost the key must be revoked and replaced. Move it somewhere outside
the repo, for example:

```sh
mkdir -p ~/.appstoreconnect/private_keys
mv ~/Downloads/AuthKey_XXXXXXXXXX.p8 ~/.appstoreconnect/private_keys/
```

### 3. Give the pipeline the three values

Three values are needed: the **Key ID** (beside the key in the list), the
**Issuer ID** (above the list, shared by all team keys), and the **path** to the
`.p8`.

Put them in a `.env` at the repo root. This file is gitignored, and `.p8` files
are gitignored too, so neither can be committed:

```sh
cat > .env <<'EOF'
ASC_KEY_ID=XXXXXXXXXX
ASC_ISSUER_ID=00000000-0000-0000-0000-000000000000
ASC_KEY_PATH=/Users/you/.appstoreconnect/private_keys/AuthKey_XXXXXXXXXX.p8
EOF
```

A `.env` file is the recommended route rather than `export`, because **each
command here runs in a fresh shell** — a variable exported in one terminal does
not reach the next command. `asc.mjs` reads `.env` automatically. Real
environment variables still win over the file, so a one-off override works:

```sh
ASC_KEY_ID=OTHERKEYID npm run publish:verify
```

### 4. Check it before using it

```sh
npm run publish:doctor           # validates the values and parses the key, offline
npm run publish:doctor -- --live # adds one real call to confirm Apple accepts it
```

`doctor` distinguishes the three failures that otherwise look alike: no
credentials at all, credentials that do not parse, and credentials Apple
rejects. It never prints a secret — the Key ID and Issuer ID are masked.

### If you would rather not hand over a key

Two options, both fine:

- **Scope it down.** A Team key with the **Marketing** or **Developer** role can
  read but not publish, which is enough to run `publish:verify` and see exactly
  what the pipeline would do.
- **Drive it yourself.** Everything here is a normal command. Run `publish:verify`,
  then `publish:build`, and so on, and nothing is shared.

Revoke the key when you are done: **Users and Access → Integrations → App Store
Connect API →** select the key **→ Revoke**. Revocation is immediate, and a
revoked key cannot be un-revoked.

## The commands

Run them in this order. Everything takes `--dry-run`, which prints the calls it
would make and writes nothing.

```sh
npm run publish:selftest   # offline: verifies JWT signing and the plan
npm run publish:doctor     # offline: validates credentials
npm run publish:verify     # read-only: reports the live account state

npm run archive            # builds and exports the signed IPA
npm run publish:build      # uploads the IPA
npm run publish:details    # pushes subtitle, keywords, description, what's new
npm run publish:media      # uploads assets and creates placements
npm run publish:submit     # submits the version for review
```

`node scripts/publish/publish.mjs plan` prints the media plan offline, with no
credentials and no network.

## What each step actually does

**`selftest`** runs offline. It signs a JWT with a throwaway key and checks the
signature is raw `R||S` rather than DER — Node defaults to DER for ECDSA, and a
DER signature is still a *valid* signature, so the only symptom of getting this
wrong is a 401 from Apple that never mentions encoding. It also checks that every
file in the plan exists, that every language maps to a real storefront locale,
and that no placement type is hard-coded.

**`verify`** is read-only and always runs first. It reports the app record, which
version is editable, every localization and its field lengths, what media each
localization currently holds, existing events and custom product pages, and the
full asset-library reference data. Run this before trusting anything else.

**`archive`** regenerates the Xcode project and builds a Release archive, then
exports a distribution IPA to `build/archive/export/Tidybyte.ipa`.

**`build`** uploads that IPA with `xcrun altool`, authenticated by the same API
key. The REST API can read build metadata but cannot create a build, so the
binary goes through altool.

**`details`** writes the store copy from `docs/appstore/listings.json` into every
`appStoreVersionLocalization`, and the subtitle into the matching
`appInfoLocalization`. It compares before writing, so a re-run is a no-op rather
than a rewrite.

**`media`** uploads each distinct file to the app's asset library once, then
creates a placement per surface. Files are deduplicated by **content hash**, not
by path: 42 of the creatives here are the same bytes on two surfaces, so the
library stores them once. Assets are named by their hash, which makes a re-run
resume instead of duplicating.

**`submit`** creates a review submission, adds the version, and submits it.

## How media maps onto Apple's model

Apple's set-based media APIs (`appScreenshotSets`, `appEventScreenshots`, and the
rest) are **deprecated**. The supported path is the **App Asset Library**:
upload a file once into a per-app library, then create *placements* that position
it on surfaces. `plan.mjs` describes the second half.

| Local surface | Placement type | Target |
|---|---|---|
| `docs/screenshots/{iphone,ipad}` | `APP_SCREENSHOT` | `appStoreVersionLocalization` |
| `docs/screenshots/duo-outer`, `duo-inner` (`--duo` only) | `APP_SCREENSHOT` | `appStoreVersionLocalization` |
| `growth/header-and-search` header | `PRODUCT_PAGE_HEADER_ASSET` | `appStoreVersionLocalization` |
| `growth/header-and-search` search | search-results creative | `appStoreVersionLocalization` |
| `growth/in-app-events` card | `EVENT_CARD_ASSET` | `appEventLocalization` |
| `growth/in-app-events` details | `EVENT_DETAILS_ASSET` | `appEventLocalization` |
| `growth/custom-product-pages` | search-results creative | `appCustomProductPageLocalization` |
| `growth/product-page-optimization` | search-results creative | `appStoreVersionExperimentTreatmentLocalization` |

Both of those surfaces render the 3:2 search-results creative, not a screenshot,
so `plan.mjs` sends `APP_STORE_SEARCH_RESULTS_ASSET` with category
`CREATIVE_ASSETS`. Sending them as `APP_SCREENSHOT` fails: screenshots are
validated against device dimensions and 2400x1600 is not one of them.

Placement groups are **never hard-coded**. They name a display target rather than
a device — Apple's required iPhone row is `IPHONE_DYNAMIC_ISLAND_*`, which Apple
scales for larger phones — and Apple adds new device families without an API
version change. `publish.mjs` reads them from `GET /v1/appAssetLibraryRefData`
and matches by prefix or by exact dimensions.

The one placement type not named in Apple's documentation is the search-results
creative. `plan.mjs` lists candidate names and the upload step resolves the first
one that exists in the live catalog; if none match it prints every name Apple
does expose and refuses to upload, rather than silently placing nothing.

## What the API covers, and what it does not

Reachable through the API, and handled here:

| Listing field | Where it lives | Command |
|---|---|---|
| Subtitle | `appInfoLocalization` | `details` |
| Description, keywords, promotional text, what's new | `appStoreVersionLocalization` | `details` |
| Screenshots | asset library placements | `media` |
| Product page header, search creative | asset library placements | `media` |
| In-app event cards and details | asset library placements | `media` |
| Custom product page screenshots | asset library placements | `media` |
| PPO experiment screenshots | asset library placements | `media` |
| Age rating declaration | `ageRatingDeclaration` | *not yet wired* |
| Availability and pricing | `appAvailability`, `appPriceSchedules` | *not yet wired* |
| Review submission | `reviewSubmissions` | `submit` |

**Not reachable through the API at all**, so these stay in the web UI:

- **App Privacy details** (the "nutrition label"). No API. fastlane's action for
  this still drives the old iTunes Portal and needs 2FA. Answer it by hand at
  **App Store Connect → your app → App Privacy**; the answers for TidyByte are
  already written out in `docs/APP_STORE_LISTING.md` §8.
- **Agreements, tax, and banking.** Account Holder only, web UI only.
- **App Review contact details and attachments**, if a human reviewer needs to
  reach you.

**Containers are not created.** In-app events, custom product pages, and product
page optimization experiments carry their own copy and review requirements.
`media` reports which ones are missing and skips their assets; it does not invent
them. Create them in App Store Connect, then re-run.

**Localizations are not created.** `details` reports any locale that has no App
Store localization rather than adding one.

**Screenshots are not localized.** The capture pipeline pins the app to English,
so the 14 screenshots are uploaded against `en-US` only and App Store Connect
falls back to them everywhere else. The growth creatives *are* localized, all 21.

## iPhone Duo screenshots

iPhone Duo (the foldable) is one device with two displays. Capturing is opt-in
and off by default, because **the group id for the Duo row is not known yet**.

```sh
npm run screenshots:duo                        # capture both Duo displays (5 screens each)
npm run screenshots:duo -- --dry-run           # print the plan, touch nothing
npm run screenshots:duo -- --screens swipe-home,storage-dashboard   # capture a different subset
npm run screenshots:duo -- --drive-devicehub   # set the Duo pose in Device Hub for you
npm run publish:media -- --duo                 # place them (needs the group id)
```

`npm run screenshots` is unchanged: it captures iPhone and iPad only, and
`npm run publish:media` with no `--duo` produces exactly the placements it did
before the Duo row existed.

### The per-row cap: 10 screenshots

App Store Connect allows **at most 10 screenshots per placement group**, and a
group is one device-size row on the product page. A Duo submission is graded as
**one** row, so `duo-outer/` and `duo-inner/` together may hold at most 10 files.

The capture default is therefore **5 screens per display — 5 + 5 = 10**, exactly
the cap:

| # | screen |
|---|---|
| 1 | `swipe-home` |
| 2 | `cleanup-tools` |
| 3 | `cleanup-duplicates` |
| 4 | `storage-dashboard` |
| 5 | `activity-savings` |

`cleanup-screenshots` and `cleanup-blurry-photos` are dropped **for Duo only** —
they repeat the cleanup-tools story the duplicates screen already tells. The
iPhone and iPad runs still capture all seven, because their rows have their own
caps.

To capture a different subset, pass `--screens` with a comma-separated list of
the slugs above (plus `cleanup-screenshots` and `cleanup-blurry-photos`, which
are still valid names):

```sh
npm run screenshots:duo -- --screens swipe-home,cleanup-tools,cleanup-duplicates
```

`--screens` applies to every requested family, and an unknown slug stops the run
rather than capturing less than asked.

`loadPlan` re-checks the count against the real files on disk before any network
call: more than 10 in a Duo group throws with the count, the cap, and this same
advice, instead of uploading 10 and dropping the rest. `scripts/publish/plan.mjs`
names the limit in one constant, `MAX_SCREENSHOTS_PER_GROUP`.

### One row, two displays

Apple's screenshot specification lists a **single** "iPhone Duo" entry carrying
all four accepted sizes — 1398×2034 / 2034×1398 (outer display) and 2007×2853 /
2853×2007 (inner display) — with no per-display requirement note, and the Duo
badge is described as one badge on the product page. So the upload model is **one
group**, fed by both capture directories:

| Family | Directories | Group source |
|---|---|---|
| `duo` (default) | `docs/screenshots/duo-outer/` + `docs/screenshots/duo-inner/` | `TIDYBYTE_DUO_GROUP_ID` |
| `duoOuter` / `duoInner` (escape hatch) | one directory each | `TIDYBYTE_DUO_OUTER_GROUP_ID` + `TIDYBYTE_DUO_INNER_GROUP_ID` |

Capture stays per display — a display is a capture concern. Only the upload
collapses.

The escape-hatch split exists for the case Apple's UI actually exposes **two
separate rows** instead of one. Each split family then gets its **own** 10-file
cap, so up to 7 per display is fine there — but the split is chosen only after
`publish:verify` shows two Duo groups, never guessed.

### What is still unknown

**The group id.** Apple names placement groups after the display. The iPhone row
is `IPHONE_DYNAMIC_ISLAND_MEDIUM_PROFILE`, the iPad row `IPAD_13_PROFILE`, and
the Duo row has a name this repo has never seen. The API key here is empty, so
`publish:verify` has never dumped a catalog that contains it. A guessed id would
either fail the upload or — worse — collide with an existing group, so it is not
guessed.

Apple's published spec says one row, so one group is the working assumption. If
the live catalog turns out to disagree, `publish:verify` is what settles it — it
prints every `APP_SCREENSHOT` group it exposes.

### Resolving it

```sh
npm run publish:verify
```

Find the `appAssetLibraryRefData` section of the dump. It lists every placement
group as `<group-id>  <platform>  <display-class>`. Take the `APP_SCREENSHOT`
group for the Duo display and export it for one run:

```sh
TIDYBYTE_DUO_GROUP_ID=<id> npm run publish:media -- --duo
```

or paste it into `duoFamilies()` in `plan.mjs`, which makes `--duo` permanent.
Until one of those is done, `--duo` fails loudly rather than uploading to the
wrong display.

**If the dump shows two Duo groups** (the unlikely case — the published spec says
one row), use the split instead: set **both** of

```sh
TIDYBYTE_DUO_OUTER_GROUP_ID=<outer-id> TIDYBYTE_DUO_INNER_GROUP_ID=<inner-id> \
  npm run publish:media -- --duo
```

and the plan becomes two families, one directory each. Setting only one of the
two is not a split: it falls back to the single-group model, which has no id, and
fails loudly. A half-split cannot happen by accident.

### Capturing them

`npm run screenshots:duo` needs the **iOS 27.1 runtime** and the **iPhone Duo
device type**. It checks for both before it builds anything, and if either is
missing it prints the two commands that fix it and exits non-zero, having created
no simulator and written no file:

```sh
xcodebuild -downloadPlatform iOS -buildVersion 27.1
xcrun simctl create "Tidybyte Duo (App Store)" \
  com.apple.CoreSimulator.SimDeviceType.iPhone-Duo \
  com.apple.CoreSimulator.SimRuntime.iOS-27-1
```

It also needs the device in the right **pose**, because the two panels are never
both showing the app — a Duo boots folded, and in the `Closed` pose only the
**outer** panel is active while the **inner** one is a blank surface; in the
`Open` pose the app moves to the inner panel and the outer one goes black:

| Family | Pose | Orientation |
|---|---|---|
| `duoOuter` | `Closed` | portrait, 1398×2034 |
| `duoInner` | `Open` | native portrait, 2007×2853 |

`simctl` has no hinge or pose verb and Device Hub has no CLI, so a pose cannot be
set from the shell. The script probes both panels, infers the pose from which one
has content, and if it is wrong it **stops** with the Device Hub steps that fix it
rather than capturing a blank panel:

```sh
npm run screenshots:duo                       # verify the pose, stop if it is wrong
npm run screenshots:duo -- --drive-devicehub  # click Closed / Open / Rotate Right for you
```

`--drive-devicehub` uses the `cua-driver` Accessibility CLI to find Device Hub's
window for the device, press the pose button **by AX label** in a fresh snapshot,
and then re-verify through `simctl io enumerate` plus a fresh pixel probe. The
inner panel comes up **landscape** (2853×2007) in the `Open` pose, which would
letterbox a portrait-only app, so `Rotate Right` is pressed and checked too.

Every capture then passes a **blank-panel gate**: a near-uniform PNG (all-black,
all-white, or effectively flat) is rejected with the likely cause named — wrong
pose, panel asleep, or the app not frontmost. That is the check a size-only test
misses, because the black outer panel an `Open` pose produces is a perfectly valid
1398×2034 file.

One Duo simulator serves both displays. `simctl io <udid> enumerate` does **not**
report `deviceName` or `screenID` — the fields it does report per display port are
`UUID`, `Class`, `Display class`, `Default width`, `Default height` and
`Default pixel format`. So the capture script picks the display by **pixel size**:
the port whose `Default width`/`Default height` equal the family's expected size
wins, and its UUID is passed as `--display=<uuid>`. A size match is required,
because a numeric selector cannot be validated before the capture and the
enumerated ports include 720x480 and 7680x4320 decoys alongside the real screen.
Port UUIDs change on every boot, so they are never cached; the documented fallback,
used only when the dump yields no parsable display ports, is the numeric screen id
(`--display=1` outer, `--display=3` inner).

To audit that against any booted simulator without capturing anything:

```sh
node scripts/growth/shoot-screenshots.mjs --probe <udid>
```

It prints the parsed display table, the inferred pose and the selector each family
would choose. On a non-Duo device the Duo families report that nothing matched,
which is correct — that device cannot produce Duo screenshots.

Files land in `docs/screenshots/duo-outer/` and `docs/screenshots/duo-inner/`,
which feed the one Duo group described above. By default that is five files each
(positions 1-5 outer, 101-105 inner), so the pair cannot collide in the gallery
order — which is why `publish.mjs` resolves a placement's position by the asset's
content hash rather than by its file name.

To check how the app behaves across the foldable's poses and orientations rather
than to capture screenshots, use **Device Hub** in Xcode — it visualizes the app
on iPhone Duo across every pose and orientation, and it is where the pose buttons
above live.

Both Duo directories may be absent, but `--duo` needs at least one PNG across the
two: with neither, the plan throws and names `npm run screenshots:duo` rather
than reporting a successful upload of nothing.

## Constraints worth knowing

- **Placements only work while the parent is editable.** The version must be in
  `PREPARE_FOR_SUBMISSION`. `verify` says so if it is not.
- **A placement cannot be modified.** To change artwork, delete the placement
  and create a new one. `media` therefore creates placements; it does not update
  them. Re-running against a surface that already has placements will add
  duplicates — check `verify` first.
- **Asset category is fixed at reservation.** Screenshots and previews are
  `APP_SCREENSHOTS_AND_PREVIEWS`; headers, event cards and other creatives are
  `CREATIVE_ASSETS`. An asset reserved under the wrong category cannot be placed
  where you intended.
- **Group limits apply.** App Store versions allow 10 screenshots, 3 previews and
  1 product page header per group. The plan is inside those limits; a change to
  the manifests needs to stay inside them too. `loadPlan` enforces the 10-screenshot
  cap for a Duo group itself, from the files on disk, before any network call.
- **An asset with placements cannot be deleted** — `STATE_ERROR.ASSET_HAS_PLACEMENTS`.
