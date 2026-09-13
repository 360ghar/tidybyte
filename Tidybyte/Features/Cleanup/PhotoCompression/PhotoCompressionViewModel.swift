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

    func loadIfNeeded() async {
        guard !hasLoadedPhotos else { return }
        await load()
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        // Live Photos have their own tool; re-encoding only their still would
        // silently drop the motion component, so exclude them here.
        let photoAssets = await photoService.fetchAllPhotos().filter { !$0.isLivePhoto }
        photos = photoAssets.map { PhotoItem(id: $0.id, asset: $0, selectedPreset: defaultPreset) }
        hasLoadedPhotos = true
        isLoading = false
    }

    /// Re-fetch without flipping `isLoading`, so existing content stays under the pull-to-refresh spinner.
    func refresh() async {
        // Don't replace `photos` out from under an in-flight compression loop —
        // its per-id index lookups would miss and savings/records would be lost.
        guard !isCompressing else { return }
        errorMessage = nil
        let photoAssets = await photoService.fetchAllPhotos().filter { !$0.isLivePhoto }
        photos = photoAssets.map { PhotoItem(id: $0.id, asset: $0, selectedPreset: defaultPreset) }
        hasLoadedPhotos = true
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
            photos.removeAll { $0.id == id }
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
    /// save+delete in the services).
    func cancelCompression() {
        isCancelled = true
        batchTask?.cancel()
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

        // COMP-16: skip assets that already have a completed record so they are
        // never re-encoded (quality degradation).
        let previouslyCompletedIds: Set<String> = ((try? modelContext.fetch(
            FetchDescriptor<CompressionRecord>(predicate: #Predicate { $0.outcome == "completed" })
        )) ?? []).reduce(into: Set<String>()) { $0.insert($1.assetLocalIdentifier) }

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
            setExporting: { [weak self] index, progress in
                guard let self else { return }
                self.photos[index].compressionState = .exporting(progress)
            },
            setKeptOriginal: { [weak self] index, reason in
                guard let self else { return }
                self.photos[index].compressionState = .keptOriginal(reason: reason)
            },
            setCompleted: { [weak self] index, saved in
                guard let self else { return }
                self.photos[index].compressionState = .completed(savedBytes: saved)
            },
            setFailed: { [weak self] index, message in
                guard let self else { return }
                self.photos[index].compressionState = .failed(message)
            },
            setWaiting: { [weak self] index in
                guard let self else { return }
                self.photos[index].compressionState = .waiting
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

                    swap.finalizeCompleted(compressedSize: compressResult.compressedSize)
                    return .completed(
                        originalSize: compressResult.originalSize,
                        compressedSize: compressResult.compressedSize
                    )
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
        photos.removeAll { successfulIds.contains($0.id) }
        selectedIds.subtract(successfulIds)
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
