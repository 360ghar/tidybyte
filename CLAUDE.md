# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

TidyByte is a native iOS app (Swift/SwiftUI, iOS 17+) that helps users clean up their photo library. Core UX is a Tinder-style swipe interface for reviewing media. The app is free, has no backend, and all processing is on-device. **No third-party dependencies** — Apple frameworks only.

## Build & Run

- **Xcode project**: `Tidybyte.xcodeproj` (generated from `project.yml` via XcodeGen)
- **Build**: `xcodebuild -project Tidybyte.xcodeproj -scheme Tidybyte -destination 'platform=iOS Simulator,name=iPhone 16' build`
- **Swift version**: 5.9 language mode (Xcode 15.3+ toolchain — `ContinuationResumer` uses the `sending` keyword), strict concurrency enabled (`SWIFT_STRICT_CONCURRENCY: complete`)
- **Min deployment**: iOS 17
- **Universal** (`TARGETED_DEVICE_FAMILY: 1,2`, iPhone + iPad) — iPhone is portrait-only (the swipe UX is portrait-centric), iPad supports all orientations.
- **App icon** uses Xcode's single-size format: one opaque 1024×1024 PNG per appearance (`icon_1024.png`, `icon_1024_dark.png`, `icon_1024_tinted.png`) on `universal` / `platform: ios` slots. There are no per-idiom slots; Xcode derives every smaller size, including the iPad 152×152 icon. The dark and tinted appearances only work in this format — the older per-size format silently drops the `appearances` keys. Regenerate with `swift Tidybyte/Scripts/GenerateAppIcon.swift`; add `--sync-site` to refresh the site's logo, favicon and touch icons, or `--check` to verify what is on disk. One script renders both the app icon and the site marks, but the two now have separate geometry (`art` for the app, `siteArt` for the site): the app icon leads, so the site keeps the art it already has until someone runs `--sync-site`. `--check` also measures small-size legibility from the shipped 1024 and fails on a flat card, a lost card, or a missing shine; it runs on the light icon only.
- Must test on a physical device for photo library operations — simulator has a fake photo library

## Architecture

**MVVM + Actors + SwiftData**

### Services (all Swift `actor` types)
Services are instantiated on-demand and injected via initializers, except a few intentional shared instances (`ImageCache.shared`, `PhotoLibraryService.shared`, `CleanupLedger.shared`, `PendingRoute.shared`). Dependencies are injected via initializers:
- `PhotoLibraryService` — wraps all PhotoKit operations (fetching, mutations, change observation, image loading). Uses `withCheckedContinuation` to bridge PHImageManager callbacks to async/await. Accesses undocumented KVC properties (`fileSize`, `locallyAvailable`) with `responds(to:)` guards.
- `DuplicateDetectionService(photoService:, visionService:)` — exact (SHA-256) and near-duplicate (Vision feature prints) detection
- `VisionAnalysisService` — blur detection, exposure analysis, feature print generation. Works with CGImage inputs, no library access.
- `VideoCompressionService(photoService:)` — AVAssetExportSession-based compression with progress polling
- `NotificationService` — static methods only (not an actor), wraps UNUserNotificationCenter

### ViewModels
One `@Observable @MainActor` ViewModel per major screen. Progress reporting from services uses `@Sendable` closures normalized to 0.0–1.0 float range.

### Models
- **SwiftData models**: `SwipeRecord`, `CompressionRecord`, `StorageSnapshot`, `CleanupActivityRecord` — simple record types with `@Model` macro
- **Value types**: `AssetSummary` (DTO decoupling UI from PHAsset), `AlbumInfo` — both `Sendable`, `Identifiable`, `Hashable`

### Design System
`Color+Theme.swift` defines the design system: `Spacing` enum (xs=4 to xxxl=32), `CornerRadius` enum, semantic colors (`appBackground`, `destructive`, `success`), category colors, gradients, and shadow view modifiers.

## Key Conventions

- **Actors for all services** — no locks, no dispatch queues
- **`@Observable` macro** throughout — not `ObservableObject`/`@StateObject`
- **`Sendable` on all value types** passed across actor boundaries
- **Long-running operations yield periodically**: `if index % 20 == 0 { await Task.yield() }`
- **Error enums** conform to `LocalizedError` (`PhotoServiceError`, `CompressionError`)
- **Non-critical failures** use `try?` (e.g., temp file cleanup, notification scheduling)
- **Tab structure**: `TabView` with independent `NavigationStack` per tab in `RootView`

## File Layout

```
Tidybyte/
├── App/           # @main entry + RootView (TabView)
├── Models/        # SwiftData models + DTOs
├── Services/      # Actor-based services
├── Features/      # Feature modules (Swipe/, Cleanup/, Storage/, Activity/, Settings/)
│   └── Cleanup/   # Sub-modules per tool (Duplicates/, Screenshots/, etc.)
└── Shared/
    ├── Components/ # Reusable UI (SkeletonView, EmptyStateView, GlassCard, etc.)
    ├── Extensions/ # Color+Theme, PHAsset+Extensions, etc.
    └── Utilities/  # ImageCache (actor singleton), PhotoPermissionHandler, CleanupLedger
```

## PRD Reference

`prd.md` contains the full product requirements document with detailed feature specifications, data models, and UI/UX direction. Consult it for feature requirements and expected behavior.
