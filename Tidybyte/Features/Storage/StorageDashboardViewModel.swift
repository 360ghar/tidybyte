import SwiftUI
import SwiftData

struct StorageCategory: Identifiable, Sendable {
    let id: String
    let name: String
    let bytes: Int64
    let count: Int
    let color: Color
}

struct CleanupOpportunity: Identifiable {
    let id: String
    let title: String
    let detail: String
    let tool: CleanupTool
    let icon: String
    let color: Color
}

struct DeviceStorageInfo: Sendable {
    var totalCapacity: Int64 = 0
    var availableCapacity: Int64 = 0
    // Clamped: available-for-important-usage can momentarily exceed total due to
    // purgeable-space accounting, which would otherwise render a negative "used".
    var usedCapacity: Int64 { max(0, totalCapacity - availableCapacity) }
}

@Observable
@MainActor
final class StorageDashboardViewModel {
    var categories: [StorageCategory] = []
    var deviceStorage = DeviceStorageInfo()
    var snapshots: [StorageSnapshot] = []
    var opportunities: [CleanupOpportunity] = []
    var isLoading = true
    var iCloudOnlyCount: Int = 0
    var iCloudOnlySize: Int64 = 0
    var localCount: Int = 0

    private let photoService = PhotoLibraryService()

    private var hasLoaded = false
    private var syncedGeneration = Int.min
    private var syncTask: Task<Void, Never>?

    var totalLibrarySize: Int64 {
        categories.reduce(0) { $0 + $1.bytes }
    }

    var totalItemCount: Int {
        categories.reduce(0) { $0 + $1.count }
    }

    /// Locally-resident media footprint (excludes iCloud-only assets, which occupy ~no local disk).
    var onDeviceMediaSize: Int64 { max(0, totalLibrarySize - iCloudOnlySize) }

    /// Estimated device storage TidyByte cannot itemize: apps, the OS, caches, mail, messages, etc.
    /// Clamped to ≥ 0 — purgeable-space accounting can briefly make media exceed measured "used".
    var appsAndOtherSize: Int64 { max(0, deviceStorage.usedCapacity - onDeviceMediaSize) }

    /// Generation-aware entry point driven by `.task(id: monitor.generation)`:
    /// loads on first call, refreshes when the library generation advances, and
    /// no-ops otherwise. The work runs in an unstructured Task so it survives
    /// `.task` cancellation when the user switches tabs mid-fetch; the stored
    /// handle serializes re-entrant callers.
    func sync(to generation: Int, modelContext: ModelContext) async {
        if let syncTask { await syncTask.value }
        guard !(hasLoaded && generation == syncedGeneration) else { return }
        syncedGeneration = generation
        let task = Task {
            if hasLoaded {
                await refresh(modelContext: modelContext)
            } else {
                await load(modelContext: modelContext)
                hasLoaded = true
            }
        }
        syncTask = task
        await task.value
        syncTask = nil
    }

    func load(modelContext: ModelContext) async {
        isLoading = true
        await reload(modelContext: modelContext)
        isLoading = false
    }

    /// Re-fetches all dashboard data WITHOUT flipping `isLoading`, so existing content
    /// stays visible under the pull-to-refresh spinner instead of swapping to skeletons.
    func refresh(modelContext: ModelContext) async {
        await reload(modelContext: modelContext)
    }

    /// Shared data-loading body for both `load` and `refresh`.
    private func reload(modelContext: ModelContext) async {
        // A single library enumeration feeds the category breakdown, iCloud status,
        // and cleanup opportunities (previously each did its own full enumeration).
        let assets = await photoService.fetchAssets(filter: .allMedia)
        buildCategories(from: assets)
        buildICloudStatus(from: assets)
        buildOpportunities(from: assets)

        fetchDeviceStorage()
        fetchSnapshots(modelContext: modelContext)
    }

    private func buildCategories(from assets: [AssetSummary]) {
        var photoBytes: Int64 = 0, photoCount = 0
        var videoBytes: Int64 = 0, videoCount = 0
        var screenshotBytes: Int64 = 0, screenshotCount = 0
        var livePhotoBytes: Int64 = 0, livePhotoCount = 0
        var otherBytes: Int64 = 0, otherCount = 0

        for asset in assets {
            switch asset.mediaType {
            case .photo:
                if asset.isScreenshot {
                    screenshotBytes += asset.fileSize; screenshotCount += 1
                } else if asset.isLivePhoto {
                    livePhotoBytes += asset.fileSize; livePhotoCount += 1
                } else {
                    photoBytes += asset.fileSize; photoCount += 1
                }
            case .video:
                videoBytes += asset.fileSize; videoCount += 1
            default:
                otherBytes += asset.fileSize; otherCount += 1
            }
        }

        categories = [
            StorageCategory(id: "photos", name: "Photos", bytes: photoBytes, count: photoCount, color: .blue),
            StorageCategory(id: "videos", name: "Videos", bytes: videoBytes, count: videoCount, color: .purple),
            StorageCategory(id: "screenshots", name: "Screenshots", bytes: screenshotBytes, count: screenshotCount, color: .yellow),
            StorageCategory(id: "livePhotos", name: "Live Photos", bytes: livePhotoBytes, count: livePhotoCount, color: .teal),
            StorageCategory(id: "other", name: "Other", bytes: otherBytes, count: otherCount, color: .gray),
        ].filter { $0.bytes > 0 }
    }

    private func buildICloudStatus(from assets: [AssetSummary]) {
        let iCloudOnly = assets.filter { !$0.isLocallyAvailable }
        iCloudOnlyCount = iCloudOnly.count
        iCloudOnlySize = iCloudOnly.reduce(0) { $0 + $1.fileSize }
        localCount = assets.count - iCloudOnly.count
    }

    private func buildOpportunities(from assets: [AssetSummary]) {
        var opps: [CleanupOpportunity] = []

        let screenshots = assets.filter(\.isScreenshot)
        if !screenshots.isEmpty {
            let size = screenshots.reduce(Int64(0)) { $0 + $1.fileSize }
            opps.append(CleanupOpportunity(
                id: "screenshots",
                title: "\(screenshots.count) screenshots",
                detail: "Free up \(size.formattedFileSize)",
                tool: .screenshots,
                icon: "camera.viewfinder",
                color: .yellow
            ))
        }

        let livePhotos = assets.filter(\.isLivePhoto)
        if !livePhotos.isEmpty {
            let size = livePhotos.reduce(Int64(0)) { $0 + $1.fileSize } / 2
            opps.append(CleanupOpportunity(
                id: "livePhotos",
                title: "\(livePhotos.count) Live Photos",
                detail: "Save ~\(size.formattedFileSize) by converting",
                tool: .livePhotos,
                icon: "livephoto",
                color: .green
            ))
        }

        let largeVideos = assets.filter { $0.mediaType == .video && $0.fileSize > 100_000_000 }
        if !largeVideos.isEmpty {
            let size = largeVideos.reduce(Int64(0)) { $0 + $1.fileSize }
            opps.append(CleanupOpportunity(
                id: "largeVideos",
                title: "\(largeVideos.count) videos over 100 MB",
                detail: "\(size.formattedFileSize) total",
                tool: .videoCompression,
                icon: "video.badge.waveform",
                color: .indigo
            ))
        }

        opportunities = opps
    }

    private func fetchDeviceStorage() {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        do {
            let values = try url.resourceValues(forKeys: [
                .volumeTotalCapacityKey,
                .volumeAvailableCapacityForImportantUsageKey
            ])
            if let total = values.volumeTotalCapacity {
                deviceStorage.totalCapacity = Int64(total)
            }
            if let available = values.volumeAvailableCapacityForImportantUsage {
                deviceStorage.availableCapacity = available
            }
        } catch {
            AppLog.app.error("Failed to read device storage: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func fetchSnapshots(modelContext: ModelContext) {
        var descriptor = FetchDescriptor<StorageSnapshot>(
            sortBy: [SortDescriptor(\.capturedAt, order: .forward)]
        )
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: .now) ?? .now
        descriptor.predicate = #Predicate { $0.capturedAt >= thirtyDaysAgo }
        snapshots = (try? modelContext.fetch(descriptor)) ?? []
    }
}
