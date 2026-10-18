import SwiftUI

/// Groups cleanup tools by what the user is trying to achieve.
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

    /// Localized through `L10n`, keyed on the English text.
    ///
    /// English-as-key is deliberate: Xcode's String Catalog extractor already
    /// keys every `Text("...")` literal on its English text, so using the same
    /// convention here means one catalog, one key namespace, and no parallel
    /// table of symbolic keys to keep in sync.
    var title: String {
        switch self {
        case .freeUpSpace: L10n.string("Free Up Space")
        case .organize: L10n.string("Review & Organize")
        case .shrink: L10n.string("Reclaim Without Deleting")
        }
    }

    var subtitle: String {
        switch self {
        case .freeUpSpace: L10n.string("Delete what you don't need")
        case .organize: L10n.string("Decide what's worth keeping")
        case .shrink: L10n.string("Keep everything, use less room")
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
    case screenRecordings
    case chatMedia
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
        case .duplicates, .similar, .blurry, .largeFiles, .bursts, .screenRecordings:
            .freeUpSpace
        case .screenshots, .smartCategories, .chatMedia:
            .organize
        case .livePhotos, .videoCompression, .photoCompression:
            .shrink
        }
    }

    /// The catalog key behind `name`, which is the English text.
    ///
    /// Separate from `name` because a navigation title has to be re-resolved on
    /// a language change rather than handed a value that was computed once; see
    /// `localizedNavigationTitle`.
    var nameKey: String {
        switch self {
        case .duplicates: L10n.key("Duplicates")
        case .similar: L10n.key("Similar Photos")
        case .screenshots: L10n.key("Screenshots")
        case .screenRecordings: L10n.key("Screen Recordings")
        case .chatMedia: L10n.key("Chat Media")
        case .blurry: L10n.key("Blurry Photos")
        case .smartCategories: L10n.key("Smart Categories")
        case .largeFiles: L10n.key("Large Files")
        case .bursts: L10n.key("Burst Photos")
        case .livePhotos: L10n.key("Live Photos")
        case .videoCompression: L10n.key("Video Compression")
        case .photoCompression: L10n.key("Photo Compression")
        }
    }

    var name: String { L10n.string(nameKey) }

    var description: String {
        switch self {
        case .duplicates: L10n.string("Find exact & visual duplicates")
        case .similar: L10n.string("Photos taken close together")
        case .screenshots: L10n.string("Review & clean up screenshots")
        case .screenRecordings: L10n.string("Review recorded videos")
        case .chatMedia: L10n.string("Review media in chat albums")
        case .blurry: L10n.string("Out-of-focus & poorly lit")
        case .smartCategories: L10n.string("Sort photos by content type")
        case .largeFiles: L10n.string("Biggest files in your library")
        case .bursts: L10n.string("Clean up burst sequences")
        case .livePhotos: L10n.string("Convert to stills & save space")
        case .videoCompression: L10n.string("Compress videos to save space")
        case .photoCompression: L10n.string("Re-encode photos to save space")
        }
    }

    var icon: String {
        switch self {
        case .duplicates: "doc.on.doc"
        case .similar: "square.on.square"
        case .screenshots: "camera.viewfinder"
        case .screenRecordings: "record.circle"
        case .chatMedia: "bubble.left.and.bubble.right"
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
        case .screenRecordings: .indigo
        case .chatMedia: .green
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
    case .screenRecordings, .chatMedia:
        MediaCleanerView(tool: tool)
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
    /// Finished-scan results, stamped with the epoch they were published in.
    /// Expired on library change: they may name assets deleted since the scan.
    private static var scanCounts: [CleanupTool: (count: Int, epoch: Int)] = [:]

    /// Counts derived from the CURRENT list — a prune or a delete just updated
    /// it, so the count is not stale. These survive library changes, including
    /// the change notification a tool's own delete triggers: wiping them would
    /// flip the badge to "Not scanned" right after a successful cleanup.
    /// Externally deleted assets are corrected the same way, when each tool's
    /// prune re-records its derived count on the next observed generation.
    private static var derivedCounts: [CleanupTool: Int] = [:]

    /// A derived count wins over a scan result: it came from the live list,
    /// not from a snapshot that predates it.
    static var counts: [CleanupTool: Int] {
        var merged: [CleanupTool: Int] = [:]
        for (tool, entry) in scanCounts where entry.epoch == epoch {
            merged[tool] = entry.count
        }
        for (tool, count) in derivedCounts {
            merged[tool] = count
        }
        return merged
    }

    /// Bumped on every observed library change. A scan captures it when it
    /// starts and passes it back to `record`, so a run that finishes after a
    /// change cannot publish pre-change results.
    private(set) static var epoch = 0

    /// The generation `libraryChanged(to:)` last handled, so the epoch advances
    /// exactly once per generation no matter how many screens observe it.
    private static var lastHandledGeneration = 0

    /// Records a count derived from the CURRENT library state — a prune or a
    /// delete just updated the list, so the count is not stale.
    static func record(_ tool: CleanupTool, count: Int) {
        derivedCounts[tool] = count
    }

    /// Records a finished scan's result. Dropped when the library changed while
    /// the scan ran (`epoch` no longer current): publishing that count would
    /// advertise results that no longer exist.
    static func record(_ tool: CleanupTool, count: Int, epoch: Int) {
        guard epoch == Self.epoch else { return }
        scanCounts[tool] = (count, epoch)
    }

    /// The library changed. Expires finished-scan results and advances the
    /// epoch, so every in-flight scan's captured epoch goes stale and its
    /// result is dropped — but derived counts survive, because they describe
    /// the list as it stands after the change. Called from the
    /// change-observation path (`LibraryChangeMonitor`), not from a screen:
    /// screen ownership would clear counts that are still valid whenever
    /// SwiftUI recreates that screen's view model, and a scan could publish a
    /// pre-change result if its screen never saw the change.
    static func libraryChanged(to generation: Int) {
        guard generation != lastHandledGeneration else { return }
        lastHandledGeneration = generation
        epoch += 1
        scanCounts.removeAll()
    }

    /// Expires finished-scan results when the library changes: a recorded scan
    /// count may include assets deleted since the scan. Derived counts survive;
    /// the badges fall back to "Not scanned" only for tools with neither.
    /// Changes are observed via `LibraryChangeMonitor`, which calls
    /// `libraryChanged(to:)`.
    static func invalidate() {
        epoch += 1
        scanCounts.removeAll()
    }

    static func permissionChanged() {
        invalidate()
        derivedCounts.removeAll()
    }

    /// Test-only reset for the shared static state (epoch, generation guard,
    /// and both stores), so order-independence tests don't leak generations
    /// into each other.
    static func resetForTesting() {
        scanCounts.removeAll()
        derivedCounts.removeAll()
        epoch = 0
        lastHandledGeneration = 0
    }
}
