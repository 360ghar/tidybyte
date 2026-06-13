# App Store Connect Listing — TidyByte v1.0

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

| Option | Text | Chars |
|---|---|---|
| A | `Swipe to clean your photos` | 26 ✅ |
| B | `Declutter photos, free space` | 28 ✅ |
| C | `Photo cleaner & storage saver` | 29 ✅ |

**TODO (human):** choose one subtitle.

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

Beyond swiping, TidyByte packs a full toolkit of smart cleanup tools that surface exactly what's wasting your space: exact and visual duplicates, near-identical similar shots, blurry or poorly-lit photos, screenshots, burst sequences, and your largest files. Convert Live Photos to stills and compress videos and photos to save even more — without deleting your memories.

Your photos never leave your phone. TidyByte does 100% of its processing on-device using Apple's Vision and Photos frameworks. There is no backend, no account or login, no ads, and no tracking of any kind. Nothing is uploaded, ever.

TidyByte is free, with no in-app purchases and no paywalls. Every feature is available to everyone.

Features:
• Tinder-style swipe to review photos and videos — swipe to delete or keep
• Duplicate finder — exact (SHA-256) and visually similar duplicates
• Similar photos — group near-identical shots taken close together
• Blurry photo detection — find out-of-focus and poorly-exposed shots
• Screenshot cleaner — round up and clear screenshots
• Burst cleaner — pick the best from burst sequences
• Smart Categories — sort photos by content type
• Large file finder — surface the biggest files in your library
• Live Photo converter — turn Live Photos into stills to save space
• Video compression — shrink videos while keeping them watchable
• Photo compression — re-encode photos to reclaim space
• Storage dashboard — see what's using your space at a glance
• Optional cleanup reminders via local notifications

Free up space. Keep your privacy. Clean with a swipe.
```

All listed features map to shipping tools (see verification at bottom). No fabricated features.

---

## 4. Keywords (max 100 chars, comma-separated, no spaces after commas)

```
photo cleaner,storage,duplicates,cleanup,swipe,declutter,free space,blurry,compress,gallery
```
Length: **91 chars** ✅ (includes commas; under the 100-char limit by 9 chars)

Notes: Do not repeat words already in the App Name/Subtitle to save space. Avoid spaces after commas — they count and waste characters. **TODO (human):** final keyword tuning is a marketing/ASO call.

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

## 12. What's New (v1.0 release notes)

```
Welcome to TidyByte 1.0! Swipe to clean your photo library, find duplicates, blurry shots, and large files, convert Live Photos, and compress videos and photos — all free and 100% on your device.
```
Length: 196 chars (well under the 4000-char release-notes limit).

---

## Verification Summary

| Item | Limit | Value | Count | OK |
|---|---|---|---|---|
| App Name | 30 | `TidyByte` | 8 | ✅ |
| Subtitle A | 30 | `Swipe to clean your photos` | 26 | ✅ |
| Subtitle B | 30 | `Declutter photos, free space` | 28 | ✅ |
| Subtitle C | 30 | `Photo cleaner & storage saver` | 29 | ✅ |
| Promotional Text | 170 | (see §2) | 157 | ✅ |
| Keywords | 100 | (see §4) | 91 | ✅ |

**Shipping cleanup tools** (verified against `Tidybyte/Features/Cleanup/CleanupTool.swift` enum + view directories): Duplicates, Similar Photos, Screenshots, Blurry Photos, Smart Categories, Large Files, Burst Photos, Live Photos, Video Compression, Photo Compression. Plus the Swipe review flow and Storage dashboard. **RecentlyDeleted was removed and is intentionally NOT listed.**
```
