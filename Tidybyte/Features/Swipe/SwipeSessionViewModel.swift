import SwiftUI
import SwiftData
import Photos

struct SessionStats: Sendable {
    var deletedCount: Int = 0
    var organizedCount: Int = 0
    var skippedCount: Int = 0
    var deletedBytes: Int64 = 0

    var totalReviewed: Int {
        deletedCount + organizedCount + skippedCount
    }

    static let empty = SessionStats()
}

struct SwipeUndoEntry: Sendable {
    let asset: AssetSummary
    let decision: SwipeDecision
    let albumId: String?
}

@Observable
@MainActor
final class SwipeSessionViewModel {
    var assets: [AssetSummary] = []
    /// Local identifiers of deck assets already in a user album. A right-swipe on
    /// one of these keeps the photo without prompting "Add to Album" — it's
    /// already organized. Precomputed once at deck load (see `loadAssets`).
    var assetIdsInUserAlbums: Set<String> = []
    var currentIndex: Int = 0
    var isLoading: Bool = false
    private(set) var hasLoadedInitialAssets = false
    var sessionStats: SessionStats = .empty
    var showCompletion: Bool = false
    var showAlbumPicker: Bool = false
    var pendingKeepAsset: AssetSummary?
    var errorMessage: String?
    /// Separate from `errorMessage` so the completion screen's delete-confirmation
    /// alert doesn't collide with the still-mounted SwipeSessionView error alert
    /// (two `.alert(isPresented:)` bound to the same flag fight over presentation).
    var deletionErrorMessage: String?
    var allPhotosAlreadySwiped: Bool = false
    var isPerformingMutation = false
    var pendingDeletionIds: [String] = []
    var pendingDeletionBytes: Int64 = 0
    var isDeletingBatch = false
    var deletionCommitted = false

    private(set) var undoStack: [SwipeUndoEntry] = []

    let filter: SwipeFilter
    let photoService: PhotoLibraryService
    let modelContext: ModelContext

    var currentAsset: AssetSummary? {
        guard currentIndex < assets.count else { return nil }
        return assets[currentIndex]
    }

    var hasMoreCards: Bool {
        currentIndex < assets.count
    }

    var visibleCards: [AssetSummary] {
        let start = currentIndex
        let end = min(currentIndex + 3, assets.count)
        guard start < end else { return [] }
        return Array(assets[start..<end])
    }

    init(filter: SwipeFilter, photoService: PhotoLibraryService, modelContext: ModelContext) {
        self.filter = filter
        self.photoService = photoService
        self.modelContext = modelContext
    }

    func loadAssetsIfNeeded() async {
        guard !hasLoadedInitialAssets, !isLoading else { return }
        await loadAssets()
    }

    func resetForNewSession() {
        assets.removeAll()
        assetIdsInUserAlbums.removeAll()
        currentIndex = 0
        isLoading = false
        hasLoadedInitialAssets = false
        sessionStats = .empty
        showCompletion = false
        showAlbumPicker = false
        pendingKeepAsset = nil
        errorMessage = nil
        deletionErrorMessage = nil
        allPhotosAlreadySwiped = false
        isPerformingMutation = false
        pendingDeletionIds.removeAll()
        pendingDeletionBytes = 0
        isDeletingBatch = false
        deletionCommitted = false
        undoStack.removeAll()
        // Release any images prefetched for the previous session.
        Task { await photoService.stopAllCaching() }
    }

    private func loadAssets() async {
        isLoading = true
        allPhotosAlreadySwiped = false

        let swipedIds = fetchSwipedIdentifiers()

        let fetched: [AssetSummary]
        switch filter {
        case .notSwipedYet:
            let allAssets = await photoService.fetchAssets(filter: .allMedia)
            let filtered = allAssets.filter { !swipedIds.contains($0.id) }
            if filtered.isEmpty && !allAssets.isEmpty {
                allPhotosAlreadySwiped = true
            }
            fetched = filtered
        default:
            fetched = await photoService.fetchAssets(filter: filter)
        }

        assets = fetched
        // Precompute album membership so a right-swipe can skip the "Add to
        // Album" prompt for already-organized photos. `.notInAnyAlbum` excludes
        // those by definition, so there's nothing to look up.
        if case .notInAnyAlbum = filter {
            assetIdsInUserAlbums = []
        } else {
            assetIdsInUserAlbums = await photoService.assetIdentifiersInUserAlbums()
        }
        currentIndex = 0
        hasLoadedInitialAssets = true
        isLoading = false

        // Pre-cache next batch in background (matches advance() pattern)
        let prefetchIds = Array(assets.prefix(10).map(\.id))
        let screenSize = ScreenMetrics.pixelSize
        Task {
            await photoService.startCaching(assetIds: prefetchIds, targetSize: screenSize)
        }
    }

    func swipeLeft() {
        guard let asset = currentAsset, !isPerformingMutation else { return }
        // Deletions are deferred and only persisted/committed at session end. We
        // intentionally do NOT write a SwipeRecord here: if the user exits without
        // committing, the photo was never deleted and must reappear next session
        // rather than being silently hidden by the "Not Swiped Yet" filter.
        if !pendingDeletionIds.contains(asset.id) {
            pendingDeletionIds.append(asset.id)
            pendingDeletionBytes += asset.fileSize
            sessionStats.deletedCount += 1
            sessionStats.deletedBytes += asset.fileSize
            undoStack.append(SwipeUndoEntry(asset: asset, decision: .deleted, albumId: nil))
        }
        advance()
    }

    func swipeRight() {
        // Guard against a second right-swipe overwriting a keep that is still
        // awaiting album selection.
        guard let asset = currentAsset, pendingKeepAsset == nil, !isPerformingMutation else { return }
        // Photos already organized into a user album don't need re-organizing —
        // keep and advance without showing the "Add to Album" picker.
        if assetIdsInUserAlbums.contains(asset.id) {
            skip()
            return
        }
        pendingKeepAsset = asset
        showAlbumPicker = true
    }

    func addToAlbum(albumId: String) async -> Bool {
        guard let asset = pendingKeepAsset, !isPerformingMutation else { return false }
        isPerformingMutation = true
        defer { isPerformingMutation = false }

        do {
            try await photoService.addToAlbum(assetIdentifiers: [asset.id], albumIdentifier: albumId)
            sessionStats.organizedCount += 1
            undoStack.append(SwipeUndoEntry(asset: asset, decision: .addedToAlbum, albumId: albumId))
            upsertSwipeRecord(asset: asset, decision: .addedToAlbum, albumId: albumId)
            pendingKeepAsset = nil
            showAlbumPicker = false
            advance()
            return true
        } catch {
            errorMessage = "Failed to add to album: \(error.localizedDescription)"
            return false
        }
    }

    func skipKeep() {
        guard let asset = pendingKeepAsset else { return }
        sessionStats.skippedCount += 1
        undoStack.append(SwipeUndoEntry(asset: asset, decision: .skipped, albumId: nil))
        upsertSwipeRecord(asset: asset, decision: .skipped)
        pendingKeepAsset = nil
        showAlbumPicker = false
        advance()
    }

    func skip() {
        guard let asset = currentAsset, !isPerformingMutation else { return }
        sessionStats.skippedCount += 1
        undoStack.append(SwipeUndoEntry(asset: asset, decision: .skipped, albumId: nil))
        upsertSwipeRecord(asset: asset, decision: .skipped)
        advance()
    }

    func undo() async {
        guard let entry = undoStack.last, !isPerformingMutation else { return }

        switch entry.decision {
        case .deleted:
            undoStack.removeLast()
            if let index = pendingDeletionIds.lastIndex(of: entry.asset.id) {
                pendingDeletionIds.remove(at: index)
            }
            pendingDeletionBytes = max(0, pendingDeletionBytes - entry.asset.fileSize)
            sessionStats.deletedCount = max(0, sessionStats.deletedCount - 1)
            sessionStats.deletedBytes = max(0, sessionStats.deletedBytes - entry.asset.fileSize)
            currentIndex = max(0, currentIndex - 1)
            // No SwipeRecord was written for a pending deletion, so nothing to remove.
        case .addedToAlbum:
            guard let albumId = entry.albumId else { return }
            isPerformingMutation = true
            defer { isPerformingMutation = false }
            do {
                try await photoService.removeFromAlbum(assetIdentifiers: [entry.asset.id], albumIdentifier: albumId)
                undoStack.removeLast()
                sessionStats.organizedCount = max(0, sessionStats.organizedCount - 1)
                currentIndex = max(0, currentIndex - 1)
                deleteSwipeRecord(for: entry.asset.id)
            } catch {
                errorMessage = "Failed to undo album change: \(error.localizedDescription)"
            }
        case .skipped:
            undoStack.removeLast()
            sessionStats.skippedCount = max(0, sessionStats.skippedCount - 1)
            currentIndex = max(0, currentIndex - 1)
            deleteSwipeRecord(for: entry.asset.id)
        }
    }

    func commitDeletions() async {
        guard !pendingDeletionIds.isEmpty, !isDeletingBatch else { return }
        isDeletingBatch = true
        do {
            try await photoService.deleteAssets(identifiers: pendingDeletionIds)
            deletionCommitted = true
            pendingDeletionIds.removeAll()
            pendingDeletionBytes = 0
            HapticHelper.notification(.success)
        } catch {
            deletionErrorMessage = "Failed to delete \(pendingDeletionIds.count) photos: \(error.localizedDescription)"
        }
        isDeletingBatch = false
    }

    func discardPendingDeletions() {
        // Pending deletions were never persisted, so there are no swipe records to
        // remove — just clear the in-memory state.
        sessionStats.deletedCount = 0
        sessionStats.deletedBytes = 0
        pendingDeletionIds.removeAll()
        pendingDeletionBytes = 0
    }

    func endSession() async {
        await photoService.stopAllCaching()
        showCompletion = true
    }

    // MARK: - Private

    private func advance() {
        currentIndex += 1
        if currentIndex >= assets.count {
            showCompletion = true
        } else {
            // Pre-cache upcoming images
            let prefetchStart = currentIndex + 1
            let prefetchEnd = min(currentIndex + 10, assets.count)
            if prefetchStart < prefetchEnd {
                let ids = Array(assets[prefetchStart..<prefetchEnd].map(\.id))
                let screenSize = ScreenMetrics.pixelSize
                Task {
                    await photoService.startCaching(assetIds: ids, targetSize: screenSize)
                }
            }
        }
    }

    private func upsertSwipeRecord(asset: AssetSummary, decision: SwipeDecision, albumId: String? = nil) {
        let assetId = asset.id
        let descriptor = FetchDescriptor<SwipeRecord>(
            predicate: #Predicate { $0.assetLocalIdentifier == assetId }
        )
        let existingRecords = (try? modelContext.fetch(descriptor)) ?? []

        let record = existingRecords.first ?? SwipeRecord(
            assetLocalIdentifier: assetId,
            decision: decision,
            albumLocalIdentifier: albumId
        )

        record.decision = decision
        record.albumLocalIdentifier = albumId
        record.swipedAt = .now

        if existingRecords.isEmpty {
            modelContext.insert(record)
        } else if existingRecords.count > 1 {
            for duplicate in existingRecords.dropFirst() {
                modelContext.delete(duplicate)
            }
        }
        save(context: "upsert swipe record")
    }

    private func deleteSwipeRecord(for assetId: String) {
        let descriptor = FetchDescriptor<SwipeRecord>(
            predicate: #Predicate { $0.assetLocalIdentifier == assetId }
        )
        if let records = try? modelContext.fetch(descriptor) {
            for record in records {
                modelContext.delete(record)
            }
            save(context: "delete swipe record")
        }
    }

    private func save(context: String) {
        do {
            try modelContext.save()
        } catch {
            // Swipe history is mission-critical: surface the failure rather than
            // letting the user believe their decisions were recorded.
            AppLog.data.error("Failed to \(context, privacy: .public): \(error.localizedDescription, privacy: .public)")
            errorMessage = "Couldn't save your changes. Please try again."
        }
    }

    private func fetchSwipedIdentifiers() -> Set<String> {
        let descriptor = FetchDescriptor<SwipeRecord>()
        do {
            let records = try modelContext.fetch(descriptor)
            return Set(records.map(\.assetLocalIdentifier))
        } catch {
            AppLog.data.error("Failed to fetch swipe records: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }
}
