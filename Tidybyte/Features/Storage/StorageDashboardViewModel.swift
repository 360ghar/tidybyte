import SwiftUI
import SwiftData

struct StorageCategory: Identifiable, Sendable {
    let id: String
    let name: String
    let bytes: Int64
    let count: Int
    let color: Color
}

/// Unified action for Storage row taps — cleanup tools, swipe sessions, or external URLs.
enum StorageAction: Sendable {
    case cleanup(CleanupTool)
    case swipe(SwipeFilter)
    case url(URL)
}

/// A reclaimable bucket: estimated bytes that could be freed, plus where to tap to do it.
struct ReclaimWin: Identifiable, Sendable {
    let id: String
    let title: String
    let detail: String
    let bytes: Int64               // estimated reclaimable — drives sort + segment width
    let count: Int
    let color: Color
    let icon: String
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

    /// Breakdowns for the "Where Your Storage Goes" card.
    var byYear: [StorageBreakdownBucket] = []
    var bySource: [StorageBreakdownBucket] = []

    private let photoService = PhotoLibraryService()

    /// Assets above this are candidates for the "Large Videos" reclaim win (and its
    /// linked compression tool). Decimal bytes (100 MB); kept as a named constant so
    /// the predicate and the "over N MB" title can't drift apart.
    private static let largeVideoByteThreshold: Int64 = 100 * 1_000_000

    private var hasLoaded = false
    private var syncedGeneration = Int.min
    private var syncTask: Task<Void, Never>?

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
        // reclaimable wins, and by‑year / by‑source breakdowns.
        let assets = await photoService.fetchAssets(filter: .allMedia)
        buildCategories(from: assets)
        buildICloudStatus(from: assets)
        buildWins(from: assets)
        buildBreakdowns(from: assets)

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

    /// Build reclaimable wins using **disjoint** priority bucketing — each asset
    /// contributes to at most one bucket, so the segmented bar and hero total are coherent.
    /// Priority matches user impact: exact‑type tools first, then broad‑review buckets.
    private func buildWins(from assets: [AssetSummary]) {
        var winsMap: [String: (count: Int, bytes: Int64, ids: [String])] = [:]
        var claimed = Set<String>()  // asset IDs already assigned to a higher-priority bucket

        /// Pick unclaimed assets matching `predicate`, record them under `key`, and mark them
        /// claimed. Each asset lands in at most one bucket (priority order below), so
        /// `totalReclaimable` and the segmented-bar widths never double-count. `estimate`
        /// maps total bytes → reclaimable (e.g. Live Photos / videos halved for compression).
        func claim(
            _ key: String,
            matching predicate: (AssetSummary) -> Bool,
            estimate: (Int64) -> Int64 = { $0 }
        ) {
            let picks = assets.filter { predicate($0) && !claimed.contains($0.id) }
            guard !picks.isEmpty else { return }
            winsMap[key] = (
                count: picks.count,
                bytes: estimate(picks.reduce(Int64(0)) { $0 + $1.fileSize }),
                ids: picks.map(\.id)
            )
            claimed.formUnion(picks.map(\.id))
        }

        // 1. Screenshots (highest priority — full reclaimable)
        claim("screenshots", matching: { $0.isScreenshot })

        // 2. Live Photos (~50% reclaimable via conversion to still)
        claim("livePhotos", matching: { $0.isLivePhoto }, estimate: { $0 / 2 })

        // 3. Large Videos — ~50% reclaimable via compression. Threshold is a named
        // constant so the predicate and the "over N MB" title stay in sync.
        claim("largeVideos", matching: { $0.mediaType == .video && $0.fileSize > Self.largeVideoByteThreshold }, estimate: { $0 / 2 })

        // 4. Saved from Apps (exact origin — full reclaimable via swipe review)
        claim("savedFromApps", matching: { $0.assetOrigin == .savedFromApp })

        // 5. Large Files (user‑configurable threshold) — full reclaimable. The
        // threshold comes from the shared `AppPreferences.largeFileThresholdBytes()`,
        // the same value `LargeFilesViewModel.thresholdBytes` uses, so this win always
        // lines up with what the Large Files tool shows.
        // NOTE: because bucketing is disjoint by priority, this count can be *smaller*
        // than what `.cleanup(.largeFiles)` lists — a screenshot / large video / saved-
        // from-app already claimed above is excluded here even though it clears the
        // threshold. The hero total stays coherent (each asset counted once) at the cost
        // of this per-tool undercount; that's the intended tradeoff.
        claim("largeFiles", matching: { $0.fileSize >= AppPreferences.largeFileThresholdBytes() })

        // Convert map to wins, sorted by bytes descending (largest impact first).
        // compactMap drops any key the switch doesn't recognize rather than crashing.
        wins = winsMap.compactMap { key, value -> ReclaimWin? in
            let (title, detail, icon, color, action): (String, String, String, Color, StorageAction)
            switch key {
            case "screenshots":
                title = "\(value.count) screenshots"
                detail = "Free up \(value.bytes.formattedFileSize)"
                icon = "camera.viewfinder"
                color = .yellow
                action = .cleanup(.screenshots)
            case "livePhotos":
                title = "\(value.count) Live Photos"
                detail = "Save ~\(value.bytes.formattedFileSize) by converting"
                icon = "livephoto"
                color = .green
                action = .cleanup(.livePhotos)
            case "largeVideos":
                title = "\(value.count) videos over \(Self.largeVideoByteThreshold / 1_000_000) MB"
                detail = "Compress to save ~\(value.bytes.formattedFileSize)"
                icon = "video.badge.waveform"
                color = .indigo
                action = .cleanup(.videoCompression)
            case "savedFromApps":
                title = "\(value.count) saved from apps"
                detail = "\(value.bytes.formattedFileSize) total"
                icon = "arrow.down.circle"
                color = .orange
                action = .swipe(.customAssetIds(Set(value.ids)))
            case "largeFiles":
                title = "\(value.count) large files"
                detail = "\(value.bytes.formattedFileSize) total"
                icon = "externaldrive"
                color = .purple
                action = .cleanup(.largeFiles)
            default:
                return nil  // unknown key — drop instead of crashing
            }
            return ReclaimWin(
                id: key,
                title: title,
                detail: detail,
                bytes: value.bytes,
                count: value.count,
                color: color,
                icon: icon,
                action: action
            )
        }.sorted { $0.bytes > $1.bytes }
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
        var descriptor = FetchDescriptor<StorageSnapshot>(
            sortBy: [SortDescriptor(\.capturedAt, order: .forward)]
        )
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: .now) ?? .now
        descriptor.predicate = #Predicate { $0.capturedAt >= thirtyDaysAgo }
        snapshots = (try? modelContext.fetch(descriptor)) ?? []
    }
}
