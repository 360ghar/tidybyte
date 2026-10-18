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
| A | `Swipe to clean your photos` | 26 ✅ | Original. Strong on the swipe hook, weak on storage intent. |
| B | `Declutter photos, free space` | 28 ✅ | Original. Balanced. |
| C | `Photo cleaner & storage saver` | 29 ✅ | Original. |
| **D** | `Storage cleaner & photo cleaner` | 33 ❌ | Too long — listed to show the ceiling. |
| **E** | `Storage cleaner, photo cleaner` | 31 ❌ | Too long. |
| **F** | `Clean storage & compress images` | 32 ❌ | Too long. |
| **G** | `Free storage cleaner & compressor` | 33 ❌ | Too long. |

**TODO (human):** choose one subtitle. If the storage-cleaner positioning matters more than the swipe hook, the shortest phrase that carries both is `Photo cleaner, free space` (24 chars) or `Clean photos, free up storage` (28 chars). Neither fits the word "compressor" alongside "cleaner" within 30 characters, so the App Store keyword field is where that term belongs.

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

**If subtitle A (`Swipe to clean your photos`) ships** — 95 chars ✅:

```
storage cleaner,duplicate photo,compress video,image compressor,screenshot,blurry,free up space
```

**If subtitle B (`Declutter photos, free space`) ships** — 98 chars ✅:

```
storage cleaner,duplicate photo,image compressor,compress video,screenshot,blurry,clean up,gallery
```

**If subtitle C (`Photo cleaner & storage saver`) ships** — the words "photo", "cleaner" and "storage" are already indexed, so the field targets the remaining intents. Recommended set (97 chars ✅):

```
duplicate,image compressor,compress video,screenshot,blurry,free up space,declutter,gallery
```

**If subtitle F (`Photo cleaner, free space`) ships** — 99 chars ✅:

```
storage cleaner,duplicate photo,image compressor,compress video,screenshot,blurry,declutter,gallery
```

**What changed from the original 91-char field.** The original was `photo cleaner,storage,duplicates,cleanup,swipe,declutter,free space,blurry,compress,gallery`. It covered the photo-cleaner cluster but not the two phrases users actually search for when storage is full: **storage cleaner** and **image compressor**. Both are now in every variant, along with the multi-word phrases (`compress video`, `duplicate photo`, `free up space`) that Apple matches as combinations. Generic single words that carry little ranking weight — `cleanup`, `swipe`, `compress`, `storage` alone — were dropped to make room.

**TODO (human):** final keyword tuning is an ASO call. Validate against your App Store Connect search-term data before shipping, and re-check the character count after any subtitle change: 100 characters is a hard limit, and spaces after commas waste them.

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

**Existing assets in `docs/screenshots/`:**

- `01-swipe-home.png`
- `02-cleanup-tools.png`
- `03-storage-dashboard.png`
- `04-settings.png`
- `05-swipe-session.png`
- `06-album-picker.png`
- `07-session-complete.png`

**Action needed (human):** App Store Connect requires screenshots for the **6.9" display (iPhone 16 Pro Max / 17 Pro Max class — 1320 × 2868 px portrait)**; the 6.7" set is also commonly required/accepted. **Verify each PNG's pixel dimensions match an accepted App Store size and regenerate if not.** Do not assume the repo screenshots are already at submission resolution — capture/regenerate from the standard simulator (iPhone 17 Pro Max) at the required size if they don't match. (Do not edit/generate images as part of this doc.)

Suggested upload order: `01-swipe-home`, `05-swipe-session`, `07-session-complete`, `02-cleanup-tools`, `03-storage-dashboard` (matches the README hero row), then `06-album-picker`, `04-settings` as extras (up to 10 allowed).

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
- Screenshots and the App Store preview video. App Store Connect requires a separate
  asset set per locale, and localized screenshots are a design task rather than a
  translation one — see §11 for the English set.

**Shipping order:** submit the localized listings after the app binary that contains the
translations is approved, so a storefront never promises a language the binary cannot
render.
