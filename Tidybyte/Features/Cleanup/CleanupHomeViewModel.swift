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

    /// Bytes the user could delete outright, from two *disjoint* sets: every
    /// screenshot, plus every file over the threshold that is not a screenshot.
    var reclaimableBytes: Int64 = 0

    /// Item count that matches `reclaimableBytes`.
    var reclaimableItemCount = 0

    static func compute(from assets: [AssetSummary], thresholdBytes: Int64) -> CleanupLibraryRollup {
        var rollup = CleanupLibraryRollup()

        for asset in assets {
            if asset.isScreenshot {
                rollup.screenshots += 1
                rollup.reclaimableBytes += asset.fileSize
                rollup.reclaimableItemCount += 1
            }

            if asset.isLivePhoto {
                rollup.livePhotos += 1
            } else if asset.mediaType == .photo {
                rollup.compressiblePhotos += 1
            }

            if asset.mediaType == .video { rollup.videos += 1 }

            if asset.fileSize >= thresholdBytes {
                rollup.largeFiles += 1
                // Excluded from the reclaimable total so a large screenshot is
                // never counted twice. The Large Files *badge* still counts it,
                // because that badge answers its own, narrower question.
                if !asset.isScreenshot {
                    rollup.reclaimableBytes += asset.fileSize
                    rollup.reclaimableItemCount += 1
                }
            }
        }

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

    /// The threshold rendered with the same formatter the Large Files rows use,
    /// so the hero's footnote can't disagree with that tool's list.
    private(set) var largeFileThresholdLabel = ""

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
    func sync(to generation: Int) async {
        guard !(hasLoadedCounts && generation == syncedGeneration) else { return }
        syncedGeneration = generation
        await enqueue {
            await self.loadCounts()
            self.hasLoadedCounts = true
        }
    }

    /// Pull-to-refresh. Serialized through the same chain as `sync(to:)` (A4).
    func refreshCounts() async {
        await enqueue {
            await self.loadCounts()
        }
    }

    private func loadCounts() async {
        // ONE all-media pass feeds screenshots, live photos, videos, large
        // files, and photo compression (E9: was five full enumerations, each
        // materializing AssetSummary arrays with per-asset resource I/O just
        // to call `.count`). Only bursts needs its own query.
        let allAssets = await photoService.fetchAssets(filter: .allMedia)

        let threshold = AppPreferences.largeFileThresholdBytes()
        let rollup = CleanupLibraryRollup.compute(from: allAssets, thresholdBytes: threshold)

        reclaimableBytes = rollup.reclaimableBytes
        reclaimableItemCount = rollup.reclaimableItemCount
        largeFileThresholdLabel = threshold.formattedFileSize

        updateTool(.screenshots, count: rollup.screenshots)
        updateTool(.livePhotos, count: rollup.livePhotos)
        updateTool(.videoCompression, count: rollup.videos)
        updateTool(.largeFiles, count: rollup.largeFiles)
        updateTool(.photoCompression, count: rollup.compressiblePhotos)

        // Bursts: grouped fetch — the one dedicated enumeration.
        let burstGroups = await photoService.fetchBurstPhotos()
        updateTool(.bursts, count: burstGroups.count)

        // Duplicates/similar/blurry/smartCategories - too expensive to scan, show
        // nil (will display "Scan")
        updateTool(.duplicates, count: nil, isLoading: false)
        updateTool(.similar, count: nil, isLoading: false)
        updateTool(.blurry, count: nil, isLoading: false)
        updateTool(.smartCategories, count: nil, isLoading: false)
    }

    private func updateTool(_ tool: CleanupTool, count: Int?, isLoading: Bool = false) {
        if let index = tools.firstIndex(where: { $0.tool == tool }) {
            tools[index].count = count
            tools[index].isLoading = isLoading
        }
    }
}
