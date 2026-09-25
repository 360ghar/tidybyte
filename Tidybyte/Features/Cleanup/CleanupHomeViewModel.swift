import SwiftUI

struct CleanupToolInfo: Identifiable {
    let tool: CleanupTool
    var count: Int?
    var isLoading: Bool = true

    var id: CleanupTool { tool }
    var name: String { tool.name }
    var description: String { tool.description }
    var icon: String { tool.icon }
    var color: Color { tool.color }
    var category: CleanupToolCategory { tool.category }
}

/// Result of the single library pass that feeds the cleanup home.
///
/// Extracted as a pure function so the hero's disjointness rule — a large
/// screenshot must not be counted twice — is unit-tested instead of buried in an
/// async enumeration.
struct CleanupLibraryRollup: Equatable {
    var screenshots = 0
    var livePhotos = 0
    var videos = 0
    var largeFiles = 0
    var compressiblePhotos = 0
    /// Badge counts: only items worth the tool's time. Videos over the
    /// large-video threshold, and non-HEIC photos over 2 MB (HEIC rarely
    /// shrinks).
    var largeVideos = 0
    var photoCompressionCandidates = 0

    static let photoCompressionMinBytes: Int64 = 2 * 1_000_000

    /// The app-wide "up to X you could free" total. Same `ReclaimBucketer`
    /// figure as the Storage tab and the widget, so the number never differs
    /// between screens.
    var reclaimableBytes: Int64 = 0

    /// Item count that matches `reclaimableBytes`.
    var reclaimableItemCount = 0

    static func compute(from assets: [AssetSummary], thresholdBytes: Int64, excludingCompressedCopies: Set<String> = []) -> CleanupLibraryRollup {
        var rollup = CleanupLibraryRollup()

        for asset in assets {
            if asset.isScreenshot { rollup.screenshots += 1 }

            if asset.isLivePhoto {
                rollup.livePhotos += 1
            } else if asset.mediaType == .photo {
                rollup.compressiblePhotos += 1
                // Same rule as the tool's list, so the badge matches it.
                if PhotoCompressionViewModel.isCandidate(asset, excluding: excludingCompressedCopies, showAll: false) {
                    rollup.photoCompressionCandidates += 1
                }
            }

            if asset.mediaType == .video {
                rollup.videos += 1
                if asset.fileSize > ReclaimBucketer.largeVideoByteThreshold { rollup.largeVideos += 1 }
            }

            if asset.fileSize >= thresholdBytes { rollup.largeFiles += 1 }
        }

        let buckets = ReclaimBucketer.buckets(from: assets, largeFileThresholdBytes: thresholdBytes)
        rollup.reclaimableBytes = buckets.reduce(Int64(0)) { $0 + $1.bytes }
        rollup.reclaimableItemCount = buckets.reduce(0) { $0 + $1.count }

        return rollup
    }
}

@Observable
@MainActor
final class CleanupHomeViewModel {
    var tools: [CleanupToolInfo] = CleanupTool.allCases.map { CleanupToolInfo(tool: $0) }
    private(set) var hasLoadedCounts = false

    /// Size of the screenshots plus the over-threshold non-screenshot files,
    /// measured during the pass the badges already do. The hero renders it as
    /// "in files worth a look" rather than "you will free this" — the four
    /// scan-only tools need a real scan before a number about them would be
    /// honest.
    private(set) var reclaimableBytes: Int64 = 0
    private(set) var reclaimableItemCount = 0


    private let photoService = PhotoLibraryService.shared

    func info(for tool: CleanupTool) -> CleanupToolInfo? {
        tools.first { $0.tool == tool }
    }

    private var syncedGeneration = Int.min
    /// Tail of a task chain. Every enumeration enqueues behind the previous
    /// one, so concurrent callers (pull-to-refresh + generation sync) can never
    /// enumerate the library simultaneously (A4). Finished handles are left in
    /// place deliberately — awaiting a completed task returns immediately, and
    /// never clearing avoids any who-owns-the-slot race.
    private var syncTask: Task<Void, Never>?

    /// Runs `work` after every previously-enqueued work item completes.
    private func enqueue(_ work: @escaping @MainActor () async -> Void) async {
        let previous = syncTask
        let task = Task {
            await previous?.value
            await work()
        }
        syncTask = task
        await task.value
    }

    /// Generation-aware entry point driven by `.task(id: monitor.generation)`:
    /// loads on first call, refreshes when the library generation advances, and
    /// no-ops otherwise. Work survives `.task` cancellation when the user
    /// switches tabs mid-fetch.
    func sync(to generation: Int, excludingCompressedCopies: @escaping @MainActor () -> Set<String> = { [] }) async {
        guard !(hasLoadedCounts && generation == syncedGeneration) else { return }
        // The scan cache is expired where the change is observed
        // (`ScanResults.libraryChanged`, driven by `LibraryChangeMonitor`), so
        // by the time this runs for a new generation the counts have already
        // been cleared. Re-applying here keeps stale badges off screen while
        // `loadCounts` waits behind the serialized queue.
        applyScanResults()
        syncedGeneration = generation
        await enqueue {
            await self.loadCounts(excludingCompressedCopies: excludingCompressedCopies())
            self.hasLoadedCounts = true
        }
    }

    /// Pull-to-refresh. Serialized through the same chain as `sync(to:)` (A4).
    func refreshCounts(excludingCompressedCopies: Set<String> = []) async {
        await enqueue {
            await self.loadCounts(excludingCompressedCopies: excludingCompressedCopies)
        }
    }

    private func loadCounts(excludingCompressedCopies: Set<String> = []) async {
        // ONE all-media pass feeds screenshots, live photos, videos, large
        // files, photo compression and bursts (E9: was five full enumerations,
        // each materializing AssetSummary arrays with per-asset resource I/O
        // just to call `.count`).
        let allAssets = await photoService.fetchAssets(filter: .allMedia)

        let threshold = AppPreferences.largeFileThresholdBytes()
        let rollup = CleanupLibraryRollup.compute(from: allAssets, thresholdBytes: threshold, excludingCompressedCopies: excludingCompressedCopies)

        reclaimableBytes = rollup.reclaimableBytes
        reclaimableItemCount = rollup.reclaimableItemCount

        updateTool(.screenshots, count: rollup.screenshots)
        updateTool(.livePhotos, count: rollup.livePhotos)
        updateTool(.videoCompression, count: rollup.largeVideos)
        updateTool(.largeFiles, count: rollup.largeFiles)
        updateTool(.photoCompression, count: rollup.photoCompressionCandidates)

        // Bursts: `.allMedia` already includes every burst frame. The badge
        // counts removable frames (all but one per burst), like the tool.
        let burstGroups = Dictionary(grouping: allAssets.filter { $0.burstIdentifier != nil }) { $0.burstIdentifier ?? "" }
            .filter { $0.value.count > 1 }
        // Same set the tool's Auto-Clean uses: all but the keeper, never a
        // favorite.
        let removableFrames = BurstCleanerViewModel.rebuildGroups(from: burstGroups)
            .reduce(0) { $0 + BurstCleanerViewModel.suggestedIds(in: $1).count }
        updateTool(.bursts, count: removableFrames)

        applyScanResults()
    }

    /// Duplicates, similar, blurry and smart categories cost a full scan to
    /// count: show the last scan's result, or nil ("Not scanned").
    func applyScanResults() {
        for tool in [CleanupTool.duplicates, .similar, .blurry, .smartCategories] {
            updateTool(tool, count: ScanResults.counts[tool], isLoading: false)
        }
    }

    private func updateTool(_ tool: CleanupTool, count: Int?, isLoading: Bool = false) {
        if let index = tools.firstIndex(where: { $0.tool == tool }) {
            tools[index].count = count
            tools[index].isLoading = isLoading
        }
    }
}
