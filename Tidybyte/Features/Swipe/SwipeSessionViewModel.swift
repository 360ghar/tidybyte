import SwiftUI
import SwiftData
import Photos

struct SessionStats: Sendable {
    var deletedCount: Int = 0
    var organizedCount: Int = 0
    var skippedCount: Int = 0
    var deletedBytes: Int64 = 0

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
    /// already organized. Computed lazily on the first right-swipe that needs it
    /// (see `resolveUserAlbumMembership`) instead of eagerly at deck load
    /// so a session can start without a full-library album scan (SWIPE-04).
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

    /// True when deletions are awaiting commit. Gates exits from the session and
    /// completion flow so pending deletions are never dropped silently (SWIPE-02).
    var hasPendingDeletions: Bool {
        !pendingDeletionIds.isEmpty && !deletionCommitted
    }

    /// True while a swipe-card animation is in flight. The view uses this to
    /// ignore a second gesture during the animation window (SWIPE-05).
    private(set) var isSwiping = false

    /// True when the app may read the photo library (authorized or limited) —
    /// used to distinguish a permissions problem from an empty filter (SWIPE-09).
    var isPhotoLibraryAccessible: Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        return status == .authorized || status == .limited
    }

    private(set) var undoStack: [SwipeUndoEntry] = []

    /// Every asset ID this session asked the image manager to cache. Tracked so
    /// the advance path can release images that fell out of the visible +
    /// prefetch window (SWIPE-01).
    private var cachedAssetIDs: Set<String> = []
    /// Whether album membership has been resolved for this deck (SWIPE-04).
    private var userAlbumMembershipResolved = false

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

    /// Clears the loaded state so the next `loadAssetsIfNeeded()` re-runs the
    /// fetch — the "Try Again" affordance for the empty state (SWIPE-09).
    func retryLoad() {
        hasLoadedInitialAssets = false
        allPhotosAlreadySwiped = false
        isLoading = false
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
        // Album membership is resolved lazily on first right-swipe (SWIPE-04):
        // `.notInAnyAlbum` decks are definitionally album-less, and resolving it
        // eagerly here cost a full-library scan before the first card appeared.
        currentIndex = 0
        hasLoadedInitialAssets = true
        isLoading = false

        // Pre-cache next batch in background (matches advance() pattern)
        let prefetchIds = Array(assets.prefix(10).map(\.id))
        cachedAssetIDs.formUnion(prefetchIds)
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
            keepAlreadyOrganized()
            return
        }
        // Lazy album-membership resolution (SWIPE-04): kick off the album scan
        // on first need so it never blocks deck load. The first right-swipe may
        // prompt the picker before the scan lands; subsequent ones won't.
        if !userAlbumMembershipResolved {
            userAlbumMembershipResolved = true
            if case .notInAnyAlbum = filter {
                // Deck assets are definitionally album-less; nothing to look up.
            } else {
                Task { await resolveUserAlbumMembership() }
            }
        }
        pendingKeepAsset = asset
        showAlbumPicker = true
    }

    /// Resolves which deck assets are already in a user album, memoized for the
    /// rest of the session. Runs off the deck-load path (SWIPE-04).
    private func resolveUserAlbumMembership() async {
        assetIdsInUserAlbums = await photoService.assetIdentifiersInUserAlbums()
    }

    /// Handles a right-swipe on a photo that is already in a user album.
    /// Records `.kept` so the completion stats distinguish "already organized"
    /// from true skips, and writes a SwipeRecord so the photo is excluded from
    /// future "Not Swiped Yet" sessions.
    private func keepAlreadyOrganized() {
        guard let asset = currentAsset, !isPerformingMutation else { return }
        sessionStats.organizedCount += 1
        undoStack.append(SwipeUndoEntry(asset: asset, decision: .kept, albumId: nil))
        upsertSwipeRecord(asset: asset, decision: .kept)
        advance()
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

    /// Aborts a keep that is still awaiting album selection. Invoked when the album
    /// picker is dismissed by any means. If the user swiped the sheet down (or tapped
    /// outside) instead of choosing an album or tapping Skip, the keep must be
    /// cancelled — otherwise `pendingKeepAsset` stays set and permanently blocks
    /// `swipeRight()`'s guard. The card stays on top (we never advanced) so the user
    /// can decide again. No-op if a clean exit (addToAlbum/skipKeep) already cleared it.
    func cancelPendingKeep() {
        guard pendingKeepAsset != nil else { return }
        pendingKeepAsset = nil
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
        // The album picker is presented on top of the deck — rewinding the deck
        // underneath the sheet would desync the card the user is choosing an
        // album for (SWIPE-06).
        guard let entry = undoStack.last, !isPerformingMutation, !showAlbumPicker else { return }

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
        case .kept:
            undoStack.removeLast()
            sessionStats.organizedCount = max(0, sessionStats.organizedCount - 1)
            currentIndex = max(0, currentIndex - 1)
            deleteSwipeRecord(for: entry.asset.id)
        }
    }

    func commitDeletions() async {
        guard !pendingDeletionIds.isEmpty, !isDeletingBatch else { return }
        isDeletingBatch = true
        do {
            // Fetch the summaries of assets that still exist at commit time so
            // the freed-size stat only counts photos that are actually being
            // deleted — assets that vanished externally before commit would
            // otherwise overstate "Storage Freed" (SWIPE-08).
            let survivors = await photoService.fetchAssets(filter: .customAssetIds(Set(pendingDeletionIds)))
            let freedBytes = survivors.reduce(Int64(0)) { $0 + $1.fileSize }
            try await photoService.deleteAssets(identifiers: pendingDeletionIds)
            deletionCommitted = true
            sessionStats.deletedCount = survivors.count
            sessionStats.deletedBytes = freedBytes
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

    /// Releases every image this session asked the image manager to cache.
    /// Safe to call multiple times; used on the plain-back dismiss path and by
    /// `endSession` so a session never leaves images pinned in the cache (SWIPE-01).
    func stopAllCaching() async {
        cachedAssetIDs.removeAll()
        await photoService.stopAllCaching()
    }

    func endSession() async {
        await stopAllCaching()
        showCompletion = true
    }

    /// Claims the swipe-animation slot. Returns false (and does nothing) when
    /// an animation is already in flight — the duplicate gesture is dropped
    /// instead of racing the in-flight task (SWIPE-05).
    func beginSwipeAnimation() -> Bool {
        guard !isSwiping else { return false }
        isSwiping = true
        return true
    }

    /// Releases the animation slot after the swipe action completes or the
    /// animation task is cancelled.
    func endSwipeAnimation() {
        isSwiping = false
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
                cachedAssetIDs.formUnion(ids)
                let screenSize = ScreenMetrics.pixelSize
                Task {
                    await photoService.startCaching(assetIds: ids, targetSize: screenSize)
                }
            }
        }
        // Release images that fell out of the visible + prefetch window so a
        // long session doesn't pin hundreds of images in the cache (SWIPE-01).
        releaseCachedAssetsOutsideWindow()
    }

    /// Stops caching every asset that is no longer in the visible + prefetch
    /// window `[currentIndex, currentIndex + 10)` (SWIPE-01).
    private func releaseCachedAssetsOutsideWindow() {
        let windowEnd = min(currentIndex + 10, assets.count)
        guard currentIndex < windowEnd else { return }
        let window = Set(assets[currentIndex..<windowEnd].map(\.id))
        let stale = cachedAssetIDs.subtracting(window)
        guard !stale.isEmpty else { return }
        cachedAssetIDs.subtract(stale)
        let screenSize = ScreenMetrics.pixelSize
        Task {
            await photoService.stopCaching(assetIds: Array(stale), targetSize: screenSize)
        }
    }

    private func upsertSwipeRecord(asset: AssetSummary, decision: SwipeDecision, albumId: String? = nil) {
        let assetId = asset.id
        let existingRecords = fetchSwipeRecords(matching: assetId)

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
        let records = fetchSwipeRecords(matching: assetId)
        for record in records {
            modelContext.delete(record)
        }
        if !records.isEmpty {
            save(context: "delete swipe record")
        }
    }

    /// Fetches swipe records for one asset. Uses a `#Predicate` so the lookup is
    /// pushed into the store instead of loading the whole table and filtering in
    /// Swift — the previous full-table fetch was quadratic with swipe history
    /// (SWIPE-03 / APP-08).
    private func fetchSwipeRecords(matching assetId: String) -> [SwipeRecord] {
        let descriptor = FetchDescriptor<SwipeRecord>(
            predicate: #Predicate { $0.assetLocalIdentifier == assetId }
        )
        return (try? modelContext.fetch(descriptor)) ?? []
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

    /// All asset local identifiers with a swipe record. SwiftData on iOS 17 has
    /// no column projection (Core Data's `propertiesToFetch` has no SwiftData
    /// equivalent), so the full model is fetched and mapped — but the records
    /// themselves are tiny and this runs once per session, not per swipe.
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
