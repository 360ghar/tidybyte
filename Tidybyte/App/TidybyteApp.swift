import SwiftUI
import SwiftData
import Photos
import WidgetKit

@main
struct TidybyteApp: App {
    let modelContainer: ModelContainer
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let schema = Schema([
            SwipeRecord.self,
            CompressionRecord.self,
            StorageSnapshot.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            modelContainer = try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            // A corrupted or migration-incompatible store shouldn't crash the app on
            // launch. Fall back to an in-memory store *using the real schema* so the
            // history models can still be inserted/queried (an empty schema would only
            // defer the crash to the first insert). History simply won't persist
            // across launches in that rare state. An in-memory container built from a
            // valid schema only fails for a deterministic, dev-time model error, so a
            // force-try here surfaces that loudly rather than masking it.
            AppLog.app.error("Persistent ModelContainer failed (\(error.localizedDescription, privacy: .public)); falling back to in-memory store")
            let fallback = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            modelContainer = try! ModelContainer(for: schema, configurations: [fallback])
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .task {
                    await handleSceneActivation()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        Task { await handleSceneActivation() }
                    }
                }
        }
        .modelContainer(modelContainer)
    }

    @MainActor
    private func handleSceneActivation() async {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else { return }

        // Gate the heavy full-library scan to once per calendar day. Foregrounding
        // the app repeatedly (and the .task + scenePhase double-fire on cold launch)
        // must not re-enumerate the entire library each time.
        // Gate on a lightweight UserDefaults marker rather than the persisted
        // StorageSnapshot: a SwiftData save failure must not force a full
        // re-enumeration of the library on every foreground.
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        if let lastScan = AppPreferences.lastStorageScanDate(),
           calendar.isDate(lastScan, inSameDayAs: today) {
            // Heavy scan already ran today; still refresh the cheap device-capacity
            // numbers so the widget's storage ring stays current without
            // re-enumerating the library.
            refreshWidgetDeviceCapacity()
            return
        }

        // A single enumeration feeds both the storage snapshot and the reminder copy.
        let measuredAt = Date()
        let photoService = PhotoLibraryService()
        let assets = await photoService.fetchAssets(filter: .allMedia)

        recordStorageSnapshot(from: assets, capturedAt: measuredAt)
        await refreshReminderIfNeeded(assets: assets)
        writeWidgetSnapshot(from: assets, capturedAt: measuredAt)
        // Record that the heavy scan ran today regardless of the SwiftData save
        // result above, so a persistent save failure can't re-trigger it on every
        // foreground.
        AppPreferences.saveLastStorageScanDate(measuredAt)
    }

    @MainActor
    private func recordStorageSnapshot(from assets: [AssetSummary], capturedAt: Date) {
        var photoBytes: Int64 = 0
        var videoBytes: Int64 = 0
        var screenshotBytes: Int64 = 0
        var livePhotoBytes: Int64 = 0
        var otherBytes: Int64 = 0

        for asset in assets {
            switch asset.mediaType {
            case .photo:
                if asset.isScreenshot {
                    screenshotBytes += asset.fileSize
                } else if asset.isLivePhoto {
                    livePhotoBytes += asset.fileSize
                } else {
                    photoBytes += asset.fileSize
                }
            case .video:
                videoBytes += asset.fileSize
            default:
                otherBytes += asset.fileSize
            }
        }

        let snapshot = StorageSnapshot(
            capturedAt: capturedAt,
            photoBytes: photoBytes,
            videoBytes: videoBytes,
            screenshotBytes: screenshotBytes,
            livePhotoBytes: livePhotoBytes,
            otherBytes: otherBytes
        )
        let context = modelContainer.mainContext
        context.insert(snapshot)
        do {
            try context.save()
        } catch {
            AppLog.app.error("Failed to save storage snapshot: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Widget Snapshot

    @MainActor
    private func writeWidgetSnapshot(from assets: [AssetSummary], capturedAt: Date) {
        let threshold = Int64(AppPreferences.largeFileThresholdMB() * 1_000_000)
        let screenshots = assets.filter(\.isScreenshot)
        let screenshotBytes = screenshots.reduce(Int64(0)) { $0 + $1.fileSize }
        let largeFiles = assets.filter { $0.fileSize >= threshold }
        let largeFileBytes = largeFiles.reduce(Int64(0)) { $0 + $1.fileSize }
        let libraryBytes = assets.reduce(Int64(0)) { $0 + $1.fileSize }

        // Reclaimable estimate mirrors the dashboard's cleanup opportunities:
        // screenshots + videos over 100 MB + ~half of each Live Photo.
        let largeVideoBytes = assets
            .filter { $0.mediaType == .video && $0.fileSize > 100_000_000 }
            .reduce(Int64(0)) { $0 + $1.fileSize }
        let livePhotoSavings = assets.filter(\.isLivePhoto).reduce(Int64(0)) { $0 + $1.fileSize } / 2
        let reclaimable = screenshotBytes + largeVideoBytes + livePhotoSavings

        let capacity = Self.readDeviceCapacity()
        let snapshot = WidgetSnapshot(
            capturedAt: capturedAt,
            usedBytes: capacity.used,
            totalBytes: capacity.total,
            libraryBytes: libraryBytes,
            screenshotCount: screenshots.count,
            screenshotBytes: screenshotBytes,
            largeFileCount: largeFiles.count,
            largeFileBytes: largeFileBytes,
            reclaimableBytes: reclaimable
        )
        AppGroupStore.save(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Cheap refresh of just the device-capacity figures (no PhotoKit), used when
    /// the heavy library scan has already run today.
    @MainActor
    private func refreshWidgetDeviceCapacity() {
        guard var snapshot = AppGroupStore.loadSnapshot() else { return }
        let capacity = Self.readDeviceCapacity()
        snapshot.usedBytes = capacity.used
        snapshot.totalBytes = capacity.total
        AppGroupStore.save(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private static func readDeviceCapacity() -> (used: Int64, total: Int64) {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        let values: URLResourceValues
        do {
            values = try url.resourceValues(forKeys: [
                .volumeTotalCapacityKey,
                .volumeAvailableCapacityForImportantUsageKey
            ])
        } catch {
            AppLog.app.error("Failed to read device capacity: \(error.localizedDescription, privacy: .public)")
            return (0, 0)
        }
        let total = Int64(values.volumeTotalCapacity ?? 0)
        let available = values.volumeAvailableCapacityForImportantUsage ?? 0
        return (max(0, total - available), total)
    }

    @MainActor
    private func refreshReminderIfNeeded(assets: [AssetSummary]) async {
        guard AppPreferences.remindersEnabled() else { return }

        let weekday = AppPreferences.reminderWeekday()
        guard (1...7).contains(weekday) else { return }

        // Don't attempt to (re)schedule if notification permission was revoked.
        guard await NotificationService.isPermissionGranted() else { return }

        let threshold = Int64(AppPreferences.largeFileThresholdMB() * 1_000_000)
        let screenshotCount = assets.filter(\.isScreenshot).count
        let largeFileCount = assets.filter { $0.fileSize >= threshold }.count
        let totalSize = assets.reduce(Int64(0)) { $0 + $1.fileSize }

        await NotificationService.scheduleWeeklyReminder(
            weekday: weekday,
            screenshotCount: screenshotCount,
            largeFileCount: largeFileCount,
            librarySize: totalSize.formattedFileSize
        )
    }
}
