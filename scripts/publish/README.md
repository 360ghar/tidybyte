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
