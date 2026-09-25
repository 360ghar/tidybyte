import Foundation
import Observation
import SwiftData
import WidgetKit
import Photos

/// Owns the launch-time library scan and the widget-snapshot refreshes
/// that keep the widget in sync with in-app cleanups.
///
/// Every entry point funnels through here so the APP-01 cold-launch race
/// (`.task` + `scenePhase` double-fire) and the APP-02 permission-grant path
/// share ONE scan, deduped by `isScanning`.
@MainActor
@Observable
final class WidgetSnapshotCoordinator {
    private var isScanning = false
    private var hasScannedThisLaunch = false
    private var lastScanPermission: PHAuthorizationStatus?
    /// Scan epochs restart each launch. Keep this deduplication state in memory.
    private var lastWrittenEpoch: Int?
    private var lastWrittenThreshold: Int64?
    private var debounceTask: Task<Void, Never>?
    private var snapshotTask: Task<NotificationService.Snapshot?, Never>?
    private var snapshotRequesters = Set<UUID>()
    private let statistics: @MainActor () async -> MediaLibraryStats
    private let photoAuthorization: @MainActor () -> PHAuthorizationStatus

    init(photoService: PhotoLibraryService = PhotoLibraryService.shared,
         statistics: (@MainActor () async -> MediaLibraryStats)? = nil,
         photoAuthorization: @escaping @MainActor () -> PHAuthorizationStatus = { PHPhotoLibrary.authorizationStatus(for: .readWrite) }) {
        self.statistics = statistics ?? { await Self.computeStats(photoService: photoService) }
        self.photoAuthorization = photoAuthorization
    }

    // MARK: - Daily Scan

    /// Refreshes statistics on launch or permission changes; storage history is
    /// written only once per day. Re-entrant:
    /// concurrent callers see `isScanning` and return immediately (APP-01).
    func runDailyScanIfNeeded(modelContext: ModelContext) async {
        guard !isScanning else { return }

        let permission = photoAuthorization()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        if hasScannedThisLaunch, lastScanPermission == permission, let lastScan = AppPreferences.lastStorageScanDate(),
           calendar.isDate(lastScan, inSameDayAs: today) {
            // Heavy scan already ran today; still refresh the cheap
            // device-capacity numbers so the widget's storage ring stays
            // current without re-enumerating the library.
            refreshWidgetDeviceCapacity()
            return
        }

        isScanning = true
        defer { isScanning = false }

        // A single enumeration feeds the storage snapshot and the widget
        // snapshot. Retry if access or the library changes during enumeration.
        let snapshot = await currentSnapshot()
        guard !Task.isCancelled else { return }
        guard let snapshot else {
            await refreshReminder(snapshot: nil)
            return
        }
        let stats = snapshot.stats
        let completedAt = Date()

        if Self.shouldRecordStorageSnapshot(lastRecordedAt: AppPreferences.lastStorageScanDate(), completedAt: completedAt) {
            recordStorageSnapshot(stats: stats, at: completedAt, modelContext: modelContext)
        }
        hasScannedThisLaunch = true
        lastScanPermission = snapshot.isLimited ? .limited : .authorized
        lastWrittenEpoch = ScanResults.epoch
        lastWrittenThreshold = AppPreferences.largeFileThresholdBytes()
        // Reconcile the cached lifetime totals from the ledger BEFORE the
        // widget write, so the widget's "Cleaned up ..." figure can't drift from
        // the SwiftData history it's supposed to mirror.
        CleanupLedger.shared.refreshCache(modelContext: modelContext)
        writeWidgetSnapshot(stats: stats)
        // Record that the heavy scan ran today regardless of the SwiftData save
        // result. Use the same day as the history row, including across midnight.
        AppPreferences.saveLastStorageScanDate(completedAt)
        await refreshReminder(snapshot: snapshot)
    }

    // MARK: - Widget Refresh After Library Change

    /// Debounced recompute of the widget snapshot after an in-library change
    /// (in-app deletion, compression, or edits made in the Photos app).
    /// Skips until the daily scan has established a baseline, and skips
    /// rewrites when neither the library epoch nor the size threshold changed.
    func refreshAfterLibraryChange(modelContext: ModelContext) async {
        guard AppPreferences.lastStorageScanDate() != nil else { return }
        let epoch = ScanResults.epoch
        let threshold = AppPreferences.largeFileThresholdBytes()
        guard epoch != lastWrittenEpoch || threshold != lastWrittenThreshold else { return }

        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1500))
            guard !Task.isCancelled, let self else { return }
            // A permission-triggered launch scan can finish during the debounce.
            guard ScanResults.epoch != self.lastWrittenEpoch
                || AppPreferences.largeFileThresholdBytes() != self.lastWrittenThreshold else { return }
            // Compression and Live Photo conversion write `CompressionRecord`
            // rows directly (not through the ledger), so this is the point that
            // folds their savings into the cached lifetime total.
            CleanupLedger.shared.refreshCache(modelContext: modelContext)
            let snapshot = await self.currentSnapshot()
            guard !Task.isCancelled else { return }
            if let snapshot {
                self.writeWidgetSnapshot(stats: snapshot.stats)
                self.lastWrittenEpoch = ScanResults.epoch
                self.lastWrittenThreshold = AppPreferences.largeFileThresholdBytes()
            }
            await self.refreshReminder(snapshot: snapshot)
        }
    }

    // MARK: - Snapshot Writing

    nonisolated static func shouldRecordStorageSnapshot(lastRecordedAt: Date?, completedAt: Date, calendar: Calendar = .current) -> Bool {
        lastRecordedAt.map { !calendar.isDate($0, inSameDayAs: completedAt) } ?? true
    }

    private func recordStorageSnapshot(stats: MediaLibraryStats, at date: Date, modelContext: ModelContext) {
        let snapshot = StorageSnapshot(
            capturedAt: date,
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

    /// Settings requests fresh counts without writing another storage-history row.
    func refreshReminder() async {
        let snapshot = await currentSnapshot()
        guard !Task.isCancelled else { return }
        await refreshReminder(snapshot: snapshot)
    }

    private func refreshReminder(snapshot: NotificationService.Snapshot?) async {
        if snapshot == nil { lastScanPermission = nil }
        NotificationService.updateSnapshot(snapshot)
        _ = await NotificationService.scheduleWeeklyReminder(weekday: AppPreferences.reminderWeekday())
    }

    /// Concurrent launch, permission, and Settings refreshes share one bounded scan.
    func currentSnapshot() async -> NotificationService.Snapshot? {
        guard !Task.isCancelled else { return nil }
        let requester = UUID()
        snapshotRequesters.insert(requester)
        let task = snapshotTask ?? Task { await scanSnapshot() }
        snapshotTask = task
        return await withTaskCancellationHandler {
            let snapshot = await task.value
            releaseSnapshotRequester(requester)
            guard !Task.isCancelled else { return nil }
            return NotificationService.authorizedSnapshot(snapshot, permission: photoAuthorization())
        } onCancel: {
            Task { @MainActor [weak self] in self?.releaseSnapshotRequester(requester) }
        }
    }

    /// One cancelled caller must not cancel work another caller still needs.
    private func releaseSnapshotRequester(_ id: UUID) {
        guard snapshotRequesters.remove(id) != nil, snapshotRequesters.isEmpty else { return }
        snapshotTask?.cancel()
        snapshotTask = nil
    }

    private func scanSnapshot() async -> NotificationService.Snapshot? {
        for _ in 0..<2 {
            guard !Task.isCancelled else { return nil }
            let permission = photoAuthorization()
            guard permission == .authorized || permission == .limited else { return nil }
            let epoch = ScanResults.epoch
            let threshold = AppPreferences.largeFileThresholdBytes()
            let stats = await statistics()
            guard !Task.isCancelled else { return nil }
            if permission != photoAuthorization() || epoch != ScanResults.epoch
                || threshold != AppPreferences.largeFileThresholdBytes() { continue }
            return NotificationService.Snapshot(stats: stats, date: .now, isLimited: permission == .limited)
        }
        return nil
    }

    // MARK: - Shared Helpers

    /// Single enumeration + off-main pure stats pass shared by the daily scan
    /// and the post-change widget refresh.
    private static func computeStats(photoService: PhotoLibraryService) async -> MediaLibraryStats {
        let assets = await photoService.fetchAssets(filter: .allMedia)
        guard !Task.isCancelled else { return MediaLibraryStats() }
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
