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
}

@Observable
@MainActor
final class CleanupHomeViewModel {
    var tools: [CleanupToolInfo] = CleanupTool.allCases.map { CleanupToolInfo(tool: $0) }
    private(set) var hasLoadedCounts = false

    private let photoService = PhotoLibraryService()

    private var syncedGeneration = Int.min
    private var syncTask: Task<Void, Never>?

    /// Generation-aware entry point driven by `.task(id: monitor.generation)`:
    /// loads on first call, refreshes when the library generation advances, and
    /// no-ops otherwise. The work runs in an unstructured Task so it survives
    /// `.task` cancellation when the user switches tabs mid-fetch; the stored
    /// handle serializes re-entrant callers.
    func sync(to generation: Int) async {
        if let syncTask { await syncTask.value }
        guard !(hasLoadedCounts && generation == syncedGeneration) else { return }
        syncedGeneration = generation
        let task = Task {
            await loadCounts()
            hasLoadedCounts = true
        }
        syncTask = task
        await task.value
        syncTask = nil
    }

    func refreshCounts() async {
        await loadCounts()
    }

    private func loadCounts() async {
        // Load counts for each tool asynchronously
        async let screenshotCount = photoService.fetchScreenshots().count
        async let livePhotoCount = photoService.fetchLivePhotos().count
        async let burstGroups = photoService.fetchBurstPhotos()
        async let videoCount = photoService.fetchAssetsByMediaType(.video).count

        let screenshots = await screenshotCount
        let livePhotos = await livePhotoCount
        let bursts = await Self.burstBadgeCount(from: burstGroups)
        let videos = await videoCount

        updateTool(.screenshots, count: screenshots)
        updateTool(.livePhotos, count: livePhotos)
        updateTool(.bursts, count: bursts)
        updateTool(.videoCompression, count: videos)

        // Large files + photo compression — both derived from the single
        // all-media fetch to avoid extra enumerations.
        let allAssets = await photoService.fetchAssets(filter: .allMedia)
        // APP-06: single shared threshold source — no manual mb → bytes math.
        let threshold = AppPreferences.largeFileThresholdBytes()
        let largeCount = allAssets.filter { $0.fileSize >= threshold }.count
        updateTool(.largeFiles, count: largeCount)

        let compressiblePhotos = allAssets.filter { $0.mediaType == .photo && !$0.isLivePhoto }.count
        updateTool(.photoCompression, count: compressiblePhotos)

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

    nonisolated static func burstBadgeCount(from groups: [String: [AssetSummary]]) -> Int {
        groups.count
    }
}
