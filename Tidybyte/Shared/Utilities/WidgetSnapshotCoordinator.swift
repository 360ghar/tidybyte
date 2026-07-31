import Foundation
import Observation
import SwiftData
import WidgetKit

/// Owns the once-per-day heavy library scan and the widget-snapshot refreshes
/// that keep the widget in sync with in-app cleanups.
///
/// Every entry point funnels through here so the APP-01 cold-launch race
/// (`.task` + `scenePhase` double-fire) and the APP-02 permission-grant path
/// share ONE scan, deduped by `isScanning`.
@MainActor
@Observable
final class WidgetSnapshotCoordinator {
    private let photoService: PhotoLibraryService
    private var isScanning = false
    /// Generation the widget snapshot was last written for. In-memory (not
    /// persisted) deliberately: the monitor's generation counter restarts at 0
    /// each launch, so a persisted value would wrongly suppress the first
    /// post-launch refresh.
    private var lastWrittenGeneration: Int?
    private var debounceTask: Task<Void, Never>?

    init(photoService: PhotoLibraryService = PhotoLibraryService()) {
        self.photoService = photoService
    }

    // MARK: - Daily Scan

    /// The once-per-day heavy scan: storage snapshot (SwiftData), reminder
    /// refresh, widget snapshot write, and the scan-date marker. Re-entrant:
    /// concurrent callers see `isScanning` and return immediately (APP-01).
    func runDailyScanIfNeeded(modelContext: ModelContext) async {
        guard !isScanning else { return }

        let measuredAt = Date()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        if let lastScan = AppPreferences.lastStorageScanDate(),
           calendar.isDate(lastScan, inSameDayAs: today) {
            // Heavy scan already ran today; still refresh the cheap
            // device-capacity numbers so the widget's storage ring stays
            // current without re-enumerating the library.
            refreshWidgetDeviceCapacity()
            return
        }

        isScanning = true
        defer { isScanning = false }

        // A single enumeration feeds the storage snapshot, the reminder copy,
        // and the widget snapshot.
        let stats = await Self.computeStats(photoService: photoService)

        recordStorageSnapshot(stats: stats, capturedAt: measuredAt, modelContext: modelContext)
        await refreshReminderIfNeeded(stats: stats)
        writeWidgetSnapshot(stats: stats, capturedAt: measuredAt)
        // Record that the heavy scan ran today regardless of the SwiftData save
        // result above, so a persistent save failure can't re-trigger it on
        // every foreground.
        AppPreferences.saveLastStorageScanDate(measuredAt)
    }

    // MARK: - Widget Refresh After Library Change

    /// Debounced recompute of the widget snapshot after an in-library change
    /// (in-app deletion, compression, or edits made in the Photos app).
    /// Skips until the daily scan has established a baseline, and skips
    /// rewrites when the generation hasn't advanced past the last write
    /// (APP-03).
    func refreshAfterLibraryChange(generation: Int) async {
        guard AppPreferences.lastStorageScanDate() != nil else { return }
        guard generation != lastWrittenGeneration else { return }

        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1500))
            guard !Task.isCancelled, let self else { return }
            // Re-check inside the task: a newer bump may have landed while we
            // slept and already written.
            guard generation != self.lastWrittenGeneration else { return }
            let stats = await Self.computeStats(photoService: self.photoService)
            self.writeWidgetSnapshot(stats: stats, capturedAt: Date())
            self.lastWrittenGeneration = generation
        }
    }

    // MARK: - Snapshot Writing

    private func recordStorageSnapshot(stats: MediaLibraryStats, capturedAt: Date, modelContext: ModelContext) {
        let snapshot = StorageSnapshot(
            capturedAt: capturedAt,
            photoBytes: stats.photoBytes,
            videoBytes: stats.videoBytes,
            screenshotBytes: stats.screenshotBytes,
            livePhotoBytes: stats.livePhotoBytes,
            otherBytes: stats.otherBytes
        )
        modelContext.insert(snapshot)
        pruneStorageSnapshots(olderThan: capturedAt, modelContext: modelContext)
        do {
            try modelContext.save()
        } catch {
            AppLog.app.error("Failed to save storage snapshot: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// APP-15: rows older than 60 days are never read (the dashboard trend
    /// filter is 30 days) — prune them so the store can't grow without bound.
    private func pruneStorageSnapshots(olderThan capturedAt: Date, modelContext: ModelContext) {
        let cutoff = Calendar.current.date(byAdding: .day, value: -60, to: capturedAt) ?? capturedAt
        let descriptor = FetchDescriptor<StorageSnapshot>(
            predicate: #Predicate { $0.capturedAt < cutoff }
        )
        guard let stale = try? modelContext.fetch(descriptor) else { return }
        for snapshot in stale {
            modelContext.delete(snapshot)
        }
    }

    private func writeWidgetSnapshot(stats: MediaLibraryStats, capturedAt: Date) {
        let capacity = Self.readDeviceCapacity()
        let snapshot = WidgetSnapshot(
            capturedAt: capturedAt,
            usedBytes: capacity.used,
            totalBytes: capacity.total,
            screenshotCount: stats.screenshotCount,
            screenshotBytes: stats.screenshotBytes,
            largeFileCount: stats.largeFileCount,
            largeFileBytes: stats.largeFileBytes,
            reclaimableBytes: stats.reclaimableBytes
        )
        AppGroupStore.save(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Cheap refresh of just the device-capacity figures (no PhotoKit), used
    /// when the heavy library scan has already run today.
    private func refreshWidgetDeviceCapacity() {
        guard var snapshot = AppGroupStore.loadSnapshot() else { return }
        let capacity = Self.readDeviceCapacity()
        snapshot.usedBytes = capacity.used
        snapshot.totalBytes = capacity.total
        AppGroupStore.save(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func refreshReminderIfNeeded(stats: MediaLibraryStats) async {
        guard AppPreferences.remindersEnabled() else { return }

        let weekday = AppPreferences.reminderWeekday()
        guard (1...7).contains(weekday) else { return }

        // Don't attempt to (re)schedule if notification permission was revoked.
        guard await NotificationService.isPermissionGranted() else { return }

        await NotificationService.scheduleWeeklyReminder(
            weekday: weekday,
            screenshotCount: stats.screenshotCount,
            largeFileCount: stats.largeFileCount,
            librarySize: stats.totalBytes.formattedFileSize
        )
    }

    // MARK: - Shared Helpers

    /// Single enumeration + off-main pure stats pass shared by the daily scan
    /// and the post-change widget refresh.
    private static func computeStats(photoService: PhotoLibraryService) async -> MediaLibraryStats {
        let assets = await photoService.fetchAssets(filter: .allMedia)
        let threshold = AppPreferences.largeFileThresholdBytes()
        // APP-09: the per-asset classification pass is pure CPU — run it off the
        // main actor so the scan never blocks UI, then hop back to the main
        // actor for the SwiftData / UserDefaults writes.
        return await Task.detached {
            MediaLibraryStats.build(from: assets, largeFileThresholdBytes: threshold)
        }.value
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
}
