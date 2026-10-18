Snap Clean — iOS Media Cleanup App

---

## 0. WHAT YOU ARE BUILDING

You are building a **native iOS application** that helps users manage, clean, and organise the photos and videos on their iPhone. The core UX is a **Tinder-style swipe interface** — the user sees one media item at a time, swipes left to delete, swipes right to organise into albums. On top of this foundation sits a full suite of intelligent cleanup tools: duplicate detection, video compression, screenshot cleaner, blurry photo detection, storage dashboards, and more.

The app is **free with no in-app purchases**. There are no paywalls. Every feature is available to every user.

The app is **personal-use only** — it never uploads any media to any server. All processing is on-device.

---

## 1. TECH STACK

| Concern | Choice | Notes |
|---|---|---|
| Language | Swift 5.9+ | No Objective-C |
| UI Framework | SwiftUI | Use UIKit via `UIViewRepresentable` only where SwiftUI cannot achieve something (e.g. gesture-heavy card stacks) |
| Photo Access | PhotoKit (`Photos` framework) | Primary interface to the device library |
| Image Analysis | Vision framework | Blur detection, face detection, perceptual hashing for near-duplicates |
| Video Processing | AVFoundation + `AVAssetExportSession` | Video compression, duration/size reading |
| Persistence | SwiftData | Store swipe history, compression history, app preferences |
| Notifications | `UserNotifications` framework | Local-only scheduled reminders |
| Minimum iOS | iOS 17 | Required for SwiftData; enables modern SwiftUI APIs |
| Xcode | Latest stable | |
| Architecture | MVVM + SwiftData | One `ViewModel` per major screen; `@Observable` macro throughout |

**Do not use any third-party dependencies.** Use only Apple-provided frameworks.

---

## 2. PERMISSIONS

Request the following permissions at the appropriate moment (never upfront all at once):

- **Photo Library (full access):** Required. Request when the user first opens the app. Use `PHPhotoLibrary.requestAuthorization(for: .readWrite, handler:)`. If denied, show an in-app guidance screen that deep-links to Settings.
- **Notifications:** Optional. Request only when the user enables "Cleanup Reminders" in Settings. Use `UNUserNotificationCenter.current().requestAuthorization`.

---

## 3. APP ARCHITECTURE OVERVIEW

```
[APP_NAME]
├── AppEntry (@main, SwiftData container setup)
├── RootView (tab bar: Swipe | Cleanup | Storage | Settings)
│
├── Swipe Tab
│   ├── SwipeHomeView (filter selector)
│   └── SwipeSessionView (card stack + gesture engine)
│
├── Cleanup Tab
│   ├── CleanupHomeView (feature grid)
│   ├── DuplicatesView
│   ├── SimilarPhotosView
│   ├── ScreenshotCleanerView
│   ├── BlurryPhotosView
│   ├── LargeFilesView
│   ├── BurstPhotosView
│   ├── LivePhotosView
│   └── VideoCompressionView
│
├── Storage Tab
│   └── StorageDashboardView
│
└── Settings Tab
    └── SettingsView
```

---

## 4. DATA MODELS (SwiftData)

```swift
@Model class SwipeRecord {
    var assetLocalIdentifier: String   // PHAsset.localIdentifier
    var decision: SwipeDecision         // .deleted | .addedToAlbum | .skipped
    var albumLocalIdentifier: String?   // if addedToAlbum
    var swipedAt: Date
}

enum SwipeDecision: String, Codable { case deleted, addedToAlbum, skipped }

@Model class CompressionRecord {
    var assetLocalIdentifier: String
    var originalSizeBytes: Int64
    var compressedSizeBytes: Int64
    var compressedAt: Date
    var exportPreset: String            // e.g. AVAssetExportPreset1920x1080
}

@Model class StorageSnapshot {
    var capturedAt: Date
    var photoBytes: Int64
    var videoBytes: Int64
    var screenshotBytes: Int64
    var otherBytes: Int64
}
```

---

## 5. FEATURE SPECIFICATIONS

---

### 5.1 SWIPE SESSION (Core Feature)

**Entry point:** Swipe tab → user picks a filter → session begins.

#### 5.1.1 Filter / Feed Modes

On the Swipe home screen, show five filter options as large tappable cards:

| Filter | Description |
|---|---|
| **All Media** | Every `PHAsset` in the library, newest first |
| **All Media from a Date** | Every asset created on or before a user-chosen date — pick a starting position and review everything older |
| **Not in Any Album** | Assets not in any user-created `PHAssetCollection` of type `.album`. Exclude smart albums. |
| **Specific Album** | User picks an album from a list; only that album's assets are shown |
| **Not Swiped Yet** | *(Default)* Assets with no `SwipeRecord` in SwiftData. First-time users see everything here. |

Tapping a filter starts the Swipe Session with that filtered asset list.

#### 5.1.2 Card Stack UI

- Show a **stack of cards** — the top card is full-screen with the next card slightly visible underneath (scaled down ~5%, offset down ~10pt) to hint continuity.
- Each card shows:
  - The photo/video thumbnail (full bleed, aspect-fill)
  - For videos: duration badge (bottom-left), a play icon overlay
  - For Live Photos: Live badge (top-left)
  - Date taken (bottom, subtle overlay)
  - File size (bottom-right, subtle)
- **Drag gesture:** User drags the card. As they drag:
  - Left drag → card rotates slightly CCW, red "DELETE" label fades in (top-right of card)
  - Right drag → card rotates slightly CW, green "KEEP" label fades in (top-left of card)
  - Up drag → blue "ALBUM" label fades in (top-center of card); releasing opens the album picker
  - Threshold: if drag exceeds 40% of screen width (or height, for the up drag) and is released, the swipe commits. Otherwise the card snaps back.
- **Haptic feedback:** Light impact on drag start. Heavy impact on committed swipe.
- **Button bar below the card:** Four buttons — ✕ (delete), ➤ (skip), folder+ (add to album), ✓ (keep). These trigger the same actions as swiping. Keeping never opens a sheet.

#### 5.1.3 Swipe Left → Delete

1. Animate card flying off screen to the left.
2. Call `PHPhotoLibrary.shared().performChanges { PHAssetChangeRequest.deleteAssets([asset]) }`.
3. Save a `SwipeRecord(decision: .deleted)` to SwiftData.
4. Show next card.
5. If the deletion requires user confirmation (iOS shows a system alert for photo deletion), handle that dialog gracefully.

#### 5.1.4 Swipe Up → Add to Album Flow

Filing a photo is explicit — an up-swipe or the album button — never a side effect of keeping. A plain right-swipe silently keeps the photo (`SwipeRecord(decision: .kept)`), advances the deck, and presents nothing.

1. Animate the card flying up. The card stays on top of the deck; the deck does not advance until the choice resolves.
2. Present a **bottom sheet** (not a full-screen modal) with:
   - Title: "Add to Album"
   - Horizontal scrollable row of the user's **5 most recently used albums** (show album cover thumbnail + name)
   - Below that: a grid of **all user albums** (sorted alphabetically)
   - A **"+ New Album"** button at the top
3. Tapping an album: adds the asset to that album via `PHAssetCollectionChangeRequest.addAssets`. Saves `SwipeRecord(decision: .addedToAlbum, albumLocalIdentifier: album.localIdentifier)`. Dismiss the sheet and advance to the next card.
4. Tapping "+ New Album": shows a text field inline to enter album name. On confirm, creates album, adds asset, dismisses sheet.
5. Dismissing the sheet any other way (Skip / swipe-down): the photo stays unfiled. Skip records `.skipped` and advances; a bare swipe-down keeps the card on top for a fresh decision.

#### 5.1.5 Session End

When all assets in the current filter are exhausted, show a **completion screen** with:
- A checkmark animation
- Count of deleted, kept, organised (added to an album), and skipped assets in this session
- Estimated storage freed (sum of deleted asset sizes, fetched via `PHAsset.resource(for:)`)
- Buttons: "Start Another Session" (returns to filter picker) and "Go to Cleanup Tools"

#### 5.1.6 iCloud Photo Handling

Before displaying a card, check if the asset's data is locally available:
```swift
let resources = PHAssetResource.assetResources(for: asset)
let isLocal = resources.first?.value(forKey: "locallyAvailable") as? Bool ?? false
```
If not local: show a subtle iCloud download indicator on the card. Trigger download with `PHImageManager` using `isNetworkAccessAllowed: true` and `deliveryMode: .highQualityFormat`. Do not block the user — they can swipe past before download completes; just show a spinner overlay.

---

### 5.2 CLEANUP TOOLS TAB

A grid/list of cleanup modules. Each module shows: icon, name, a one-line description, and a **badge showing the count of items found** (computed asynchronously on tab load, cached for the session).

---

#### 5.2.1 Duplicate Finder

**What it does:** Finds exact and near-duplicate photos and videos.

**Exact duplicates:** Group assets by SHA-256 hash of their data. Assets in the same group are exact duplicates. Fetch asset data via `PHAssetResourceManager.requestData`.

**Near-duplicates (photos only):** Use Vision framework's `VNGenerateImageFeaturePrintRequest` to generate a feature vector for each photo. Compute cosine distance between vectors. Group photos where distance < 0.1 (tuneable threshold) as near-duplicates.

**Duplicate videos:** Group videos by `(duration rounded to 0.5s, file size within 1MB tolerance)`.

**UI:**
- Show groups in a list. Each group shows a horizontal strip of thumbnails.
- Tapping a group expands to full-screen comparison view:
  - Thumbnails of all duplicates side by side (scrollable horizontally if >2)
  - Tap any thumbnail to see it full-screen
  - For each asset: date taken, file size, resolution, whether it's in an album
  - One asset per group is auto-selected as "Best" (highest resolution; if tie, most recently modified)
  - User can change which to keep
  - "Delete all others" button — deletes all non-selected assets in the group
- "Delete All Duplicates (Auto)" button at top of list — auto-selects best in each group and deletes the rest. Confirm via alert before executing.
- Progress bar while scanning (this is computationally heavy — run on a background actor).

---

#### 5.2.2 Similar Photo Clustering

**What it does:** Groups photos taken close together in time (burst-like, but not necessarily marked as bursts by iOS).

**Logic:**
1. Fetch all photos sorted by `creationDate`.
2. Group photos where consecutive items are within 5 seconds of each other (configurable in Settings).
3. Each group must have ≥ 2 photos to be shown.
4. Also identify iOS burst photos via `PHAsset.representsBurst == true`.

**UI:**
- List of groups, each showing a count badge and a 3-thumbnail preview strip.
- Tapping a group: grid view of all photos in the group.
- User taps to select which ones to **keep** (multi-select). By default, the sharpest one is pre-selected (use Vision blur scoring — `VNDetectFaceRectanglesRequest` sharpness or `VNGenerateImageFeaturePrintRequest` confidence).
- "Delete unselected" button.
- Swipe-gesture UI also available within a group (same engine as main swipe session, but bounded to this group).

---

#### 5.2.3 Screenshot Cleaner

**What it does:** Surfaces all screenshots for quick batch review and deletion.

**Detection:** `PHAsset.mediaSubtype.contains(.photoScreenshot)`

**UI:**
- Grid view (3 columns) of all screenshots, sorted newest first.
- Tap to enter fullscreen preview with swipe navigation between screenshots.
- Multi-select mode: tap "Select" to enter selection mode. Select all / deselect all. Delete selected.
- Sort options: Newest, Oldest, Largest.
- Show total count and total size at top.
- Integrate the swipe session: "Review with Swipe" button launches a swipe session scoped to screenshots only.

---

#### 5.2.4 Blurry & Low-Quality Photo Detector

**What it does:** Identifies photos that are likely out-of-focus, too dark, or overexposed.

**Detection pipeline (run in background):**
- **Blur:** Use `VNGenerateAttentionBasedSaliencyImageRequest` or run a Laplacian variance calculation on a downsized version of the image. Photos with variance below a threshold (e.g. 100) are flagged as blurry.
- **Dark/overexposed:** Compute average luminance of the image histogram. Flag photos with mean luminance < 30 (dark) or > 225 (overexposed).
- Run only on `.photo` mediaType assets.

**UI:**
- Tabbed view: "Blurry" | "Too Dark" | "Overexposed"
- Grid view within each tab (3 columns). Tapping opens fullscreen.
- Multi-select + batch delete.
- Show confidence score as a subtle bar indicator on each thumbnail.
- "Review with Swipe" button per tab.

---

#### 5.2.5 Large File Finder

**What it does:** Lists all media assets sorted by file size, so the user can identify and delete the largest files first.

**Data source:** `PHAssetResource.assetResources(for: asset)` → sum `value(forKey: "fileSize")` across resources.

**UI:**
- List view, sorted by size descending (default). Toggle to sort by duration (for videos).
- Each row: thumbnail, filename/date, resolution/duration, **file size prominently displayed**.
- Configurable minimum size threshold slider at top (default: show files > 10 MB).
- Multi-select + batch delete.
- Running total of "selected size" shown in the delete button ("Delete 3 items · 847 MB").
- Segmented control: All | Photos | Videos.

---

#### 5.2.6 Burst Photo Cleaner

**What it does:** Specifically handles iOS-native burst photo groups.

**Detection:** `PHAsset.representsBurst == true` and `PHAsset.burstIdentifier` to group them.

**Fetch strategy:** Fetch burst representative photos, then use `PHFetchOptions` with `includeAllBurstAssets = true` to get all frames in each burst.

**UI:**
- List of burst groups: show count of frames, date, strip of first 5 thumbnails.
- Tapping a group: horizontal swipe-through of all frames with the following per frame:
  - Sharpness indicator (computed via Vision)
  - "Keep" toggle
  - Date/time to millisecond precision
- Best frame is pre-selected. User confirms/changes. "Delete rest" action.
- "Auto-clean all bursts" button: keeps the best-scored frame in each burst, deletes the rest. Confirm before executing.

---

#### 5.2.7 Live Photos → Stills Converter

**What it does:** Converts Live Photos to static images to save storage.

**Detection:** `PHAsset.mediaSubtype.contains(.photoLive)`

**Conversion approach:**
1. Export the still component using `PHAssetResourceManager.requestData(for:)` on the resource with type `.photo`.
2. Save the still as a new asset via `PHAssetChangeRequest.creationRequestForAsset(from: UIImage)`.
3. Delete the original Live Photo asset.

**UI:**
- List of all Live Photos: thumbnail, file size (combined still + video component), date.
- Show "Live" badge on each.
- Per-item convert button. Also "Convert All" with confirmation.
- Show before/after estimated size (Live ≈ 4–8 MB; still ≈ 2–4 MB). Show savings.
- After conversion, show a success state on the row.

---

#### 5.2.8 Video Compression

**What it does:** Re-encodes selected videos at lower quality to reclaim storage.

**Export presets available (user chooses):**

| Label | AVAssetExportPreset | Notes |
|---|---|---|
| 1080p HD | `AVAssetExportPreset1920x1080` | Good default |
| 720p | `AVAssetExportPreset1280x720` | Major savings |
| 480p | `AVAssetExportPreset640x480` | Maximum compression |

**Flow:**
1. User opens Video Compression tool — sees a list of all videos, sorted by file size descending.
2. Each row: thumbnail, date, duration, current resolution, current file size.
3. User taps a video to select export quality and see an **estimated output file size** (compute based on bitrate × duration).
4. User can select multiple videos via multi-select.
5. Tapping "Compress" starts a background `AVAssetExportSession` queue (max 2 concurrent).
   - Export the video to a temporary directory.
   - Save the compressed video as a new `PHAsset` via `PHAssetChangeRequest.creationRequestForAssetFromVideo`.
   - Delete the original asset.
   - Save a `CompressionRecord` to SwiftData.
6. Show a **live progress bar** per video during compression. App can be backgrounded; use `BGProcessingTask` to continue compression in background.
7. Show total storage reclaimed after completion.
8. Compression history: a sub-screen listing all past compressions with before/after sizes.

**Edge cases:**
- Do not offer to compress videos already at 480p or below.
- If the device is low on free storage (< 2× video size), warn the user before starting.
- Videos stored only in iCloud (not downloaded): prompt to download first.

---

### 5.3 STORAGE DASHBOARD TAB

A rich analytics screen showing the user's media storage breakdown and trends.

#### 5.3.1 Current Breakdown

Fetch all assets grouped by `mediaType` and `mediaSubtype`. Compute total file size per category using `PHAssetResource`.

Display as:
- A **donut/ring chart** (built in SwiftUI using `Canvas` or `Path`) showing:
  - Photos (blue)
  - Videos (purple)
  - Screenshots (yellow)
  - Live Photos (teal)
  - Other (grey)
- Below the chart: a legend with each category, item count, and total size.
- Total library size vs total device storage (use `FileManager.default.attributesOfFileSystem(forPath:)` for device storage).

#### 5.3.2 iCloud Status

- Count of assets available locally vs iCloud-only (not downloaded).
- "iCloud-only" assets: those where `PHAsset.resource.isLocallyAvailable == false`.
- Show size represented by iCloud-only assets.
- If "Optimise iPhone Storage" is not enabled, show a tip card suggesting the user enable it (deep-link to `App-prefs:root=PHOTOS`).

#### 5.3.3 Storage Trend

- On every app launch, capture a `StorageSnapshot` to SwiftData (at most once per day — check if a snapshot already exists for today before saving).
- Display a **line chart** (using SwiftUI Charts framework) of total library size over the last 30 days.
- Show delta: "You've added X GB of media in the last 30 days."

#### 5.3.4 Cleanup Opportunities Summary

A quick-action section showing:
- "X duplicate groups found — free up Y MB"
- "X screenshots — free up Y MB"
- "X videos over 100 MB — Y GB total"
- A Recently Deleted shortcut with manual instructions; no measurable balance.
- Each row is tappable. The first three navigate to that cleanup tool; the Recently Deleted row deep-links to the system Photos app via `photos-redirect://` (PhotoKit does not expose this album or an API to empty it).

This section is computed async when the tab loads. Show skeleton placeholders while computing.

#### 5.3.5 Recently Deleted Reminder

PhotoKit does not expose the contents of Recently Deleted or provide a public API to empty it. Do not find this album by title or claim a remaining balance.

After confirmed deletion, show a dismissible notice: "This cleanup moved X to Recently Deleted. Open Photos to empty it." X is the known size only when all deleted sizes are available; otherwise use the confirmed item count. Keep the notice across navigation, including a swipe session that commits while exiting. Cancelled or failed operations do not create a success notice. Partial operations count only confirmed deletions, excluding assets already absent from Photos.

Compression and Live Photo replacement notices use original bytes, while the existing savings ledger keeps net savings. Notices are transient and do not add another history record.

Open Photos with `photos-redirect://`. If opening fails, show manual instructions to find Recently Deleted under Utilities. The Storage tab retains a general shortcut without any balance claim.

#### 5.3.6 Camera Format Insights

Show Cinematic and Spatial counts and known sizes from public PhotoKit subtype flags. Categories can overlap and are not added to reclaimable totals. ProRAW, ProRes, and RAW+JPEG totals are unavailable in this subtype-only implementation. Include a manual Settings → Camera → Formats tip for future captures.

---

### 5.4 SETTINGS TAB

Simple settings screen with the following options:

| Setting | Type | Default | Notes |
|---|---|---|---|
| Language | Picker | Automatic (device language) | 20 languages. Applies live, no relaunch. See §13. |
| Appearance | Picker | Automatic (device) | Light / Dark / Automatic, matching iOS's own Appearance control. |
| Haptics | Toggle | On | Gates every `UIImpactFeedbackGenerator` / `UINotificationFeedbackGenerator` call through `HapticHelper`. |
| Similar Photo Time Window | Slider (1–60 seconds) | 5 seconds | For Similar Photos clustering |
| Blur Detection Sensitivity | Segmented (Low/Med/High) | Medium | Adjusts Laplacian variance threshold |
| Large File Threshold | Slider (5–500 MB) | 10 MB | For Large File Finder |
| Default Swipe Filter | Picker | Not Swiped Yet | Sets default filter on swipe home |
| Cleanup Reminders | Toggle | Off | Enables weekly local notification |
| Reminder Day | Day picker | Device's first weekday | Shown only if reminders enabled. Weekday names are localized and start from the device's first day of the week, not Sunday. |
| Video Compression Default Preset | Picker | 1080p HD | |
| Reset Swipe History | Button | — | Clears all SwipeRecord entries. Confirm before executing. |
| About | Section | — | App version, build, acknowledgements |

---

### 5.5 SMART AUTOMATION & NOTIFICATIONS

When **Cleanup Reminders** is enabled in Settings:
- Schedule a weekly `UNCalendarNotificationTrigger` for the chosen day at 10:00 AM.
- Refresh dated screenshot and large-file counts on launch, after library changes, and after reminder settings change. Example: *"Last scan, 25 Sep 2026: 214 screenshots (1.2 GB) to review."* Counts are a snapshot, not a measurement at notification delivery. Omit incomplete size totals and identify limited-library counts. Use generic text when counts are unavailable.
- Tapping the notification opens the Cleanup tab.
- Re-schedule the notification each time the app launches (to reflect updated content).

> **Localization note (2026-10):** the reminder time is stored as a `Date` and rendered through `Formatters.shortTime`, so it follows the user's 12/24-hour convention. The footer used to hardcode "10 AM", which read as a foreign convention in most of the world. Notification bodies are built with `L10n` because they render outside the app process, where there is no SwiftUI environment to resolve a `LocalizedStringKey`.

---

## 6. PERFORMANCE REQUIREMENTS

- **Never block the main thread.** All PHAsset fetching, Vision analysis, file size computation, and hashing must run on background actors (`actor` or `Task { await ... }` with appropriate QoS).
- Use **pagination** in the swipe session: pre-fetch thumbnails for the next 10 cards in advance using `PHImageManager.requestImage` with `deliveryMode: .fastFormat` first, then upgrade to `.highQualityFormat`.
- Duplicate detection and blur scoring for large libraries (10,000+ photos) must show incremental progress and must not lock the UI.
- Cache computed results (duplicate groups, blur scores) in memory for the app session. Do not re-compute unless the photo library sends a `PHPhotoLibraryChangeObserver` notification indicating new changes.
- Register as `PHPhotoLibraryChangeObserver` and invalidate relevant caches when the library changes.

---

## 7. ERROR HANDLING

- **Photo library access denied:** Show a dedicated full-screen onboarding/permission screen with an explanation and a button that opens `UIApplication.openSettingsURLString`. The app should not crash or show empty states without explaining why.
- **iCloud download failure:** Show a non-blocking toast/snackbar. Let the user swipe past.
- **AVAssetExportSession failure:** Show an alert with the specific error. Log to `os_log`. Do not silently discard.
- **SwiftData errors:** Wrap all `modelContext.save()` calls in do/catch. Log errors. Non-critical (swipe records failing to save should not crash the app).
- **Recently Deleted:** Do not attempt to enumerate it. Use only confirmed cleanup outcomes for notices and offer manual Photos instructions.

---

## 8. UI/UX DESIGN DIRECTION

- **Follow the device's appearance**, with full light and dark support (use semantic colours / `Color(uiColor: .systemBackground)` throughout). Settings offers an explicit override, but "Automatic" is the default, so the app never freezes a scheme the user did not choose. (HISTORICAL, 2026-10: this line read "Dark mode first"; the default is now the device.)
- **Two screens stay dark on purpose:** the full-screen media previews (`MediaPreviewView`, `LivePhotoPreviewView`) pin `.preferredColorScheme(.dark)`. A bright backdrop changes how a photo reads, which is why the Photos app does the same. This is the one place an explicit scheme beats the user's choice.
- Use **SF Symbols** for all iconography. No custom icon assets needed.
- The swipe card stack is the hero UI. It must feel **physical and responsive** — match real-world card physics (spring animation, rotation tied to drag offset).
- Transitions between screens: use SwiftUI's `.navigationTransition(.zoom)` (iOS 18) where available; fall back to `.slide`.
- Destructive actions (delete, compress+replace): always confirm with an alert that explicitly states what will happen and is irreversible.
- Loading/scanning states: use skeleton placeholders (rectangles with shimmer animation) rather than spinners for list/grid content.
- Empty states: every list/grid must have a designed empty state view with an SF Symbol illustration and a short message.

---

## 9. FILE STRUCTURE

```
[APP_NAME]/
├── App/
│   ├── [APP_NAME]App.swift          # @main, SwiftData container
│   └── RootView.swift               # TabView root
│
├── Models/
│   ├── SwipeRecord.swift
│   ├── CompressionRecord.swift
│   └── StorageSnapshot.swift
│
├── Services/
│   ├── PhotoLibraryService.swift    # All PHAsset fetching, change observer
│   ├── DuplicateDetectionService.swift
│   ├── VisionAnalysisService.swift  # Blur, near-duplicate feature prints
│   ├── VideoCompressionService.swift
│   └── NotificationService.swift
│
├── Features/
│   ├── Swipe/
│   │   ├── SwipeHomeView.swift
│   │   ├── SwipeSessionView.swift
│   │   ├── CardView.swift
│   │   ├── AlbumPickerSheet.swift
│   │   └── SwipeSessionViewModel.swift
│   ├── Cleanup/
│   │   ├── CleanupHomeView.swift
│   │   ├── Duplicates/
│   │   ├── SimilarPhotos/
│   │   ├── Screenshots/
│   │   ├── BlurryPhotos/
│   │   ├── LargeFiles/
│   │   ├── BurstPhotos/
│   │   ├── LivePhotos/
│   │   ├── VideoCompression/
│   ├── Storage/
│   │   └── StorageDashboardView.swift
│   └── Settings/
│       └── SettingsView.swift
│
└── Shared/
    ├── Extensions/
    ├── Components/           # Reusable UI: SkeletonView, EmptyStateView, etc.
    └── Utilities/
```

---

## 10. WHAT THE AGENT SHOULD FIGURE OUT INDEPENDENTLY

The following are intentionally **left to the agent's discretion**. The agent should make sensible engineering decisions:

- Exact Vision framework request chaining and concurrency management.
- Precise SwiftUI animation curves and spring parameters for the card stack (as long as it feels physically convincing).
- Whether to use `@StateObject` / `@Observable` / `@ObservedObject` — use modern `@Observable` macro throughout (iOS 17+).
- Exact SwiftData query predicates and sort descriptors.
- How to structure `PhotoLibraryService` — whether as a singleton, `@Observable`, or actor.
- Exact layout metrics (padding, corner radii, font sizes) — follow iOS HIG.
- Whether to use `LazyVGrid` or `LazyVStack` for grids — choose whichever performs better for the content density.
- `BGProcessingTask` registration and scheduling details for background video compression.
- How to handle the system-level delete confirmation alert that iOS presents — do not try to suppress it; handle it gracefully.

---

## 11. WHAT THIS APP DOES NOT DO

Explicitly out of scope — do not build:

- Any network requests, backend, or cloud sync of any kind.
- User accounts or authentication.
- Sharing functionality (beyond what iOS share sheet provides natively if the user long-presses).
- In-app purchases or subscription logic.
- App Clips.
- iPad-specific layout (HISTORICAL, 2026-08: the app is universal since v1.0.1 — iPad layout shipped; this line predates that and is kept only for PRD history).
- Direct access to other apps' sandboxed data.
- Private API usage (`LSApplicationWorkspace` or similar) — App Store compliance required.

---

## 12. TESTING NOTES

- Build and test on a **physical iPhone**. The simulator photo library is fake and will not reflect real-world performance.
- Test with a large library (1,000+ assets) to validate background processing performance.
- Test iCloud-only asset handling by using a device with "Optimise Storage" enabled.

---

## 13. LOCALIZATION & DEVICE-NATIVE DEFAULTS

TidyByte ships **20 languages** and detects its defaults from the device rather than
assuming the US. This section is the contract; the pipeline that enforces it is in
`scripts/localization/`.

### 13.1 Supported languages

English (base), Hindi, Bengali, Tamil, Telugu, Marathi, Gujarati, Kannada,
Malayalam, Punjabi, Spanish, French, German, Portuguese (Brazil), Italian,
Japanese, Korean, Simplified Chinese, Russian, Arabic, Hebrew.

Arabic and Hebrew are **right-to-left** and the whole layout mirrors.

### 13.2 What detects from the device

| Surface | Behavior |
|---|---|
| Language | Follows the device language on first launch. If the device is set to a language we do not ship, the UI falls back to English and Settings says so. |
| Appearance | Follows the device's light/dark setting, including an automatic schedule. |
| Region | Always from the device, even when the language is overridden. A US user who picks German gets German words and US dates — which is what iOS itself does for a per-app language. |
| File sizes | Locale-aware decimal units (`1,5 MB` in German, Arabic-Indic digits in Arabic). |
| Dates and times | Locale-aware, including 12/24-hour convention. |
| Week start | The device's first day of the week (Monday in most of the world, Saturday in much of the Middle East), not Sunday. |
| List joining | Locale conjunction via `ListFormatter` ("a, b und c", "a、b、c"). |

### 13.3 Three ways the language can change

1. **Automatic** (default) — follows the device.
2. **iOS per-app language** — Settings links to the iOS screen, which is the only
   way to change the language of *system-rendered* UI (the photo permission alert,
   the Photos picker, the share sheet, the Mail composer).
3. **In-app picker** — applies immediately, no relaunch.

In-app switching works because `RootView` injects `\.locale` and
`\.layoutDirection` and rebuilds the view tree on language change. The two surfaces
that do *not* change live are documented where they bite: system-owned UI follows on
the next launch, and the widget refreshes on its next timeline reload.

### 13.4 Architecture

- **`AppLanguage`** — the 21-case enum (20 + `system`). Foundation-only so the
  widget target can share it.
- **`LanguagePreferenceStore`** — the stored choice, mirrored to the App Group so
  the widget reads the same value.
- **`L10n`** — lookup for code that runs outside a SwiftUI view: services, view
  models, notification bodies, the widget, App Intents. Resolves against the chosen
  language's `.lproj` bundle rather than `Bundle.main`, which is what makes the
  switch work without a relaunch.
- **`Formatters`** — every locale-aware number, size, date, list, and calendar
  helper. `ByteCountFormatter` is deliberately not used: it has no locale API at
  all, so it renders "1.5 MB" for every user on earth.
- **`LocalizedStringKey`** — the parameter type for any shared component that
  renders text (`EmptyStateView`, `ToolIdleView`, `ToolScanningView`,
  `ToolErrorBanner`, `MetadataRow`). A `String` parameter silently opts out of
  localization; this is the single most common way a screen stays English.

### 13.5 String Catalog

One catalog, `Tidybyte/Resources/Localizable.xcstrings`, shared by the app and the
widget extension. English text is the key. Plural variations compile to
`.stringsdict`, which is the only way to get correct CLDR categories per language
(Arabic needs 6, Russian 4, Hebrew 3, Japanese and Chinese 1).

Permission prompts live in a separate `Tidybyte/InfoPlist.xcstrings`, keyed on the
**plist key name** (`NSPhotoLibraryUsageDescription`), not the English sentence —
that is how iOS resolves them, and keying on the sentence compiles fine while doing
nothing.

### 13.6 The pipeline

`scripts/localization/`:

| Script | Role |
|---|---|
| `refresh.sh` | The one command to run after changing any user-facing string. Builds to emit `.stringsdata`, syncs Xcode's own extraction into the catalog, scans for code-built strings, collects Xcode's key set, merges translations, validates. |
| `extract.mjs` | Finds what Xcode cannot see: `L10n.*` calls, display properties, App Shortcut phrases, and a broad prose audit for user-facing text that never reached the catalog. `--check` exits non-zero on a gap. |
| `collect-xcode-keys.mjs` | Reads the keys Xcode's extractor saw out of the build's `.stringsdata`, so `build-catalog.mjs` can tell a live key from a dead one. |
| `build-catalog.mjs` | Merges `translations/*.json` into the catalog, expands plurals, pins reordered placeholders positionally, and prunes keys no call site can reach. |
| `check.mjs` | Fails on missing languages, placeholder mismatches, wrong plural categories, and a `UsageDescription` set in `project.yml` with no catalog entry. |
| `make-listings.mjs` / `check-listings.mjs` | Build and validate the App Store listings against App Store Connect's field limits. |

`refresh.sh` builds into a repo-local `build/LocalizationDerivedData` rather than
`~/Library/Developer/Xcode/DerivedData`. The shared directory holds build trees
from every checkout and configuration, so a lookup there can read a
`.stringsdata` from an unrelated build and merge keys from source that no longer
exists. The catalog gate is `git diff --exit-code`, which only means anything if
the catalog is a pure function of the source.

**The catalog is pruned, because `xcstringstool sync` only ever adds.**
A key whose source text is deleted or rewritten stays forever, carrying 20
translations and reporting 100% coverage for a string nothing looks up. That is
worse than a missing translation: the denominator grows, every language's
percentage is flattered, and a genuinely untranslated string hides in the total.
A real one shipped — `"Couldn't %@ this %@%@."` survived the rewrite of its call
site into four whole sentences.

The website has its own pair under `scripts/localization/site/`:

| Script | Role |
|---|---|
| `extract-site-strings.mjs` | Pulls translatable text out of `src/content/pages/index.html`, plus the title and description from `src/data/pages.ts`. |
| `build-site-translations.mjs` | Regenerates the 20 localized landing pages from the English page plus `site-translations/<slug>.json`. |
| `keep-literal.mjs` | The strings that stay English on the site (product and framework names). Shared by both scripts, so a keep-literal string is neither asked for nor reported missing. |

The site builder takes the **English page as the structural source of truth** and
replaces only the text. Hand-editing 20 copies of a 47 KB file is how markup
drifts; generating them means every localized page has the markup the design was
reviewed against. It fails outright when an English string has no translation —
a page declaring `lang="de"` while rendering English is worse than no page.

The FAQ `FAQPage` structured data is rebuilt per language from that page's own
visible FAQ rather than translated a second time, so the schema cannot drift from
what a reader sees (Google requires them to match, and `seo-audit.mjs` enforces
it).

`translations/_glossary.json` is binding: `keepLiteral` terms (TidyByte, iOS,
iPhone, HEIC, Live Photo, MB, iCloud) are never translated, and per-language terms
for screenshot, duplicate, compress, Recently Deleted, and Screen Time must be used
as given. The Screen Time and Recently Deleted entries name the exact string iOS
shows in Settings, because the surrounding copy tells the user to go look there.

### 13.7 CI gates

`.github/workflows/ci.yml` runs these checks; each fails the build.

1. **Catalog freshness** — `refresh.sh` then `git diff --exit-code` on both
   catalogs. A stale catalog is otherwise invisible: the app builds and runs, it
   just shows English where a translation exists.
2. **No unlocalized user-facing strings** — `extract.mjs --check`, three scans for
   three shapes that hide a string completely:
   - **A key computed from an enum.** `L10n.string(rawValue)` is invisible to every
     literal scan, localizes correctly at runtime, and therefore ships English in all
     20 languages with nothing failing. Seven enums had that shape and sixteen keys
     were missing; the labels are now written out as literals in a `switch`.
   - **A literal nested in an interpolation.** `Text("Couldn't \(ok ? "load" :
     "download") …")` gives `Text` the outer literal as a key and renders the inner
     `String` verbatim, so every language kept the English fragment. The German
     template read "load dieses video nicht möglich." Eight sites had this shape.
   - **Prose in a `String` parameter** that no call site localizes. This is the
     original case: the sentence never reaches the catalog while every coverage
     number reads 100%.
3. **Full translation coverage** — `check.mjs --strict`. `refresh.sh` runs the same
   check without `--strict`, so a key still carrying English passes locally and is
   merely reported; CI fails on it.
4. **Listing validity** — `check-listings.mjs --strict`: field limits, keyword
   hygiene, and full coverage across all 20 languages.
5. **Localized page freshness** — regenerate the landing pages and `git diff
   --exit-code`. A translation edit nobody rebuilt is a page still showing English.
   The builder's own missing-translation failure is the stronger half of this gate.
6. **Site build and audit** (separate `site` job) — `npm run build && npm run
   check`: title and description budgets, duplicate titles, hreflang parity,
   per-page `lang` and `dir`, sitemap coverage, and a Markdown alternate for every
   sitemap URL.

### 13.8 Non-goals

- **Machine-drafted translations ship with a review flag.** The 20 locales were
  drafted by translators and are marked for native review; `check.mjs --strict`
  tracks coverage, not quality. The batches' flagged judgment calls are recorded in
  `scripts/localization/translations/_batch*.md`.
- **Blog posts stay English.** A translated post that goes stale is worse for trust
  than an English one that is current. Only the landing page and the App Store
  listing are localized.
- **The app does not translate system-owned UI.** The photo permission alert, the
  Photos picker, and the share sheet are rendered by iOS and follow the app's
  language on the next launch.

