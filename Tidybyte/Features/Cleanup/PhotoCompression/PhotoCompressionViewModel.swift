import SwiftUI
import SwiftData

struct PhotoItem: Identifiable {
    let id: String
    let asset: AssetSummary
    var compressionState: CompressionState = .waiting
    var selectedPreset: PhotoCompressionPreset = PhotoCompressionPreset.presets[0]
}

@Observable
@MainActor
final class PhotoCompressionViewModel {
    var photos: [PhotoItem] = []
    var isLoading = true
    private(set) var hasLoadedPhotos = false
    var selectedIds: Set<String> = []
    var isCompressing = false
    var errorMessage: String?
    var insufficientDiskSpace = false
    var isDeleting = false
    /// Per-batch outcome counts, set once the loop finishes so the view can
    /// show a single summary / success haptic (COMP-09, COMP-11).
    var batchSummary: CompressionBatchSummary?
    private(set) var isCancelled = false
    /// Which step of the replace batch is running, for the bottom bar.
    private(set) var phase: ReplacePhase = .idle
    /// Saved copies whose originals are still in the library (the user tapped
    /// "Don't Allow"). The view offers Try Again / Remove Copies.
    /// `OriginalsCommit.commit` already settles them as kept-both in the journal.
    var keptOriginals: [PendingOriginal] = []
    /// The batch mutation loop, owned by the VM so leaving the screen can
    /// cancel it instead of orphaning the mutation loop (COMP-08).
    private var batchTask: Task<Void, Never>?

    var defaultPresetId: String {
        get { AppPreferences.defaultPhotoCompressionPresetID() }
        set { AppPreferences.saveDefaultPhotoCompressionPresetID(newValue) }
    }

    private let photoService = PhotoLibraryService.shared
    private let compressionService: PhotoCompressionService

    init() {
        compressionService = PhotoCompressionService(photoService: photoService)
    }

    var defaultPreset: PhotoCompressionPreset {
        PhotoCompressionPreset.presets.first { $0.id == defaultPresetId } ?? PhotoCompressionPreset.presets[0]
    }

    /// Cached sort ORDER (ids only, C13 parity with ScreenshotCleanerViewModel):
    /// `sortedPhotos` used to re-sort on every access, and progress ticks +
    /// `body` touch it repeatedly. Sort keys are immutable (`fileSize`), so the
    /// order is recomputed only when the id set changes. Items are always
    /// mapped from the current `photos`, so preset/state edits never render
    /// stale copies.
    private var cachedSortedPhotoOrder: [String] = []
    private var cachedSortedPhotoIdSet: Set<String> = []

    var sortedPhotos: [PhotoItem] {
        let ids = Set(photos.map(\.id))
        if ids != cachedSortedPhotoIdSet {
            cachedSortedPhotoOrder = photos.sorted { $0.asset.fileSize > $1.asset.fileSize }.map(\.id)
            cachedSortedPhotoIdSet = ids
        }
        let byId = Dictionary(uniqueKeysWithValues: photos.map { ($0.id, $0) })
        return cachedSortedPhotoOrder.compactMap { byId[$0] }
    }

    var selectedSize: Int64 {
        photos.totalFileSize(selectedIds: selectedIds, idOf: \.id, sizeOf: { $0.asset.fileSize })
    }

    /// Every eligible photo from the last fetch; `photos` is this list after
    /// the candidate filter.
    private var allPhotoAssets: [AssetSummary] = []
    /// New copies this tool (or video / Live Photo conversion) already made.
    /// Compressing a copy again only loses quality, so they are never listed.
    private var compressedCopyIds: Set<String> = []

    /// Off: only photos over 2 MB that are not HEIC (the ones that shrink).
    var showAllPhotos = false {
        didSet { applyFilter() }
    }

    /// True when the candidate filter hides photos that exist. Set in
    /// `applyFilter`, so a render never re-scans the whole library.
    private(set) var filterHidesPhotos = false
    /// How many photos the "show all" list would hold. Counted once per fetch,
    /// then kept current by `removePhotos`.
    private var eligibleCount = 0

    nonisolated static func candidates(
        from assets: [AssetSummary],
        excluding compressedCopies: Set<String>,
        showAll: Bool
    ) -> [AssetSummary] {
        assets.filter { isCandidate($0, excluding: compressedCopies, showAll: showAll) }
    }

    /// The list rule, shared with the Cleanup home badge.
    nonisolated static func isCandidate(_ asset: AssetSummary, excluding compressedCopies: Set<String>, showAll: Bool) -> Bool {
        // Live Photos have their own tool; re-encoding only their still
        // would silently drop the motion.
        guard !asset.isLivePhoto, !compressedCopies.contains(asset.id) else { return false }
        return showAll
            || (asset.fileSize >= CleanupLibraryRollup.photoCompressionMinBytes && !asset.isHEIC)
    }

    func loadIfNeeded(modelContext: ModelContext) async {
        guard !hasLoadedPhotos else { return }
        isLoading = true
        errorMessage = nil
        await fetch(modelContext: modelContext)
        isLoading = false
    }

    /// Re-fetch without flipping `isLoading`, so existing content stays under the pull-to-refresh spinner.
    func refresh(modelContext: ModelContext) async {
        // Don't replace `photos` out from under an in-flight compression loop —
        // its per-id index lookups would miss and savings/records would be lost.
        guard !isCompressing else { return }
        errorMessage = nil
        await fetch(modelContext: modelContext)
    }

    private func fetch(modelContext: ModelContext) async {
        compressedCopyIds = CompressionJournal.savedCopyIds(modelContext: modelContext)
        allPhotoAssets = await photoService.fetchAllPhotos()
        eligibleCount = Self.candidates(from: allPhotoAssets, excluding: compressedCopyIds, showAll: true).count
        applyFilter()
        hasLoadedPhotos = true
    }

    /// Drops photos that left the library (deleted, or replaced by a copy)
    /// from the list AND from the last fetch, so toggling the filter can
    /// never bring a deleted original back.
    private func removePhotos(_ ids: Set<String>) {
        guard !ids.isEmpty else { return }
        photos.removeAll { ids.contains($0.id) }
        eligibleCount -= allPhotoAssets
            .filter { ids.contains($0.id) && Self.isCandidate($0, excluding: compressedCopyIds, showAll: true) }
            .count
        allPhotoAssets.removeAll { ids.contains($0.id) }
        updateFilterHidesPhotos()
    }

    private func updateFilterHidesPhotos() {
        filterHidesPhotos = !showAllPhotos && photos.count < eligibleCount
    }

    /// Rebuilds `photos` from the last fetch. Per-row quality picks and row
    /// states ("Already compressed", failure reasons) survive.
    private func applyFilter() {
        guard !isCompressing else { return }
        let previous = Dictionary(photos.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        photos = Self.candidates(from: allPhotoAssets, excluding: compressedCopyIds, showAll: showAllPhotos)
            .map { asset in
                var item = PhotoItem(id: asset.id, asset: asset, selectedPreset: previous[asset.id]?.selectedPreset ?? defaultPreset)
                if let state = previous[asset.id]?.compressionState { item.compressionState = state }
                return item
            }
        selectedIds.formIntersection(photos.map(\.id))
        updateFilterHidesPhotos()
    }

    func toggleSelection(_ id: String) {
        selectedIds.toggle(id)
    }

    var allSelected: Bool {
        !photos.isEmpty && selectedIds.count == photos.count
    }

    func selectAll() {
        selectedIds = Set(photos.map(\.id))
    }

    func deselectAll() {
        selectedIds.removeAll()
    }

    /// The bottom-bar quality picker: one choice for every selected photo.
    func setPresetForSelected(_ preset: PhotoCompressionPreset) {
        for index in photos.indices where selectedIds.contains(photos[index].id) {
            photos[index].selectedPreset = preset
        }
    }

    /// The shared preset of the selection, or nil when it is mixed.
    var selectedPreset: PhotoCompressionPreset? {
        let presets = photos.filter { selectedIds.contains($0.id) }.map(\.selectedPreset)
        guard let first = presets.first, presets.allSatisfy({ $0.id == first.id }) else { return nil }
        return first
    }

    func setPreset(_ preset: PhotoCompressionPreset, for photoId: String) {
        if let index = photos.firstIndex(where: { $0.id == photoId }) {
            photos[index].selectedPreset = preset
        }
    }

    /// Conservative synchronous savings estimate for the row hint: scale the
    /// original by quality and, when downscaling, by the area ratio.
    func estimateSize(for photo: PhotoItem) -> Int64 {
        var factor = Double(photo.selectedPreset.quality)
        if let maxDim = photo.selectedPreset.maxDimension {
            let longest = Double(max(photo.asset.pixelWidth, photo.asset.pixelHeight))
            if longest > Double(maxDim) {
                let scale = Double(maxDim) / longest
                factor *= scale * scale
            }
        }
        return Int64(Double(photo.asset.fileSize) * min(factor, 1.0))
    }

    func deletePhoto(id: String) async -> Bool {
        guard !isDeleting, !isCompressing else { return !photos.contains(where: { $0.id == id }) }
        errorMessage = nil
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await photoService.deleteAssets(identifiers: [id])
            removePhotos([id])
            selectedIds.remove(id)
        } catch {
            errorMessage = error.localizedDescription
        }
        return !photos.contains(where: { $0.id == id })
    }

    /// Starts the batch on a VM-owned task so the screen can cancel it on
    /// disappear (COMP-08). Idempotent while a batch is running.
    func startBatchCompression(modelContext: ModelContext) {
        guard batchTask == nil else { return }
        batchTask = Task { [weak self] in
            await self?.compressSelected(modelContext: modelContext)
            self?.batchTask = nil
        }
    }

    /// Requests cancellation of the running batch: sets the flag the loop
    /// checks and cancels the VM-owned task (which also stops any in-flight
    /// save in the services). Copies already saved still go to the one
    /// delete-originals commit.
    func cancelCompression() {
        isCancelled = true
        batchTask?.cancel()
    }

    /// "Try Again" on the Originals Kept alert: one more delete commit.
    /// Clears `keptOriginals` synchronously so the alert does not re-present.
    func retryRemovingOriginals() {
        let items = keptOriginals
        keptOriginals = []
        guard !items.isEmpty else { return }
        isCompressing = true
        Task {
            let outcome = await OriginalsCommit.commit(items) { phase = $0 }
            let done = Set(outcome.committed.map(\.assetId))
            removePhotos(done)
            selectedIds.subtract(done)
            // A copy that vanished since the decline leaves its item failed:
            // the original was never deleted, so it goes back to waiting for
            // another Compress instead of staying on a kept state that no
            // alert offers to act on.
            let missingIds = Set(outcome.failed.map(\.assetId))
            for index in photos.indices where missingIds.contains(photos[index].id) {
                photos[index].compressionState = .waiting
            }
            isCompressing = false
            keptOriginals = outcome.kept
            if !outcome.failed.isEmpty {
                errorMessage = OriginalsCommit.missingReplacementMessage
            }
            // A retry that completes the delete IS a clean batch success, but
            // `batchSummary` is unchanged so the view's `.onChange` never
            // re-fires and the success haptic is lost. Play it here, matching
            // the other cleanup tools.
            if !done.isEmpty, outcome.failed.isEmpty, outcome.kept.isEmpty {
                HapticHelper.notification(.success)
            }
        }
    }

    /// "Remove Copies" on the Originals Kept alert: the originals stay, the
    /// new copies go.
    func removeCopies() {
        let items = keptOriginals
        keptOriginals = []
        guard !items.isEmpty else { return }
        isCompressing = true
        Task {
            let outcome = await OriginalsCommit.removeCopies(items)
            // A decline leaves both versions: say so instead of going quiet.
            if !outcome.allCopiesRemoved {
                errorMessage = OriginalsCommit.copiesKeptMessage
            }
            // An original that vanished outside the app is already replaced, so
            // its saved copy is the library's asset now — stop listing the row
            // instead of claiming both versions are present.
            let doneIds = Set(outcome.completed.map(\.assetId))
            removePhotos(doneIds)
            selectedIds.subtract(doneIds)
            // Declined rows stay non-eligible: their copies are still in the
            // library (journaled as kept), so offering Compress again would
            // strand another duplicate. Rows whose copies went back to waiting
            // are the ones the journal nilled a `replacementId` for.
            let keptIds = Set(outcome.kept.map(\.assetId))
            let remaining = Set(items.map(\.assetId)).subtracting(doneIds)
            for index in photos.indices where remaining.contains(photos[index].id) {
                if keptIds.contains(photos[index].id) {
                    photos[index].compressionState = .keptOriginal(reason: "Original kept — both versions in your library")
                } else {
                    photos[index].compressionState = .waiting
                }
            }
            // A decline leaves the decision open, so the Originals Kept alert
            // (and the preview cover, which reads the same state) keeps
            // offering Try Again and Remove Copies for the rows whose copies
            // are still in the library.
            keptOriginals = outcome.kept
            isCompressing = false
        }
    }

    func compressSelected(modelContext: ModelContext) async {
        guard !selectedIds.isEmpty, !isCompressing, !isDeleting else { return }
        errorMessage = nil
        batchSummary = nil

        // Re-encoding needs scratch space for the temp file; keep parity with the
        // video tool's headroom check.
        insufficientDiskSpace = false
        let totalSelectedSize = selectedSize
        if let freeSpace = try? URL(fileURLWithPath: NSHomeDirectory())
            .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            .volumeAvailableCapacityForImportantUsage,
           freeSpace < Int64(Double(totalSelectedSize) * 2.0) {
            insufficientDiskSpace = true
            return
        }

        isCompressing = true
        isCancelled = false

        // COMP-16: skip assets that already have a usable copy — completed
        // swaps, no-savings skips, and kept-both declines — so they are never
        // re-encoded (quality degradation, duplicate copies).
        //
        // The copy must still be in the library: a kept-both row whose copy the
        // user deleted in Photos would otherwise block its original from ever
        // being compressed again ("Already compressed" forever).
        let settled = CompressionJournal.settledReplacements(modelContext: modelContext)
        let liveReplacements = await photoService.existingIds(Array(settled.values))
        let previouslyCompletedIds = Set(settled.filter { liveReplacements.contains($0.value) }.keys)

        // D1: resolve leftovers from any interrupted swap BEFORE the batch.
        await CompressionJournal.reconcile(modelContext: modelContext)

        // COMP-12: deterministic batch order (descending file size, id tiebreak)
        // matching the on-screen list instead of nondeterministic Set iteration.
        // Owned by CompressionBatchRunner.run; the VM only builds the inputs.
        let fileSizes = photos.reduce(into: [String: Int64]()) { $0[$1.id] = $1.asset.fileSize }

        // O(1) row lookup for the batch: `refresh()` and per-item delete are
        // both no-ops while `isCompressing`, so no structural mutation can
        // reorder rows mid-batch and these indices stay valid until the
        // terminal removeAll below.
        let indexById = Dictionary(uniqueKeysWithValues: photos.enumerated().map { ($1.id, $0) })

        let handlers = CompressionBatchRunner.Handlers(
            setState: { [weak self] index, state in
                self?.photos[index].compressionState = state
            },
            setPhase: { [weak self] phase in
                self?.phase = phase
            }
        )

        let isSizeUnknown: @MainActor @Sendable (Error) -> Bool = { error in
            guard let compressionError = error as? PhotoCompressionError else { return false }
            if case .sizeUnknown = compressionError { return true }
            return false
        }

        let result = await CompressionBatchRunner.run(
            selected: selectedIds,
            fileSizes: fileSizes,
            indexById: indexById,
            alreadyCompletedIds: previouslyCompletedIds,
            isCancelled: { [weak self] in self?.isCancelled ?? true },
            isSizeUnknown: isSizeUnknown,
            modelContext: modelContext,
            handlers: handlers,
            execute: { [weak self] id, index, report in
                guard let self else { throw CancellationError() }
                let preset = self.photos[index].selectedPreset
                let originalSize = self.photos[index].asset.fileSize
                // D1: journal the swap before it starts (see VideoCompressionViewModel).
                // Throws when the pending row is not durable — that aborts this
                // item before any library write (no journal, no swap).
                let swap = try CompressionSwap(
                    mediaType: .photo,
                    assetId: id,
                    originalSize: originalSize,
                    exportPreset: preset.id,
                    modelContext: modelContext
                )
                do {
                    let compressResult = try await self.compressionService.compressPhoto(
                        assetId: id,
                        preset: preset,
                        // D1: the library write is about to start — from here a crash
                        // could strand a copy whose id the journal never learned.
                        onSaveWillCommit: {
                            swap.markSaveAttempted()
                        },
                        onReplacementSaved: { replacementId, compressedSize in
                            swap.recordReplacement(id: replacementId, size: compressedSize)
                        },
                        onProgress: { progress in
                            report(progress)
                        }
                    )

                    if compressResult.skipped {
                        // COMP-04: no-savings items stay in the list with an
                        // explanation instead of silently vanishing.
                        swap.finalizeSkipped()
                        self.photos[index].compressionState = .keptOriginal(reason: "No savings — kept original")
                        return .skipped
                    }

                    // Step 1 done. The original stays until the runner's single
                    // delete commit, which finalizes this journal row.
                    return .saved(PendingOriginal(
                        assetId: id,
                        originalSize: compressResult.originalSize,
                        compressedSize: compressResult.compressedSize,
                        swap: swap
                    ))
                } catch {
                    if self.isCancelled || error is CancellationError {
                        // A cancel is not a failure: History must not render a red
                        // badge for something the batch summary reports as cancelled.
                        await swap.markSkipped(assetId: id)
                        throw error
                    }
                    if let compressionError = error as? PhotoCompressionError,
                       case .sizeUnknown = compressionError {
                        // COMP-07: iCloud-only / unknown size — leave the original
                        // alone. An intentional skip, not a failure.
                        await swap.markSkipped(assetId: id)
                        throw error
                    }
                    await swap.markFailed(assetId: id)
                    throw error
                }
            }
        )
        let successfulIds = result.successfulIds
        let completedCount = result.summary.completed
        let failedCount = result.summary.failed
        let skippedCount = result.summary.skipped

        // COMP-04: remove only successfully compressed (and deleted) items;
        // skipped ones stay so the user can see why they were left alone.
        removePhotos(successfulIds)
        selectedIds.subtract(successfulIds)
        keptOriginals = result.kept
        isCompressing = false
        batchSummary = CompressionBatchSummary(
            completed: completedCount,
            failed: failedCount,
            skipped: skippedCount,
            cancelled: isCancelled
        )

        // COMP-11: one aggregated summary after the batch instead of an alert
        // popping per item mid-loop.
        if failedCount > 0 {
            let attempted = completedCount + failedCount
            errorMessage = "Compressed \(completedCount) of \(attempted). \(failedCount) failed."
        }
    }
}
