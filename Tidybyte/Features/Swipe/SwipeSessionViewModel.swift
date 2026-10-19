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
    private(set) var analysisProgress: Float = 0
    private(set) var skippedAnalysisCount = 0
    private var loadGeneration = 0
    private let visionService = VisionAnalysisService()
    private let intelligence = LocalPhotoIntelligence()
    private var cardReason: (asset: AssetSummary, text: String)?
    var reviewReason: String? {
        guard cardReason?.asset == currentAsset else { return nil }
        return cardReason?.text
    }

    func refreshReviewReason() async {
        cardReason = nil
        guard let asset = currentAsset, !showCompletion, await intelligence.isAvailable() else { return }
        let epoch = ScanResults.epoch
        do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
        guard !Task.isCancelled, currentAsset == asset else { return }
        // Not `fetchAssets`: that waits behind any library-wide scan in flight,
        // which on a large library holds the hint back for minutes.
        let current = await fetchDetails(for: [asset.id])[asset.id]
        guard !Task.isCancelled, current == asset else { return }
        let image = asset.mediaType == .photo && !asset.isScreenshot
            ? await photoService.loadAnalysisImage(for: asset.id, targetSize: CGSize(width: 512, height: 512))?.cgImage : nil
        let reason = await intelligence.reviewReason(asset: asset, image: image)
        guard !Task.isCancelled else { return }
        applyReviewReason(reason, for: asset, epoch: epoch)
    }

    func applyReviewReason(_ reason: String?, for asset: AssetSummary, epoch: Int) {
        guard currentAsset == asset, epoch == ScanResults.epoch, !showCompletion else { return }
        if let reason { cardReason = (asset, reason) }
    }
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

    /// Pixel size of the deck's render area, published by `SwipeCardDeck` on
    /// every geometry change (deck size × display scale). Every image request
    /// this session makes — the first window, the on-advance prefetch, and the
    /// cache release — is sized from this, so the decode target follows the deck
    /// through a live resize (fold, unfold, Split View, Stage Manager) instead
    /// of the device screen. Stays `.zero` until the deck has laid out;
    /// prefetching waits for it rather than guessing a size.
    private(set) var renderTarget: CGSize = .zero

    /// `assets[..<detailedEnd]` hold complete summaries. The cards after it
    /// are deck listings (no file size, filename or iCloud state) until
    /// `detailUpcoming()` reaches them.
    private var detailedEnd = 0
    private var isDetailing = false
    private static let detailWindow = 40
    /// Complete summaries for deck ids. Reads PhotoKit; replaced in tests.
    var loadDetails: @Sendable ([String]) -> [String: AssetSummary]
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
        self.loadDetails = { [photoService] ids in photoService.fetchSummaries(for: ids) }
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
        loadGeneration += 1
        let token = loadGeneration
        let epoch = ScanResults.epoch
        defer { if token == loadGeneration { isLoading = false } }
        analysisProgress = 0
        skippedAnalysisCount = 0
        allPhotosAlreadySwiped = false

        let swipedIds = fetchSwipedIdentifiers()

        let fetched: [AssetSummary]
        switch filter {
        case .worstShots:
            let all = await photoService.fetchAllPhotos()
            guard !Task.isCancelled, token == loadGeneration else { return }
            let candidates = Self.collapsingBursts(all).filter(Self.isWorstShotCandidate)
            let phByID = photoService.phAssetsById(candidates.map(\.id))
            var scored: [(asset: AssetSummary, result: AestheticsResult)] = []
            for (index, asset) in candidates.enumerated() {
                guard !Task.isCancelled, token == loadGeneration else { return }
                if index % 20 == 0 { await Task.yield() }
                if let phAsset = phByID[asset.id],
                   let image = await photoService.loadAnalysisImage(for: phAsset, targetSize: CGSize(width: 512, height: 512))?.cgImage,
                   let result = await visionService.analyzeAesthetics(image: image) {
                    guard !Task.isCancelled, token == loadGeneration else { return }
                    if result.isLowQuality { scored.append((asset, result)) }
                } else if token == loadGeneration {
                    skippedAnalysisCount += 1
                }
                guard !Task.isCancelled, token == loadGeneration else { return }
                analysisProgress = Float(index + 1) / Float(max(1, candidates.count))
            }
            guard !Task.isCancelled, token == loadGeneration else { return }
            guard epoch == ScanResults.epoch else {
                // `errorMessage` is a String handed to a banner, so it has to be
                // looked up where it is built — nothing downstream can localize it.
                errorMessage = L10n.string("Your library changed during analysis. Try Worst Shots again.")
                hasLoadedInitialAssets = true
                return
            }
            fetched = scored.sorted(by: Self.worstShotOrder).map(\.asset)
        case .notSwipedYet:
            let allAssets = await photoService.fetchDeckListing(filter: .allMedia)
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
            fetched = await photoService.fetchDeckListing(filter: filter)
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
        guard !Task.isCancelled, token == loadGeneration else { return }
        var listed = Self.deckAssets(deck, excludingPending: pendingDeletionIds)
        if filter == .worstShots {
            // Scored from complete summaries already.
            detailedEnd = listed.count
        } else {
            // The listing has no file sizes or iCloud state; fill them in for
            // the first cards before showing any.
            let firstDetails = 0..<min(Self.detailWindow, listed.count)
            let ids = listed[firstDetails].map(\.id)
            let details = await fetchDetails(for: ids)
            guard !Task.isCancelled, token == loadGeneration else { return }
            Self.apply(details, to: &listed, in: firstDetails)
            detailedEnd = firstDetails.upperBound
        }
        assets = listed
        currentIndex = 0
        // Undo entries point into the old deck; after a reload they would
        // rewind to cards that are no longer in it.
        undoStack.removeAll()
        hasLoadedInitialAssets = true
        isLoading = false

        // Pre-cache the first window in the background (matches advance()).
        // Sized from the deck's own render target: if the deck has not measured
        // itself yet this is a no-op, and the deck's first geometry change runs
        // it rather than prefetching at a guessed size.
        prefetchUpcoming(includingCurrent: true)
    }

    func cancelLoading() {
        loadGeneration += 1
        isLoading = false
    }

    nonisolated static func isWorstShotCandidate(_ asset: AssetSummary) -> Bool {
        asset.mediaType == .photo && !asset.isFavorite && !asset.isScreenshot
    }

    nonisolated static func worstShotOrder(
        _ lhs: (asset: AssetSummary, result: AestheticsResult),
        _ rhs: (asset: AssetSummary, result: AestheticsResult)
    ) -> Bool {
        if lhs.result.score != rhs.result.score { return lhs.result.score < rhs.result.score }
        if lhs.asset.creationDate != rhs.asset.creationDate {
            return (lhs.asset.creationDate ?? .distantPast) < (rhs.asset.creationDate ?? .distantPast)
        }
        return lhs.asset.id < rhs.asset.id
    }

    /// A reload ("Try Again" after the deck ran out) must not show photos that
    /// are already marked for deletion. A marked photo shown again could be
    /// kept, yet stay on the delete list and be deleted at commit.
    nonisolated static func deckAssets(_ fetched: [AssetSummary], excludingPending pending: [String]) -> [AssetSummary] {
        guard !pending.isEmpty else { return fetched }
        let pendingSet = Set(pending)
        return fetched.filter { !pendingSet.contains($0.id) }
    }

    /// True while this photo is still waiting on the batch commit, which is the
    /// only state an undo can bring it back from. `undoStack` is not
    /// authoritative on its own: a committed or discarded batch leaves its
    /// `.deleted` entries on the stack, so a caller that trusts the stack alone
    /// can accept an undo that does nothing.
    func isPendingDeletion(_ assetId: String) -> Bool {
        pendingDeletionSizeById[assetId] != nil
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
        guard let asset = pendingKeepAsset else { return L10n.string("No photo is waiting to be filed. Dismiss and try again.") }
        guard !isPerformingMutation else { return L10n.string("Still adding — please wait a moment and try again.") }
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
            return L10n.format("Failed to add to album: %@", error.localizedDescription)
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
                errorMessage = L10n.format("Failed to undo album change: %@", error.localizedDescription)
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
        do {
            let result = try await photoService.deleteAssets(identifiers: pendingDeletionIds)
            let confirmedIds = result.deletedIds
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
        } catch is CancellationError {
            // A cancel is not a failure: nothing was deleted, so stay quiet
            // instead of reporting "Failed to delete N photos". The pending
            // list stays, exactly as for "Don't Allow".
        } catch let error as PhotoServiceError {
            // Partial failure: some assets WERE deleted. Reconcile state to the
            // survivors first, then surface an honest retry message (B6).
            var handled = false
            if let result = error.deletionOutcome {
                let succeededIds = result.removedIds
                // Bytes from the pre-delete size map — a post-delete fetch of
                // these ids is empty (they are gone), which is what inflated
                // pendingDeletionBytes before (B6). sessionStats stays as-is:
                // swipeLeft already counted every pending id optimistically,
                // so succeeded ids are covered; a retry or discard resolves.
                // Like the success path, only pre-delete-existing ids count —
                // externally-vanished ids clear from pending but add no bytes.
                let confirmedSucceeded = result.deletedIds
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
                deletionErrorMessage = Self.deletionFailureMessage(count: pendingDeletionIds.count, error: error)
            }
        } catch {
            deletionErrorMessage = Self.deletionFailureMessage(count: pendingDeletionIds.count, error: error)
        }
        isDeletingBatch = false
    }

    /// One place for the failure copy, so the two catch paths above cannot
    /// drift apart, and the plural form goes through the catalog instead of an
    /// appended "s".
    nonisolated static func deletionFailureMessage(count: Int, error: Error) -> String {
        L10n.format(
            "Failed to delete %lld photo",
            fallback: "Failed to delete %lld photos",
            count
        ) + ": \(error.localizedDescription)"
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

    /// Called by `SwipeCardDeck` whenever its measured size (or the display
    /// scale) changes. An unchanged target is a no-op, so an ordinary layout
    /// pass cannot restart the prefetch. On a real change — a fold, unfold, or
    /// any resize — the entries cached at the old size are released at that
    /// size (PhotoKit matches on `targetSize`) and the visible window is
    /// re-cached at the new one, so the deck stops decoding for the old pose.
    func updateRenderTarget(_ target: CGSize) {
        guard target != renderTarget, target.width > 0, target.height > 0 else { return }
        let previous = renderTarget
        renderTarget = target
        if previous != .zero, !cachedAssetIDs.isEmpty {
            let releasing = Array(cachedAssetIDs)
            cachedAssetIDs.removeAll()
            Task {
                await photoService.stopCaching(assetIds: releasing, targetSize: previous)
            }
        }
        prefetchUpcoming(includingCurrent: true)
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
            detailVisibleCards()
            // Pre-cache upcoming images
            prefetchUpcoming(includingCurrent: false)
            detailUpcoming()
        }
        // Release images that fell out of the visible + prefetch window so a
        // long session doesn't pin hundreds of images in the cache (SWIPE-01).
        releaseCachedAssetsOutsideWindow()
    }

    /// Replaces deck listings with complete summaries ahead of the current
    /// card, a window at a time, so a card has its file size and iCloud state
    /// before it is shown.
    private func detailUpcoming() {
        guard !isDetailing, detailedEnd < assets.count,
              detailedEnd - currentIndex < Self.detailWindow / 2 else { return }
        let range = detailedEnd..<min(detailedEnd + Self.detailWindow, assets.count)
        let ids = assets[range].map(\.id)
        let token = loadGeneration
        isDetailing = true
        Task {
            let details = await fetchDetails(for: ids)
            isDetailing = false
            guard token == loadGeneration else { return }
            Self.apply(details, to: &assets, in: range)
            detailedEnd = max(detailedEnd, range.upperBound)
            detailUpcoming()
        }
    }

    /// The window normally stays far ahead of the deck. If a fast run of
    /// swipes outruns it, the cards on screen are filled in here, on the spot,
    /// so no decision is recorded against a listing (which has no file size).
    private func detailVisibleCards() {
        let visibleEnd = min(currentIndex + 3, assets.count)
        guard detailedEnd < visibleEnd else { return }
        let range = detailedEnd..<visibleEnd
        Self.apply(loadDetails(assets[range].map(\.id)), to: &assets, in: range)
        detailedEnd = visibleEnd
    }

    /// `loadDetails`, off the main actor.
    private func fetchDetails(for ids: [String]) async -> [String: AssetSummary] {
        await Task.detached(priority: .userInitiated) { [loadDetails] in loadDetails(ids) }.value
    }

    nonisolated static func apply(_ details: [String: AssetSummary], to deck: inout [AssetSummary], in range: Range<Int>) {
        for index in range where index < deck.count {
            if let detail = details[deck[index].id] { deck[index] = detail }
        }
    }

    /// Caches the images the deck is about to show, at the deck's own size.
    /// The window matches `releaseCachedAssetsOutsideWindow`'s, so a card is
    /// never released while it is still about to be shown. Sized from
    /// `renderTarget`: with no measured deck there is nothing to size against,
    /// and the deck's first geometry change re-runs this.
    private func prefetchUpcoming(includingCurrent: Bool) {
        guard renderTarget != .zero else { return }
        let start = includingCurrent ? currentIndex : currentIndex + 1
        let end = min(max(currentIndex, 0) + 10, assets.count)
        guard start < end else { return }
        let ids = Array(assets[start..<end].map(\.id))
        guard !ids.isEmpty else { return }
        cachedAssetIDs.formUnion(ids)
        let target = renderTarget
        Task {
            await photoService.startCaching(assetIds: ids, targetSize: target)
        }
    }

    /// Stops caching every asset that is no longer in the visible + prefetch
    /// window `[currentIndex, currentIndex + 10)` (SWIPE-01).
    private func releaseCachedAssetsOutsideWindow() {
        let windowEnd = min(currentIndex + 10, assets.count)
        guard currentIndex < windowEnd else { return }
        let window = Set(assets[currentIndex..<windowEnd].map(\.id))
        let stale = cachedAssetIDs.subtracting(window)
        // Nothing can be cached before the deck has published a target, and
        // PhotoKit only releases an entry at the size it was cached with.
        guard !stale.isEmpty, renderTarget != .zero else { return }
        cachedAssetIDs.subtract(stale)
        let target = renderTarget
        Task {
            await photoService.stopCaching(assetIds: Array(stale), targetSize: target)
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
            errorMessage = L10n.string("Couldn't save your changes. Please try again.")
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
