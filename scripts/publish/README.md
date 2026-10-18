# Publishing to App Store Connect

Everything needed to put a build, its media, and its store copy into App Store
Connect, without the web UI.

## What you need first

An **App Store Connect API key**. Create one at:

> App Store Connect → Users and Access → Integrations → App Store Connect API

The key needs **Admin** or **App Manager** access, because it uploads media and
edits metadata. Download the `.p8` once — Apple lets you download it a single
time — and note the Key ID beside it and the Issuer ID above the list.

Then export three values. Nothing in this directory writes them anywhere, and no
code path logs the key or the token it signs.

```sh
export ASC_KEY_ID=XXXXXXXXXX
export ASC_ISSUER_ID=00000000-0000-0000-0000-000000000000
export ASC_KEY_PATH=~/Downloads/AuthKey_XXXXXXXXXX.p8
```

Add those to your shell profile if you publish regularly. Do not commit the
`.p8`; it is already covered by `.gitignore` (`*.p8`).

## The commands

Run them in this order. Everything takes `--dry-run`, which prints the calls it
would make and writes nothing.

```sh
npm run publish:selftest   # offline: verifies JWT signing and the plan
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
| `growth/header-and-search` header | `PRODUCT_PAGE_HEADER_ASSET` | `appStoreVersionLocalization` |
| `growth/header-and-search` search | search-results creative | `appStoreVersionLocalization` |
| `growth/in-app-events` card | `EVENT_CARD_ASSET` | `appEventLocalization` |
| `growth/in-app-events` details | `EVENT_DETAILS_ASSET` | `appEventLocalization` |
| `growth/custom-product-pages` | `APP_SCREENSHOT` | `appCustomProductPageLocalization` |
| `growth/product-page-optimization` | `APP_SCREENSHOT` | `appStoreVersionExperimentTreatmentLocalization` |

Placement groups are **never hard-coded**. They name a display target rather than
a device — Apple's required iPhone row is `IPHONE_DYNAMIC_ISLAND_*`, which Apple
scales for larger phones — and Apple adds new device families without an API
version change. `publish.mjs` reads them from `GET /v1/appAssetLibraryRefData`
and matches by prefix or by exact dimensions.

The one placement type not named in Apple's documentation is the search-results
creative. `plan.mjs` lists candidate names and the upload step resolves the first
one that exists in the live catalog; if none match it prints every name Apple
does expose and refuses to upload, rather than silently placing nothing.

## What is not automated

**Containers are not created.** In-app events, custom product pages, and product
page optimization experiments carry their own copy and review requirements.
`media` reports which ones are missing and skips their assets; it does not invent
them. Create them in App Store Connect, then re-run.

**Localizations are not created.** `details` reports any locale that has no App
Store localization rather than adding one.

**Screenshots are not localized.** The capture pipeline pins the app to English,
so the 14 screenshots are uploaded against `en-US` only and App Store Connect
falls back to them everywhere else. The growth creatives *are* localized, all 21.

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
  the manifests needs to stay inside them too.
- **An asset with placements cannot be deleted** — `STATE_ERROR.ASSET_HAS_PLACEMENTS`.
