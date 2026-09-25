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

    init(photoService: PhotoLibraryService = PhotoLibraryService.shared) {
        self.photoService = photoService
    }

    // MARK: - Daily Scan

    /// The once-per-day heavy scan: storage snapshot (SwiftData), reminder
    /// refresh, widget snapshot write, and the scan-date marker. Re-entrant:
    /// concurrent callers see `isScanning` and return immediately (APP-01).
    func runDailyScanIfNeeded(modelContext: ModelContext) async {
        guard !isScanning else { return }

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

        // `measuredAt` only marks that this scan ran (the once-per-day gate).
        // Snapshot timestamps are stamped at WRITE time below — a scan spanning
        // midnight must land on the day its data was recorded, not when the
        // enumeration started (A2).
        let measuredAt = Date()

        // A single enumeration feeds the storage snapshot and the widget
        // snapshot.
        let stats = await Self.computeStats(photoService: photoService)

        recordStorageSnapshot(stats: stats, modelContext: modelContext)
        // Reconcile the cached lifetime totals from the ledger BEFORE the
        // widget write, so the widget's "Cleaned up ..." figure can't drift from
        // the SwiftData history it's supposed to mirror.
        CleanupLedger.shared.refreshCache(modelContext: modelContext)
        writeWidgetSnapshot(stats: stats)
        await migrateReminderCopyIfNeeded()
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
    func refreshAfterLibraryChange(generation: Int, modelContext: ModelContext) async {
        guard AppPreferences.lastStorageScanDate() != nil else { return }
        guard generation != lastWrittenGeneration else { return }

        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1500))
            guard !Task.isCancelled, let self else { return }
            // Compression and Live Photo conversion write `CompressionRecord`
            // rows directly (not through the ledger), so this is the point that
            // folds their savings into the cached lifetime total.
            CleanupLedger.shared.refreshCache(modelContext: modelContext)
            let stats = await Self.computeStats(photoService: self.photoService)
            self.writeWidgetSnapshot(stats: stats)
            self.lastWrittenGeneration = generation
        }
    }

    // MARK: - Snapshot Writing

    private func recordStorageSnapshot(stats: MediaLibraryStats, modelContext: ModelContext) {
        let snapshot = StorageSnapshot(
            capturedAt: .now,
            photoBytes: stats.photoBytes,
            videoBytes: stats.videoBytes,
            screenshotBytes: stats.screenshotBytes,
            livePhotoBytes: stats.livePhotoBytes,
            otherBytes: stats.otherBytes
        )
        modelContext.insert(snapshot)
        pruneStorageSnapshots(modelContext: modelContext)
        do {
            try modelContext.save()
        } catch {
            AppLog.app.error("Failed to save storage snapshot: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// APP-15: rows older than 60 days are never read (the dashboard trend
    /// filter is 30 days) — prune them so the store can't grow without bound.
    private func pruneStorageSnapshots(modelContext: ModelContext) {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -60, to: .now) else { return }
        let descriptor = FetchDescriptor<StorageSnapshot>(
            predicate: #Predicate { $0.capturedAt < cutoff }
        )
        guard let stale = try? modelContext.fetch(descriptor) else { return }
        for snapshot in stale {
            modelContext.delete(snapshot)
        }
    }

    /// Writes the widget snapshot. No-ops when nothing changed — a foreground
    /// that re-ran the daily-scan gate used to burn a WidgetKit reload budget
    /// slot on every launch even with identical numbers (A5).
    private func writeWidgetSnapshot(stats: MediaLibraryStats) {
        let capacity = Self.readDeviceCapacity()
        let lifetime = AppPreferences.lifetimeFreed()
        if let current = AppGroupStore.loadSnapshot(),
           current.usedBytes == capacity.used,
           current.totalBytes == capacity.total,
           current.screenshotCount == stats.screenshotCount,
           current.screenshotBytes == stats.screenshotBytes,
           current.largeFileCount == stats.largeFileCount,
           current.largeFileBytes == stats.largeFileBytes,
           current.reclaimableBytes == stats.reclaimableBytes,
           current.lifetimeFreedBytes == lifetime.bytes,
           current.lifetimeItemCount == lifetime.items {
            // Same figures: record the scan time only, so the widget's
            // "Updated 3d ago" reflects the last scan, not the last change.
            // No timeline reload: the hourly refresh picks it up.
            var refreshed = current
            refreshed.capturedAt = .now
            AppGroupStore.save(refreshed)
            return
        }
        let snapshot = WidgetSnapshot(
            capturedAt: .now,
            usedBytes: capacity.used,
            totalBytes: capacity.total,
            screenshotCount: stats.screenshotCount,
            screenshotBytes: stats.screenshotBytes,
            largeFileCount: stats.largeFileCount,
            largeFileBytes: stats.largeFileBytes,
            reclaimableBytes: stats.reclaimableBytes,
            lifetimeFreedBytes: lifetime.bytes,
            lifetimeItemCount: lifetime.items
        )
        AppGroupStore.save(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Cheap refresh of just the device-capacity figures (no PhotoKit), used
    /// when the heavy library scan has already run today. Also skips the
    /// reload when nothing changed (A5).
    private func refreshWidgetDeviceCapacity() {
        guard var snapshot = AppGroupStore.loadSnapshot() else { return }
        let capacity = Self.readDeviceCapacity()
        guard snapshot.usedBytes != capacity.used || snapshot.totalBytes != capacity.total else { return }
        snapshot.usedBytes = capacity.used
        snapshot.totalBytes = capacity.total
        AppGroupStore.save(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// A repeating reminder keeps the text it was scheduled with. Reminders
    /// scheduled by older builds carry stale counts, so reschedule once with
    /// the count-free text.
    ///
    /// Gated on V3, not V2: V2 was already consumed by the build that shipped
    /// "large videos" in the body, so those users kept the old wording. A fresh
    /// key re-runs the reschedule once and lets the current copy land.
    private func migrateReminderCopyIfNeeded() async {
        let key = AppPreferences.Key.reminderCopyMigratedV3
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        guard AppPreferences.remindersEnabled() else {
            UserDefaults.standard.set(true, forKey: key)
            return
        }
        let weekday = AppPreferences.reminderWeekday()
        guard (1...7).contains(weekday), await NotificationService.isPermissionGranted() else { return }
        guard await NotificationService.scheduleWeeklyReminder(weekday: weekday) else { return }
        UserDefaults.standard.set(true, forKey: key)
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
