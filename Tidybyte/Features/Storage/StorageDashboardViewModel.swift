import SwiftUI
import SwiftData

struct StorageCategory: Identifiable, Sendable {
    let id: String
    let name: String
    let bytes: Int64
    let count: Int
    let color: Color
}

/// Unified action for Storage row taps — cleanup tools or swipe sessions.
enum StorageAction: Sendable {
    case cleanup(CleanupTool)
    case swipe(SwipeFilter)
    case activity
}

/// A reclaimable bucket: estimated bytes that could be freed, plus where to tap to do it.
struct ReclaimWin: Identifiable, Sendable {
    let id: String
    let title: String
    let detail: String
    let bytes: Int64               // estimated reclaimable — drives sort + segment width
    let count: Int
    let color: Color
    let action: StorageAction
}

/// A bucket for by‑year / by‑source breakdowns, carrying asset IDs for deep‑linking.
struct StorageBreakdownBucket: Identifiable, Sendable {
    let id: String                 // e.g. "2019" or "savedFromApp"
    let label: String
    let bytes: Int64
    let count: Int
    let assetIds: [String]         // for .swipe(.customAssetIds(...)) deep-link
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
    var isLoading = true
    var iCloudOnlyCount: Int = 0
    var iCloudOnlySize: Int64 = 0
    var localCount: Int = 0

    /// Reclaimable wins — disjoint buckets sorted largest-first.
    var wins: [ReclaimWin] = []

    /// Lifetime cleanup savings, mirrored from the ledger for the "Your
    /// Savings" entry card (reconciled on every load).
    var lifetimeFreedBytes: Int64 = 0
    var lifetimeItemCount: Int = 0

    /// Breakdowns for the "Where Your Storage Goes" card.
    var byYear: [StorageBreakdownBucket] = []
    var bySource: [StorageBreakdownBucket] = []

    private let photoService = PhotoLibraryService.shared

    private var hasLoaded = false
    private var syncedGeneration = Int.min
    /// Tail of a task chain. Every enumeration enqueues behind the previous
    /// one, so concurrent callers (pull-to-refresh + generation sync) can never
    /// enumerate the library simultaneously (A4). Finished handles are left in
    /// place deliberately — awaiting a completed task returns immediately.
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

    var totalLibrarySize: Int64 {
        categories.reduce(0) { $0 + $1.bytes }
    }

    var totalItemCount: Int {
        categories.reduce(0) { $0 + $1.count }
    }

    /// Total estimated reclaimable bytes across all wins.
    var totalReclaimable: Int64 {
        wins.reduce(0) { $0 + $1.bytes }
    }

    /// Locally-resident media footprint (excludes iCloud-only assets, which occupy ~no local disk).
    var onDeviceMediaSize: Int64 { max(0, totalLibrarySize - iCloudOnlySize) }

    /// Estimated device storage TidyByte cannot itemize: apps, the OS, caches, mail, messages, etc.
    /// Clamped to ≥ 0 — purgeable-space accounting can briefly make media exceed measured "used".
    var appsAndOtherSize: Int64 { max(0, deviceStorage.usedCapacity - onDeviceMediaSize) }

    /// Generation-aware entry point driven by `.task(id: monitor.generation)`:
    /// loads on first call, refreshes when the library generation advances, and
    /// no-ops otherwise. Work runs in an unstructured Task so it survives
    /// `.task` cancellation when the user switches tabs mid-fetch.
    func sync(to generation: Int, modelContext: ModelContext) async {
        guard !(hasLoaded && generation == syncedGeneration) else { return }
        syncedGeneration = generation
        if hasLoaded {
            await enqueue { await self.reload(modelContext: modelContext) }
        } else {
            await enqueue {
                await self.load(modelContext: modelContext)
                self.hasLoaded = true
            }
        }
    }

    func load(modelContext: ModelContext) async {
        isLoading = true
        await reload(modelContext: modelContext)
        isLoading = false
    }

    /// Re-fetches all dashboard data WITHOUT flipping `isLoading`, so existing content
    /// stays visible under the pull-to-refresh spinner instead of swapping to skeletons.
    /// APP-16/A4: serialized through the same task chain as `sync(to:)` so a
    /// pull-to-refresh can never enumerate the library concurrently with a
    /// generation-driven reload.
    func refresh(modelContext: ModelContext) async {
        await enqueue { await self.reload(modelContext: modelContext) }
    }

    /// Shared data-loading body for both `load` and `refresh`.
    private func reload(modelContext: ModelContext) async {
        // A single library enumeration feeds the category breakdown, iCloud status,
        // reclaimable wins, and by‑year / by‑source breakdowns.
        let assets = await photoService.fetchAssets(filter: .allMedia)
        buildCategories(from: assets)
        buildICloudStatus(from: assets)
        buildWins(from: assets)
        buildBreakdowns(from: assets)

        fetchDeviceStorage()
        fetchSnapshots(modelContext: modelContext)
        fetchLifetimeSavings(modelContext: modelContext)
    }

    /// Reads the lifetime cleanup totals for the "Your Savings" card, and
    /// reconciles the cached copy on the way through (this screen is the entry
    /// point to Activity, so the two must agree the moment it loads).
    private func fetchLifetimeSavings(modelContext: ModelContext) {
        let summary = CleanupLedger.shared.refreshCache(modelContext: modelContext)
        lifetimeFreedBytes = summary.lifetimeFreedBytes
        lifetimeItemCount = summary.lifetimeItemCount
    }

    private func buildCategories(from assets: [AssetSummary]) {
        let stats = MediaLibraryStats.build(
            from: assets,
            largeFileThresholdBytes: AppPreferences.largeFileThresholdBytes()
        )
        categories = Self.makeCategories(from: stats)
    }

    /// Pure mapping from shared stats → dashboard categories (testable without
    /// PhotoKit; the widget/scan use the same `MediaLibraryStats` builder).
    nonisolated static func makeCategories(from stats: MediaLibraryStats) -> [StorageCategory] {
        [
            StorageCategory(id: "photos", name: "Photos", bytes: stats.photoBytes, count: stats.photoCount, color: .blue),
            StorageCategory(id: "videos", name: "Videos", bytes: stats.videoBytes, count: stats.videoCount, color: .purple),
            StorageCategory(id: "screenshots", name: "Screenshots", bytes: stats.screenshotBytes, count: stats.screenshotCount, color: .yellow),
            StorageCategory(id: "livePhotos", name: "Live Photos", bytes: stats.livePhotoBytes, count: stats.livePhotoCount, color: .teal),
            StorageCategory(id: "other", name: "Other", bytes: stats.otherBytes, count: stats.otherCount, color: .gray),
        ].filter { $0.bytes > 0 }
    }

    private func buildICloudStatus(from assets: [AssetSummary]) {
        let iCloudOnly = assets.filter { !$0.isLocallyAvailable }
        iCloudOnlyCount = iCloudOnly.count
        iCloudOnlySize = iCloudOnly.reduce(0) { $0 + $1.fileSize }
        localCount = assets.count - iCloudOnly.count
    }

    /// Build reclaimable wins using the SHARED disjoint priority bucketing
    /// (`ReclaimBucketer`) — the same buckets that drive the widget's
    /// reclaimable figure, so the two surfaces can never disagree (APP-04).
    /// Each asset contributes to at most one bucket, so the segmented bar and
    /// hero total are coherent.
    private func buildWins(from assets: [AssetSummary]) {
        let buckets = ReclaimBucketer.buckets(
            from: assets,
            largeFileThresholdBytes: AppPreferences.largeFileThresholdBytes()
        )
        wins = Self.makeWins(buckets: buckets)
    }

    /// Pure mapping from disjoint reclaim buckets → wins (testable without
    /// PhotoKit). `compactMap` drops any key the switch doesn't recognize
    /// rather than crashing.
    nonisolated static func makeWins(buckets: [ReclaimBucketer.Bucket]) -> [ReclaimWin] {
        buckets.compactMap { bucket -> ReclaimWin? in
            let (title, detail, color, action): (String, String, Color, StorageAction)
            switch bucket.key {
            case "screenshots":
                title = "\(bucket.count) screenshots"
                detail = "Free up \(bucket.bytes.formattedFileSize)"
                color = .yellow
                action = .cleanup(.screenshots)
            case "livePhotos":
                title = "\(bucket.count) Live Photos"
                detail = "Save ~\(bucket.bytes.formattedFileSize) by converting"
                color = .green
                action = .cleanup(.livePhotos)
            case "largeVideos":
                title = "\(bucket.count) videos over \(ReclaimBucketer.largeVideoByteThreshold / 1_000_000) MB"
                detail = "Compress to save ~\(bucket.bytes.formattedFileSize)"
                color = .indigo
                action = .cleanup(.videoCompression)
            case "savedFromApps":
                title = "\(bucket.count) saved from apps"
                detail = "\(bucket.bytes.formattedFileSize) total"
                color = .orange
                action = .swipe(.customAssetIds(Set(bucket.ids)))
            case "largeFiles":
                title = "\(bucket.count) large files"
                detail = "\(bucket.bytes.formattedFileSize) total"
                color = .purple
                action = .cleanup(.largeFiles)
            default:
                return nil  // unknown key — drop instead of crashing
            }
            return ReclaimWin(
                id: bucket.key,
                title: title,
                detail: detail,
                bytes: bucket.bytes,
                count: bucket.count,
                color: color,
                action: action
            )
        }
        .sorted { $0.bytes > $1.bytes }
    }

    /// Build by‑year and by‑source breakdowns for the "Where Your Storage Goes" card.
    ///
    /// Each bucket retains the asset IDs it contains so a row tap can deep-link into a
    /// Swipe session via `.swipe(.customAssetIds(...))`. Storing just the ID strings (not
    /// full `AssetSummary`s, and not re-fetching on tap) is the lean option: re-querying at
    /// tap time would re-introduce the per-action full-library enumeration that the
    /// single-pass `reload` deliberately collapsed. The cost is that the dashboard holds
    /// roughly one library's worth of ID strings across these two maps (plus the
    /// `savedFromApps` win); acceptable for a transient screen. `AppNavigation.showSwipeSession`
    /// logs the routed payload size so a stall on a very large bucket is diagnosable.
    private func buildBreakdowns(from assets: [AssetSummary]) {
        var byYearMap: [Int: (bytes: Int64, count: Int, ids: [String])] = [:]
        var bySourceMap: [AssetOrigin: (bytes: Int64, count: Int, ids: [String])] = [:]
        let calendar = Calendar.current

        for asset in assets {
            // Group by year (missing dates → "Unknown")
            let year: Int
            if let date = asset.creationDate {
                year = calendar.component(.year, from: date)
            } else {
                year = 0  // 0 represents "Unknown"
            }

            var existing = byYearMap[year] ?? (bytes: 0, count: 0, ids: [])
            existing.bytes += asset.fileSize
            existing.count += 1
            existing.ids.append(asset.id)
            byYearMap[year] = existing

            // Group by asset origin
            var originExisting = bySourceMap[asset.assetOrigin] ?? (bytes: 0, count: 0, ids: [])
            originExisting.bytes += asset.fileSize
            originExisting.count += 1
            originExisting.ids.append(asset.id)
            bySourceMap[asset.assetOrigin] = originExisting
        }

        // Convert by‑year to buckets, sorted most recent first (descending year),
        // with "Unknown" (year 0) last. Sort on the Int key directly rather than
        // round-tripping through the label string, so there's no parse + `?? 0` fallback.
        byYear = byYearMap.sorted { lhs, rhs in
            if lhs.key == 0 { return false }  // "Unknown" sorts after everything
            if rhs.key == 0 { return true }
            return lhs.key > rhs.key
        }.map { year, value in
            let label = year == 0 ? "Unknown" : "\(year)"
            return StorageBreakdownBucket(
                id: label,
                label: label,
                bytes: value.bytes,
                count: value.count,
                assetIds: value.ids
            )
        }

        // Convert by‑source to buckets, sorted by bytes descending
        bySource = bySourceMap.map { origin, value in
            let label: String
            switch origin {
            case .camera:
                label = "Camera"
            case .savedFromApp:
                label = "Saved from Apps"
            case .screenshot:
                label = "Screenshots"
            case .unknown:
                label = "Unknown"
            }
            return StorageBreakdownBucket(
                id: origin.rawValue,
                label: label,
                bytes: value.bytes,
                count: value.count,
                assetIds: value.ids
            )
        }.sorted { $0.bytes > $1.bytes }
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
        let descriptor = FetchDescriptor<StorageSnapshot>()
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: .now) ?? .now
        snapshots = ((try? modelContext.fetch(descriptor)) ?? [])
            .filter { $0.capturedAt >= thirtyDaysAgo }
            .sorted { $0.capturedAt < $1.capturedAt }
    }
}
