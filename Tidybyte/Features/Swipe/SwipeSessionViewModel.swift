import SwiftUI
import SwiftData
import Photos

struct SessionStats: Sendable {
    var deletedCount: Int = 0
    var keptCount: Int = 0
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
    /// Per-id sizes for pending deletions, captured at swipe time. `assets`
    /// excludes pending ids after a reload (`deckAssets`), so commit-time sizes
    /// can't be rebuilt from `assets` alone — this map survives reloads and
    /// fills the gap. It holds exactly the ids in `pendingDeletionIds`.
    var pendingDeletionSizeById: [String: Int64] = [:]
    var pendingDeletionBytes: Int64 { pendingDeletionSizeById.values.reduce(0, +) }
    var isDeletingBatch = false
    var deletionCommitted = false
    /// Session-scoped exact accounting of what the photo library confirmed as
    /// deleted, across all commit attempts. `sessionStats` stays optimistic
    /// while a batch is pending; these replace it at commit/discard time so a
    /// partial failure can neither double-count nor wipe earlier successes.
    private var committedDeletionCount = 0
    private var committedDeletionBytes: Int64 = 0

    /// True when deletions are awaiting commit. Gates exits from the session and
    /// completion flow so pending deletions are never dropped silently (SWIPE-02).
    var hasPendingDeletions: Bool {
        !pendingDeletionIds.isEmpty && !deletionCommitted
    }

    /// Set when an external launch (deep link / widget / intent) asked for a new
    /// session while this one still held uncommitted deletions. SwipeSessionView
    /// observes it and pushes the completion review instead of tearing the
    /// session down (A1). Observable (not ignored) precisely so the view can
    /// watch it.
    private(set) var deletionReviewRequested = false

    /// Flags the completion review without discarding any pending state. The
    /// queued filter stays parked in `AppNavigation.pendingSwipeFilter` and is
    /// consumed by SwipeHomeView once this session is gone.
    func requestDeletionReview() {
        deletionReviewRequested = true
    }

    func clearDeletionReviewRequest() {
        deletionReviewRequested = false
    }

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
            // Collapse before the swipe filter: filtering first lets a reviewed
            // keeper's unreviewed siblings win the next session's collapse and
            // return. Burst-level exclusion covers a keeper that changed since
            // the review — any burst with a recorded frame is done.
            let collapsed = Self.collapsingBursts(allAssets)
            let swipedBurstIds = Set(allAssets.filter { swipedIds.contains($0.id) }.compactMap(\.burstIdentifier))
            let filtered = collapsed.filter {
                !swipedIds.contains($0.id) && ($0.burstIdentifier.map { !swipedBurstIds.contains($0) } ?? true)
            }
            if filtered.isEmpty && !allAssets.isEmpty {
                allPhotosAlreadySwiped = true
            }
            fetched = filtered
        default:
            fetched = await photoService.fetchAssets(filter: filter)
        }

        // One card per burst, like the Photos app: the frames are near copies
        // and belong to the Bursts tool. An explicit id list is left alone.
        let deck: [AssetSummary]
        switch filter {
        case .customAssetIds, .notSwipedYet: // .notSwipedYet is collapsed above
            deck = fetched
        default:
            deck = Self.collapsingBursts(fetched)
        }
        assets = Self.deckAssets(deck, excludingPending: pendingDeletionIds)
        currentIndex = 0
        // Undo entries point into the old deck; after a reload they would
        // rewind to cards that are no longer in it.
        undoStack.removeAll()
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

    /// A reload ("Try Again" after the deck ran out) must not show photos that
    /// are already marked for deletion. A marked photo shown again could be
    /// kept, yet stay on the delete list and be deleted at commit.
    nonisolated static func deckAssets(_ fetched: [AssetSummary], excludingPending pending: [String]) -> [AssetSummary] {
        guard !pending.isEmpty else { return fetched }
        let pendingSet = Set(pending)
        return fetched.filter { !pendingSet.contains($0.id) }
    }

    /// A keep, file or skip always wins over an earlier delete mark for the
    /// same photo. Without this, a kept photo would still be deleted at commit.
    private func unmarkPendingDeletion(_ asset: AssetSummary) {
        guard pendingDeletionSizeById.removeValue(forKey: asset.id) != nil else { return }
        pendingDeletionIds.removeAll { $0 == asset.id }
        sessionStats.deletedCount = max(0, sessionStats.deletedCount - 1)
        sessionStats.deletedBytes = max(0, sessionStats.deletedBytes - asset.fileSize)
    }

    /// Keeps one frame per burst: the user's pick, then iPhone's pick, then
    /// the first frame. Order of the list is kept.
    nonisolated static func collapsingBursts(_ assets: [AssetSummary]) -> [AssetSummary] {
        var keeper: [String: AssetSummary] = [:]
        for asset in assets {
            guard let burst = asset.burstIdentifier else { continue }
            if let current = keeper[burst], current.burstPick >= asset.burstPick { continue }
            keeper[burst] = asset
        }
        return assets.filter { asset in
            guard let burst = asset.burstIdentifier else { return true }
            return keeper[burst]?.id == asset.id
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
            pendingDeletionSizeById[asset.id] = asset.fileSize
            sessionStats.deletedCount += 1
            sessionStats.deletedBytes += asset.fileSize
            undoStack.append(SwipeUndoEntry(asset: asset, decision: .deleted, albumId: nil))
        }
        advance()
    }

    /// Plain keep: no album picker, no interruption. Filing into an album is
    /// an explicit up-swipe or album-button action (`keepWithAlbum`).
    func swipeRight() {
        // Guard against a second keep overwriting one that is still awaiting
        // album selection behind the presented sheet.
        guard let asset = currentAsset, pendingKeepAsset == nil, !isPerformingMutation else { return }
        unmarkPendingDeletion(asset)
        sessionStats.keptCount += 1
        undoStack.append(SwipeUndoEntry(asset: asset, decision: .kept, albumId: nil))
        upsertSwipeRecord(asset: asset, decision: .kept)
        advance()
    }

    /// Opens the album picker for the top card. Invoked by the up-swipe gesture
    /// and the action-bar album button — filing a photo is an explicit intent,
    /// never a side effect of keeping it.
    func keepWithAlbum() {
        // Guard against a second filing request overwriting one that is still
        // awaiting album selection.
        guard let asset = currentAsset, pendingKeepAsset == nil, !isPerformingMutation else { return }
        pendingKeepAsset = asset
        showAlbumPicker = true
    }

    /// Adds the pending keep to the album. Returns nil on success, or a
    /// user-facing error message on failure — AlbumPickerSheet presents it in
    /// its own alert, because an error written to `errorMessage` here would
    /// render in an alert *behind* the presented sheet and never be seen (B4).
    func addToAlbum(albumId: String) async -> String? {
        // A nil pending asset or an in-flight add is a real failure, not a
        // success: returning nil would make the picker record recents and
        // dismiss as if the photo had been filed.
        guard let asset = pendingKeepAsset else { return "No photo is waiting to be filed. Dismiss and try again." }
        guard !isPerformingMutation else { return "Still adding — please wait a moment and try again." }
        isPerformingMutation = true
        defer { isPerformingMutation = false }

        do {
            try await photoService.addToAlbum(assetIdentifiers: [asset.id], albumIdentifier: albumId)
            unmarkPendingDeletion(asset)
            sessionStats.organizedCount += 1
            undoStack.append(SwipeUndoEntry(asset: asset, decision: .addedToAlbum, albumId: albumId))
            upsertSwipeRecord(asset: asset, decision: .addedToAlbum, albumId: albumId)
            pendingKeepAsset = nil
            showAlbumPicker = false
            advance()
            return nil
        } catch {
            return "Failed to add to album: \(error.localizedDescription)"
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

    /// "Keep Without Album": the user swiped up to keep the photo, then chose
    /// no album. Recorded as a keep, not a skip.
    func skipKeep() {
        guard let asset = pendingKeepAsset, !isPerformingMutation else { return }
        unmarkPendingDeletion(asset)
        sessionStats.keptCount += 1
        undoStack.append(SwipeUndoEntry(asset: asset, decision: .kept, albumId: nil))
        upsertSwipeRecord(asset: asset, decision: .kept)
        pendingKeepAsset = nil
        showAlbumPicker = false
        advance()
    }

    func skip() {
        guard let asset = currentAsset, !isPerformingMutation else { return }
        unmarkPendingDeletion(asset)
        sessionStats.skippedCount += 1
        undoStack.append(SwipeUndoEntry(asset: asset, decision: .skipped, albumId: nil))
        upsertSwipeRecord(asset: asset, decision: .skipped)
        advance()
    }

    func undo() async {
        // The album picker is presented on top of the deck — rewinding the deck
        // underneath the sheet would desync the card the user is choosing an
        // album for (SWIPE-06).
        //
        // Undo is also blocked while a commit is in flight — rewinding into
        // the captured batch would show a "restored" card that is actually
        // being deleted right now (B2).
        guard let entry = undoStack.last, !isPerformingMutation, !showAlbumPicker,
              !isDeletingBatch else { return }

        switch entry.decision {
        case .deleted:
            undoStack.removeLast()
            // Not pending any more (a partial commit already deleted it):
            // drop the stale entry without rewinding to a deleted photo.
            guard pendingDeletionSizeById[entry.asset.id] != nil else { return }
            unmarkPendingDeletion(entry.asset)
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
            sessionStats.keptCount = max(0, sessionStats.keptCount - 1)
            currentIndex = max(0, currentIndex - 1)
            deleteSwipeRecord(for: entry.asset.id)
        }
    }

    func commitDeletions() async {
        guard !pendingDeletionIds.isEmpty, !isDeletingBatch else { return }
        isDeletingBatch = true
        // Sizes come from the in-memory session assets (no re-fetch): only ids
        // the library confirms as deleted are counted, so assets that vanished
        // externally before commit can't overstate "Storage Freed" (SWIPE-08).
        // Merged with pre-exclusion pending sizes: after a reload `assets`
        // drops pending ids (`deckAssets`), so rebuilding from `assets` alone
        // reports zero freed bytes for them.
        let sizeById = pendingDeletionSizeById
        // Fresh pre-delete existence check: deleteAssets' fast path returns
        // every requested id, including assets that vanished externally (iCloud
        // sync, the Photos app) between session load and commit. Only ids
        // present here count toward bytes, stats, and the ledger — the pending
        // list itself still clears, since "not in the library" is the goal
        // state either way.
        let existingIds = await photoService.existingIds(pendingDeletionIds)
        do {
            let deletedIds = try await photoService.deleteAssets(identifiers: pendingDeletionIds)
            let confirmedIds = deletedIds.intersection(existingIds)
            let freedBytes = confirmedIds.reduce(Int64(0)) { sum, id in sum + (sizeById[id] ?? 0) }
            committedDeletionCount += confirmedIds.count
            committedDeletionBytes += freedBytes
            CleanupLedger.shared.record(kind: .swipe, deletedIds: confirmedIds, sizeOf: { sizeById[$0] ?? 0 })
            deletionCommitted = true
            // Replace the optimistic per-swipe tally with the exact one — same
            // visible result on first-pass success, no double-count on retry.
            sessionStats.deletedCount = committedDeletionCount
            sessionStats.deletedBytes = committedDeletionBytes
            pendingDeletionIds.removeAll()
            pendingDeletionSizeById.removeAll()
            HapticHelper.notification(.success)
        } catch let error as PhotoServiceError {
            // Partial failure: some assets WERE deleted. Reconcile state to the
            // survivors first, then surface an honest retry message (B6).
            var handled = false
            if let succeededIds = error.succeededIds {
                // Bytes from the pre-delete size map — a post-delete fetch of
                // these ids is empty (they are gone), which is what inflated
                // pendingDeletionBytes before (B6). sessionStats stays as-is:
                // swipeLeft already counted every pending id optimistically,
                // so succeeded ids are covered; a retry or discard resolves.
                // Like the success path, only pre-delete-existing ids count —
                // externally-vanished ids clear from pending but add no bytes.
                let confirmedSucceeded = succeededIds.intersection(existingIds)
                let succeededBytes = confirmedSucceeded.reduce(Int64(0)) { sum, id in sum + (sizeById[id] ?? 0) }
                committedDeletionCount += confirmedSucceeded.count
                committedDeletionBytes += succeededBytes
                CleanupLedger.shared.record(kind: .swipe, deletedIds: confirmedSucceeded, sizeOf: { sizeById[$0] ?? 0 })
                pendingDeletionIds.removeAll { succeededIds.contains($0) }
                for id in succeededIds { pendingDeletionSizeById.removeValue(forKey: id) }
                deletionCommitted = pendingDeletionIds.isEmpty
                // The per-item retry may have cleared the batch entirely —
                // that's success, not an error.
                handled = pendingDeletionIds.isEmpty
                if handled { HapticHelper.notification(.success) }
            }
            // "Don't Allow" is the user's choice, not a failure: the pending
            // list stays so they can confirm again.
            if !handled, case .userDeclined = error { handled = true }
            if !handled {
                deletionErrorMessage = "Failed to delete \(pendingDeletionIds.count) photo\(pendingDeletionIds.count == 1 ? "" : "s"): \(error.localizedDescription)"
            }
        } catch {
            deletionErrorMessage = "Failed to delete \(pendingDeletionIds.count) photo\(pendingDeletionIds.count == 1 ? "" : "s"): \(error.localizedDescription)"
        }
        isDeletingBatch = false
    }

    func discardPendingDeletions() {
        // Pending deletions were never persisted, so there are no swipe records to
        // remove — just clear the in-memory state. Deletions the library already
        // confirmed stay in the stats; only the optimistic pending tally goes.
        sessionStats.deletedCount = committedDeletionCount
        sessionStats.deletedBytes = committedDeletionBytes
        pendingDeletionIds.removeAll()
        pendingDeletionSizeById.removeAll()
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
