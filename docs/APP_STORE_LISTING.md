# App Store Connect Listing — TidyByte

> **HISTORICAL (2026-08):** the shipped version is **1.0.5 (build 6)**. This
> document preserves the original v1.0 listing copy; the site's `/changelog` is
> now the canonical version history. §4 (Keywords) and §1 (Subtitle) were
> refreshed on 2026-10-18 for the storage-cleaner and image-compressor
> positioning — see the notes under each table.

Paste-ready copy for App Store Connect. Char-count annotations are inline. Anything marked **TODO** needs a human decision before submission.

> **Bundle ID (confirmed):** The app ships as **`com.sakshammittal.tidybyte`** (widget: `com.sakshammittal.tidybyte.widget`, tests: `com.sakshammittal.tidybyte.tests`). This matches `AppGroupStore.swift`'s App Group (`group.com.sakshammittal.tidybyte.shared`), both `.entitlements` files, and `project.yml`. Use `com.sakshammittal.tidybyte` when creating the App Store Connect app record, registered to Team **HMWGCVU4SV**.

---

## 1. App Name & Subtitle

**App Name** (max 30 chars):

```
TidyByte
```
`TidyByte` = 8 chars. ✅

**Subtitle options** (max 30 chars each — pick one):

| Option | Text | Chars | Notes |
|---|---|---|---|
| **I** | `Clean photos, free up storage` | 29 ✅ | **In use.** Verb-forward; carries both the cleaning action and the storage outcome. |
| H | `Photo cleaner, free space` | 25 ✅ | Shortest phrase carrying both intents, but noun-form and weaker on storage. |
| A | `Swipe to clean your photos` | 26 ✅ | Strong on the swipe hook, weak on storage intent. |
| B | `Declutter photos, free space` | 28 ✅ | Balanced. |
| C | `Photo cleaner & storage saver` | 29 ✅ | Names both the cleaner and the storage outcome. |
| E | `Storage cleaner, photo cleaner` | 30 ✅ | At the limit. Leads with the storage problem. |
| D | `Storage cleaner & photo cleaner` | 31 ❌ | Too long by one character. |
| F | `Clean storage & compress images` | 31 ❌ | Too long by one character. |
| G | `Free storage cleaner & compressor` | 33 ❌ | Too long — listed to show the ceiling. |

Character counts above are measured, not estimated: `[...text].length` in JavaScript.
An earlier revision of this table listed E as 31 characters and marked it too long;
it is 30 and fits. D and F were each overstated by one character. The counts are
what App Store Connect enforces, so they are worth re-measuring after any edit.

**Decided:** option I, `Clean photos, free up storage`, ships. It is set in
`docs/appstore/listings.json` for all 21 locales. H was the earlier working
default; the localized values were rewritten for I and are machine-drafted —
they carry the previous per-language phrasing forward with the verb-forward
shift, but have not had a native review pass.

Neither option fits the word "compressor" alongside "cleaner" within 30
characters, so the App Store keyword field is where that term belongs.

---

## 2. Promotional Text (max 170 chars)

```
Free up storage in minutes. Swipe to delete junk photos, find duplicates and blurry shots, and compress videos — all 100% on your device. No ads, no account.
```
Length: **157 chars** ✅ (Promotional text can be updated anytime without a new build.)

---

## 3. Description

```
TidyByte is the fastest, most private way to clean up your iPhone photo library — and it's completely free.

Tired of "Storage Almost Full"? TidyByte turns photo cleanup into something you'll actually finish. Swipe left to delete, swipe right to keep — review your whole library one photo at a time, just like a dating app, and reclaim gigabytes in minutes.

Beyond swiping, TidyByte packs a full toolkit of smart cleanup tools that surface exactly what's wasting your space: exact and visual duplicates, near-identical similar shots, blurry or poorly-lit photos, screenshots, screen recordings, chat media saved by messaging apps, burst sequences, and your largest files. Convert Live Photos to stills and compress videos and photos to save even more — without deleting your memories.

Your photos never leave your phone. TidyByte does 100% of its processing on-device using Apple's Vision and Photos frameworks, including a local AI search that finds photos from a plain-language description. There is no backend, no account or login, no ads, and no tracking of any kind. Nothing is uploaded, ever.

TidyByte is free, with no in-app purchases and no paywalls. Every feature is available to everyone.

Features:
• Tinder-style swipe to review photos and videos — swipe to delete or keep
• Duplicate finder — exact (SHA-256) and visually similar duplicates
• Similar photos — group near-identical shots taken close together
• Blurry photo detection — find out-of-focus and poorly-exposed shots
• Screenshot cleaner — round up and clear screenshots
• Screen recording cleaner — clear the largest forgotten files
• Chat media cleaner — review what WhatsApp, Telegram and other messengers saved
• Burst cleaner — pick the best from burst sequences
• Smart Categories — sort photos by content type, with on-device AI search in plain words
• Large file finder — surface the biggest files in your library
• Live Photo converter — turn Live Photos into stills to save space
• Video compression — shrink videos while keeping them watchable
• Photo compression — re-encode photos to reclaim space
• Storage dashboard — see what's using your space at a glance
• Activity & savings — track everything you've cleaned and total space freed
• Home Screen widget and Siri shortcuts for one-tap cleanups
• Optional cleanup reminders via local notifications

Free up space. Keep your privacy. Clean with a swipe.
```

All listed features map to shipping tools (see verification at bottom). No fabricated features.

---

## 4. Keywords (max 100 chars, comma-separated, no spaces after commas)

Apple indexes the app name, subtitle and keyword field together, so words already present in the name or subtitle must not be repeated here. The field therefore depends on which subtitle ships.

**Shipped: subtitle I (`Clean photos, free up storage`)** — the name and subtitle
already index "tidybyte", "clean", "photos", "free", "up" and "storage", so the field
targets the remaining intents. This is the set in `docs/appstore/listings.json`
(90 chars ✅):

```
duplicate,image compressor,compress video,screenshot,blurry,declutter,gallery,junk,similar
```

An earlier revision gave the field below for this subtitle. It repeats "storage" and
"clean" — both already indexed — and so spends 12 characters to add nothing:

```
storage,duplicate,image compressor,compress video,screenshot,blurry,declutter,gallery,clean
```

**If a different subtitle ships**, re-derive the field from that subtitle's words:

Subtitle A (`Swipe to clean your photos`) — 95 chars ✅:

```
storage cleaner,duplicate photo,compress video,image compressor,screenshot,blurry,free up space
```

Subtitle B (`Declutter photos, free space`) — 98 chars ✅:

```
storage cleaner,duplicate photo,image compressor,compress video,screenshot,blurry,clean up,gallery
```

Subtitle C (`Photo cleaner & storage saver`) — the words "photo", "cleaner", "storage" and "saver" are already indexed, so the field targets the remaining intents. 91 chars ✅:

```
duplicate,image compressor,compress video,screenshot,blurry,free up space,declutter,gallery
```

Subtitle H (`Photo cleaner, free space`) — "photo", "cleaner", "free" and "space" are already indexed. 91 chars ✅:

```
storage,duplicate,image compressor,compress video,screenshot,blurry,declutter,gallery,clean
```

**What changed from the original 91-char field.** The original was `photo cleaner,storage,duplicates,cleanup,swipe,declutter,free space,blurry,compress,gallery`. It covered the photo-cleaner cluster but not the two intents users actually search for when storage is full: **storage** and **image compressor**. Both are now covered, along with the multi-word phrases (`compress video`, `duplicate photo`) that Apple matches as combinations. Generic single words that carry little ranking weight — `cleanup`, `swipe`, `compress` alone — were dropped to make room. Under the shipped subtitle, `storage` and `clean` moved out of the field entirely because the subtitle now indexes them.

**TODO (human):** final keyword tuning is an ASO call. Validate against your App Store Connect search-term data before shipping, and re-check the character count after any subtitle change: 100 characters is a hard limit, and spaces after commas waste them.

**Caveat on the localized keyword fields.** The rule above (do not repeat a word the name or subtitle already indexes) has been applied to the English field and to the five languages where an exact token repeat was measurable — Bengali, German, Arabic and Hebrew, plus English. It is *not* applied to the remaining languages, because whether a repeat is waste depends on how the storefront tokenizes the script. In the Indic languages the subtitle and keyword field often spell the same word with and without a nukta (`फ़ोटो` vs `फोटो`), which is two different tokens to a tokenizer but one word to a reader; keeping both is defensible and was left alone deliberately. Treat this as an ASO pass, not a finished audit.

---

## 5. Categories

- **Primary: Utilities** — recommended.
- **Secondary: Photo & Video** — recommended.

**Reasoning:** TidyByte's core value is freeing up device storage and decluttering — a maintenance/utility job — which aligns with how comparable "phone cleaner / storage" apps are categorized and ranked. Photo & Video is the natural secondary since the app operates entirely on the photo library and includes compression/conversion. If ASO data later shows the app ranks better under Photo & Video, the two can be swapped; Utilities is the safer primary for discoverability of cleanup intent.

---

## 6. URLs

| Field | Value | Required? |
|---|---|---|
| Support URL | `https://tidybyte.360ghar.com/support` | Required |
| Marketing URL | `https://tidybyte.360ghar.com` | Optional |
| Privacy Policy URL | `https://tidybyte.360ghar.com/privacy` | **Required** |

All three URLs are live and reachable.

---

## 7. Age Rating

**Recommended rating: 4+** (no objectionable content).

Answer the App Store Connect age-rating questionnaire as follows (all "None"/"No"):

- Cartoon or Fantasy Violence: **None**
- Realistic Violence: **None**
- Sexual Content or Nudity: **None**
- Profanity or Crude Humor: **None**
- Alcohol, Tobacco, or Drug Use: **None**
- Mature/Suggestive Themes: **None**
- Horror/Fear Themes: **None**
- Gambling, Contests: **None / No**
- Unrestricted Web Access: **No**
- User-generated content / messaging: **No**

This yields a **4+** rating. Note: the app displays the user's own photos, which may include personal content, but the app itself ships no objectionable content — 4+ is correct.

---

## 8. App Privacy — "Data Not Collected"

In **App Store Connect → your app → App Privacy**:

1. Under "Data Collection," select **"Data is not collected from this app."**
2. This produces a **"Data Not Collected"** privacy label with no data-type details required.

**Rationale (truthful and verifiable):**
- TidyByte has **no backend and performs no networking** — nothing is transmitted off the device.
- All photo analysis (Vision feature prints, blur/exposure detection, SHA-256 hashing) and all cleanup run **100% on-device**.
- There is **no account/login, no analytics SDK, no ad SDK, and no tracking**.
- This is reflected in `Tidybyte/Resources/PrivacyInfo.xcprivacy`: `NSPrivacyTracking = false`, empty `NSPrivacyTrackingDomains`, and an **empty `NSPrivacyCollectedDataTypes` array**. (The file declares only required-reason API usage: DiskSpace, UserDefaults, and FileTimestamp — these are API-usage declarations, not data collection.)

---

## 9. Export Compliance

- The app uses **no encryption** beyond what is exempt (standard OS/HTTPS usage), and in fact does no networking at all.
- `INFOPLIST_KEY_ITSAppUsesNonExemptEncryption` is set to **`NO`** in `project.yml`, so the value is baked into the build's Info.plist. App Store Connect should **not** show a "Missing Compliance" prompt.
- If a compliance question does appear, answer: **"No"** (the app does not use non-exempt encryption). No CCATS / self-classification report is needed.

---

## 10. App Review Notes

Paste into the **App Review Information → Notes** field:

```
TidyByte cleans up the device photo library. To review it properly:

- Use a PHYSICAL iPhone with REAL photos and videos in the library. The iOS Simulator has a small fake photo library and will not exercise most tools meaningfully.
- On first launch, the app requests Photo Library access — please grant FULL access (read & write). Without it, the Swipe screen and Cleanup tools have nothing to operate on.
- Optionally, the app requests Notifications permission only if "Cleanup Reminders" is enabled in Settings; it is not required to review the app.
- There is NO login, NO account, and NO demo credentials — all features are available immediately once photo access is granted.
- The app is free with no in-app purchases. All processing is on-device; the app performs no networking.
- Write actions (deleting photos, saving compressed videos/converted Live Photos) go through the standard iOS PhotoKit confirmation prompts.
```

---

## 11. Screenshots

**Current assets:** `docs/screenshots/iphone/` and `docs/screenshots/ipad/`, seven PNGs each, regenerated by `npm run screenshots`. The legacy flat `docs/screenshots/*.png` files (1206 × 2622, RGBA) are superseded and must not be uploaded — they carry an alpha channel App Store Connect rejects.

**Requirements (verified against Apple, 2026-10):** App Store Connect requires **one iPhone screenshot for "iPhone with Dynamic Island (medium display)"** — accepted sizes **1179 × 2556** or **1206 × 2622** portrait. The 6.9" set (1320 × 2868) is accepted but **optional**; Apple scales the medium set down for larger displays. Because the app ships iPad (`TARGETED_DEVICE_FAMILY: "1,2"`), an **iPad 13-inch screenshot is also mandatory** — accepted sizes **2064 × 2752** or **2048 × 2732** portrait. Minimum 1, maximum 10 screenshots per device size. PNG/JPEG only, and **no alpha channel** — `simctl` output is RGBA and must be flattened. Regenerate with `npm run screenshots`, which writes `docs/screenshots/<iphone|ipad>/` at the exact accepted sizes with alpha stripped and prints a verification table. Source: <https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications>

Suggested upload order, per device (from `docs/screenshots/<device>/`): `01-swipe-home`, `02-cleanup-tools`, `06-storage-dashboard`, `03-cleanup-duplicates`, `07-activity-savings`, then `04-cleanup-screenshots` and `05-cleanup-blurry-photos`. Up to 10 allowed per device size. The legacy `05-swipe-session`, `06-album-picker` and `07-session-complete` shots need manual taps to reach and are not produced by the automated pipeline.

---

## 12. What's New (v1.0.5 release notes)

```
Search your photos in plain words — "dogs on a beach" — with on-device AI. Plus two new tools: Screen Recordings and Chat Media, for the largest files hiding in your library. Everything still runs on your device: no account, no ads, no subscription.
```
Length: 258 chars (well under the 4000-char release-notes limit).

---

## 12b. Version history for App Store Connect

| Version | Build | Release notes source |
|---|---|---|
| 1.0.5 | 6 | §12 above. On-device AI search, Screen Recordings tool, Chat Media tool, smarter reminders. |
| 1.0.4 | — | Cleanup tools refresh: UI, honest savings numbers, keep-choices preserved across scans. (1.0.3 was skipped.) |
| 1.0.2 | — | Storage dashboard redesign, cross-tab deep links, cleanup-tool fixes. |
| 1.0.1 | — | Native iPad support, album picker fix, settings layout. |
| 1.0 | 1 | Initial release. |

The same table appears on the site at `https://tidybyte.360ghar.com/changelog`, which is the canonical version history. `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml` are the source of truth for the app binary.

---

## 13. Website landing pages (per-feature URLs)

The marketing site now has one landing page per cleanup tool, each targeting its own search intent. Use these as the Marketing URL for App Store Connect promotional links, or in review notes, rather than linking everything to the home page:

| Tool | URL |
|---|---|
| All cleanup tools (hub) | https://tidybyte.360ghar.com/photo-cleaner |
| Storage cleaner | https://tidybyte.360ghar.com/storage-cleaner |
| Duplicate photos | https://tidybyte.360ghar.com/duplicate-photo-cleaner |
| Similar photos | https://tidybyte.360ghar.com/similar-photo-cleaner |
| Screenshots | https://tidybyte.360ghar.com/screenshot-cleaner |
| Screen recordings | https://tidybyte.360ghar.com/screen-recording-cleaner |
| Chat media | https://tidybyte.360ghar.com/chat-media-cleaner |
| Blurry photos | https://tidybyte.360ghar.com/blurry-photo-cleaner |
| Large files | https://tidybyte.360ghar.com/large-file-cleaner |
| Burst photos | https://tidybyte.360ghar.com/burst-photo-cleaner |
| Live Photo converter | https://tidybyte.360ghar.com/live-photo-converter |
| Video compression | https://tidybyte.360ghar.com/video-compression |
| Image compression | https://tidybyte.360ghar.com/image-compression |
| Photo organizer | https://tidybyte.360ghar.com/photo-organizer |
| AI photo search | https://tidybyte.360ghar.com/on-device-ai-photo-search |
| Free, no subscription | https://tidybyte.360ghar.com/free-photo-cleaner-no-subscription |

---

## Verification Summary

| Item | Limit | Value | Count | OK |
|---|---|---|---|---|
| App Name | 30 | `TidyByte` | 8 | ✅ |
| Subtitle A | 30 | `Swipe to clean your photos` | 26 | ✅ |
| Subtitle B | 30 | `Declutter photos, free space` | 28 | ✅ |
| Subtitle C | 30 | `Photo cleaner & storage saver` | 29 | ✅ |
| Subtitle F | 30 | `Photo cleaner, free space` | 25 | ✅ |
| Promotional Text | 170 | (see §2) | 157 | ✅ |
| Keywords (any subtitle) | 100 | (see §4) | 95–99 | ✅ |

**Shipping cleanup tools** (verified against `Tidybyte/Features/Cleanup/CleanupTool.swift` enum + view directories): Duplicates, Similar Photos, Screenshots, Screen Recordings, Chat Media, Blurry Photos, Smart Categories, Large Files, Burst Photos, Live Photos, Video Compression, Photo Compression — twelve tools, plus on-device AI photo search inside Smart Categories, the Swipe review flow, the Storage dashboard, and the Activity & Savings ledger. **RecentlyDeleted was removed and is intentionally NOT listed.**

**Every claim in §3 maps to shipped functionality.** The "on-device AI search" line describes `Tidybyte/Services/LocalPhotoIntelligence.swift`: FoundationModels when available, keyword label matching otherwise, both local. The "chat media" line describes `ChatAlbumSelection` in `Tidybyte/Features/Cleanup/MediaCleanerViewModel.swift`. If a future release removes either, update §3 and the site's tool pages together.

---

## 14. Localized listings (20 languages)

The app ships 20 languages, so the store listing is localized too. The machine-readable
copy lives in **`docs/appstore/listings.json`** — one entry per storefront language, with
App Store Connect's field limits recorded in `_limits` so they cannot drift from this doc.

| Command | Purpose |
|---|---|
| `node scripts/localization/make-listings.mjs` | Regenerates `listings.json` from the English copy in this document. Run it after editing §1–§4 or §12. |
| `node scripts/localization/check-listings.mjs` | Validates every field: character limits, empty values, keyword hygiene (no space after a comma, no term repeated from the subtitle), and that `name` is `TidyByte` in every language. |
| `node scripts/localization/check-listings.mjs --strict` | The same, but also fails while any language is untranslated. All 20 languages are translated, and this is what CI runs. |

**Two fields need a human before submission:**

1. **Subtitle** — this document offers four candidates (§1). `listings.json` currently
   carries option F, `Photo cleaner, free space`. The choice is load-bearing for ASO:
   Apple indexes the app name, subtitle, and keyword field together, so whichever
   subtitle ships decides which words must be removed from the keyword field. Change
   `en.subtitle` and re-translate that one field in all 20 languages.
2. **Keywords** — tuned against the subtitle in use. See §4 for the per-subtitle
   variants and the reasoning.

**What is deliberately *not* localized:**

- `name` stays `TidyByte` in every storefront. A translated app name would not match
  what users search for, and the keyword field carries the descriptive terms instead.
- **Screenshots** are captured in English only (`npm run screenshots`). App Store Connect
  accepts a localized set per language, but Apple does not require one: if a localization
  has no screenshots, the next best available language is shown. Localized screenshots
  remain a design task rather than a translation one — see §11.
- **Growth assets are localized.** In-App Events, Custom Product Pages, Asset Library
  creatives, Product Page Optimization treatments, and the header/search creatives are all
  rendered in all 20 languages by `npm run growth`. That is a hard requirement, not a
  choice: Apple requires text inside a creative asset to be localized for every language
  the app supports. See §15.

**Shipping order:** submit the localized listings after the app binary that contains the
translations is approved, so a storefront never promises a language the binary cannot
render.
