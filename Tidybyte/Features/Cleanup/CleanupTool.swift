import SwiftUI

/// Groups the ten tools by what the user is actually trying to achieve.
///
/// Grouping is by intent, not by which tools happen to free space: Live Photos
/// sits with compression (it converts rather than deletes) and Screenshots sits
/// with organizing (it is a review-and-decide tool), even though both end up
/// reclaiming room.
enum CleanupToolCategory: String, CaseIterable, Identifiable, Sendable {
    case freeUpSpace
    case organize
    case shrink

    var id: String { rawValue }

    var title: String {
        switch self {
        case .freeUpSpace: "Free Up Space"
        case .organize: "Review & Organize"
        case .shrink: "Reclaim Without Deleting"
        }
    }

    var subtitle: String {
        switch self {
        case .freeUpSpace: "Delete what you don't need"
        case .organize: "Decide what's worth keeping"
        case .shrink: "Keep everything, use less room"
        }
    }

    /// Tools in this group, in `CleanupTool.allCases` order.
    var tools: [CleanupTool] {
        CleanupTool.allCases.filter { $0.category == self }
    }
}

enum CleanupTool: String, CaseIterable, Identifiable, Hashable, Sendable {
    case duplicates
    case similar
    case screenshots
    case blurry
    case smartCategories
    case largeFiles
    case bursts
    case livePhotos
    case videoCompression
    case photoCompression

    var id: String { rawValue }

    var category: CleanupToolCategory {
        switch self {
        case .duplicates, .similar, .blurry, .largeFiles, .bursts:
            .freeUpSpace
        case .screenshots, .smartCategories:
            .organize
        case .livePhotos, .videoCompression, .photoCompression:
            .shrink
        }
    }

    var name: String {
        switch self {
        case .duplicates: "Duplicates"
        case .similar: "Similar Photos"
        case .screenshots: "Screenshots"
        case .blurry: "Blurry Photos"
        case .smartCategories: "Smart Categories"
        case .largeFiles: "Large Files"
        case .bursts: "Burst Photos"
        case .livePhotos: "Live Photos"
        case .videoCompression: "Video Compression"
        case .photoCompression: "Photo Compression"
        }
    }

    var description: String {
        switch self {
        case .duplicates: "Find exact & visual duplicates"
        case .similar: "Photos taken close together"
        case .screenshots: "Review & clean up screenshots"
        case .blurry: "Out-of-focus & poorly lit"
        case .smartCategories: "Sort photos by content type"
        case .largeFiles: "Biggest files in your library"
        case .bursts: "Clean up burst sequences"
        case .livePhotos: "Convert to stills & save space"
        case .videoCompression: "Compress videos to save space"
        case .photoCompression: "Re-encode photos to save space"
        }
    }

    var icon: String {
        switch self {
        case .duplicates: "doc.on.doc"
        case .similar: "square.on.square"
        case .screenshots: "camera.viewfinder"
        case .blurry: "camera.metering.unknown"
        case .smartCategories: "sparkles.rectangle.stack"
        case .largeFiles: "externaldrive"
        case .bursts: "square.stack.3d.up"
        case .livePhotos: "livephoto"
        case .videoCompression: "video.badge.waveform"
        case .photoCompression: "photo.badge.arrow.down"
        }
    }

    var color: Color {
        switch self {
        case .duplicates: .red
        case .similar: .orange
        case .screenshots: .yellow
        case .blurry: .purple
        case .smartCategories: .pink
        case .largeFiles: .blue
        case .bursts: .teal
        case .livePhotos: .green
        case .videoCompression: .indigo
        case .photoCompression: .mint
        }
    }
}

@MainActor
@ViewBuilder
func cleanupDestinationView(for tool: CleanupTool) -> some View {
    switch tool {
    case .duplicates:
        DuplicateFinderView()
    case .similar:
        SimilarPhotosView()
    case .screenshots:
        ScreenshotCleanerView()
    case .blurry:
        BlurryPhotosView()
    case .smartCategories:
        SmartCategoriesView()
    case .largeFiles:
        LargeFilesView()
    case .bursts:
        BurstCleanerView()
    case .livePhotos:
        LivePhotosConverterView()
    case .videoCompression:
        VideoCompressionView()
    case .photoCompression:
        PhotoCompressionView()
    }
}

/// The last scan result per scan-only tool, kept for this app run, so the
/// Cleanup home shows "12 found" instead of "Not scanned" after a scan.
@MainActor
enum ScanResults {
    private(set) static var counts: [CleanupTool: Int] = [:]

    /// Bumped by `invalidate()` on every observed library change. A scan
    /// captures it when it starts and passes it back to `record`, so a run
    /// that finishes after a change cannot publish pre-change results.
    private(set) static var epoch = 0

    /// Records a count derived from the CURRENT library state — a prune or a
    /// delete just updated the list, so the count is not stale.
    static func record(_ tool: CleanupTool, count: Int) {
        counts[tool] = count
    }

    /// Records a finished scan's result. Dropped when the library changed while
    /// the scan ran (`epoch` no longer current): publishing that count would
    /// advertise results that no longer exist.
    static func record(_ tool: CleanupTool, count: Int, epoch: Int) {
        guard epoch == Self.epoch else { return }
        counts[tool] = count
    }

    /// Expires cached counts when the library changes: a recorded count may
    /// include assets deleted since the scan. The badges fall back to
    /// "Not scanned" until the tool is scanned again. (Library changes are
    /// observed via `LibraryChangeMonitor.generation` — see
    /// `CleanupHomeViewModel.sync(to:)`.)
    static func invalidate() {
        epoch += 1
        counts.removeAll()
    }
}
