import SwiftUI
import SwiftData
import Photos

enum ConversionState {
    case idle
    case converting
    /// Step 1 done: the still is saved. The Live Photo is deleted in step 2.
    case copySaved
    case completed
    case failed(String)
}

struct LivePhotoItem: Identifiable {
    let id: String
    let asset: AssetSummary
    var conversionState: ConversionState = .idle
    var savedBytes: Int64 = 0
}

@Observable
@MainActor
final class LivePhotosConverterViewModel {
    var items: [LivePhotoItem] = []
    var isLoading = true
    private(set) var hasLoadedItems = false
    var selectedIds: Set<String> = []
    var isSelectionMode = false
    var convertingAll = false
    var errorMessage: String?
    /// Outcome of the most recent Convert All, so the view can decide the
    /// haptic/summary (COMP-09): success only when `failed == 0`.
    var lastBatch: (converted: Int, failed: Int)?
    private(set) var isCancelled = false
    /// Which step of the conversion is running, for the bottom bar.
    private(set) var phase: ReplacePhase = .idle
    /// Saved stills whose Live Photos are still in the library (the user
    /// tapped "Don't Allow"). The view offers Try Again / Remove Copies.
    /// `OriginalsCommit.commit` already settles them as kept-both in the journal.
    var keptOriginals: [PendingOriginal] = []
    /// True while a single conversion or a retry runs, so row buttons and
    /// Convert All stay disabled.
    private(set) var isBusy = false
    /// D2: the Convert-All loop, owned by the VM so leaving the screen can
    /// cancel it instead of letting it keep converting (and deleting originals)
    /// with no way to stop — COMP-08 was never ported to this tool.
    private var batchTask: Task<Void, Never>?

    private let photoService = PhotoLibraryService.shared

    /// Album names keyed by asset id, populated in a single pass over the
    /// user's albums (O(albums)) — COMP-13. The blocking PhotoKit enumeration
    /// runs off the main actor via `AlbumMembershipLoader` (D12).
    private(set) var albumNamesByAsset: [String: [String]] = [:]

    func refreshAlbumNames(for itemIds: Set<String>) async {
        guard !itemIds.isEmpty else {
            albumNamesByAsset = [:]
            return
        }
        albumNamesByAsset = await AlbumMembershipLoader.membership(for: itemIds)
    }

    var totalSize: Int64 {
        items.reduce(0) { $0 + $1.asset.fileSize }
    }

    var estimatedSavings: Int64 {
        // Live Photos are roughly 2x the size of stills
        items.reduce(0) { $0 + $1.asset.fileSize / 2 }
    }

    var deletedCount: Int = 0

    func indexOfItem(id: String) -> Int? {
        items.firstIndex(where: { $0.id == id })
    }

    /// Deletes a Live Photo outright (removes both the still and the motion
    /// component) without creating a replacement. Use when the user decides
    /// the Live Photo is junk from the preview. Album membership is dropped
    /// automatically by iOS on delete.
    func deleteLivePhoto(itemId: String) async {
        // COMP-18: never delete outright while Convert All is running — the
        // batch may be converting (and about to delete) this same item.
        guard !convertingAll, !isBusy else { return }
        guard let index = items.firstIndex(where: { $0.id == itemId }) else { return }
        // Captured before the await: a post-delete fetch returns nothing.
        let size = items[index].asset.fileSize
        CleanupLedger.shared.dismissDeletionNotice()
        errorMessage = nil
        do {
            let result = try await photoService.deleteAssets(identifiers: [itemId])
            let deletedIds = result.deletedIds
            CleanupLedger.shared.record(kind: .livePhotos, deletedIds: deletedIds, sizeOf: { _ in size })
            items.removeAll { result.removedIds.contains($0.id) }
            deletedCount += deletedIds.count
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadIfNeeded() async {
        guard !hasLoadedItems else { return }
        await load()
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        let livePhotos = await photoService.fetchLivePhotos()
        items = livePhotos.map { LivePhotoItem(id: $0.id, asset: $0) }
        hasLoadedItems = true
        isLoading = false
    }

    /// Re-fetches Live Photos without toggling `isLoading`, so the existing list
    /// stays visible under the pull-to-refresh spinner instead of flashing the skeleton.
    /// D3: blocked during Convert All — replacing rows mid-batch resets every
    /// row's state and lets the user re-tap Convert on an item whose original is
    /// already deleted (guaranteed assetNotFound failure).
    func refresh() async {
        guard !convertingAll, !isBusy else { return }
        errorMessage = nil
        let livePhotos = await photoService.fetchLivePhotos()
        items = livePhotos.map { LivePhotoItem(id: $0.id, asset: $0) }
        hasLoadedItems = true
    }

    /// D2: starts Convert All on a VM-owned task so leaving the screen cancels
    /// it. Idempotent while running.
    func startConvertAll(modelContext: ModelContext) {
        guard batchTask == nil else { return }
        batchTask = Task { [weak self] in
            await self?.convertAll(modelContext: modelContext)
            self?.batchTask = nil
        }
    }

    /// D2: requests cancellation of the running batch.
    func cancelConvertAll() {
        isCancelled = true
        batchTask?.cancel()
    }

    func convertSingle(itemId: String, modelContext: ModelContext) async {
        // COMP-18: never start a single conversion while Convert All is
        // running (double spinners, double counts).
        guard !convertingAll, !isBusy else { return }
        guard let index = items.firstIndex(where: { $0.id == itemId }) else { return }
        errorMessage = nil
        isBusy = true
        defer { isBusy = false }
        items[index].conversionState = .converting

        do {
            let pending = try await performConversion(assetId: itemId, modelContext: modelContext)
            setState(.copySaved, for: itemId)
            let result = await commitOriginals([pending])
            if result.failed > 0 {
                errorMessage = OriginalsCommit.missingStillMessage
            }
        } catch {
            setState(.failed(error.localizedDescription), for: itemId)
            errorMessage = error.localizedDescription
        }
    }

    /// Step 2: delete the Live Photos of every saved still in one call (one
    /// iOS prompt). Returns how many were committed and how many failed.
    @discardableResult
    private func commitOriginals(_ pending: [PendingOriginal]) async -> (committed: Int, failed: Int) {
        guard !pending.isEmpty else { return (0, 0) }
        let outcome = await OriginalsCommit.commit(pending) { phase = $0 }
        let indexById = Dictionary(items.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
        for item in outcome.committed {
            if let idx = indexById[item.assetId] {
                items[idx].savedBytes = max(0, item.originalSize - item.compressedSize)
                items[idx].conversionState = .completed
            }
        }
        // A still that vanished mid-batch fails its item: the Live Photo was
        // never deleted, so the row must offer Convert again instead of sitting
        // on `.copySaved`, which has no action at all.
        for item in outcome.failed {
            if let idx = indexById[item.assetId] {
                items[idx].conversionState = .failed(OriginalsCommit.missingStillMessage)
            }
        }
        keptOriginals = outcome.kept
        return (outcome.committed.count, outcome.failed.count)
    }

    /// "Try Again" on the Originals Kept alert. Clears `keptOriginals`
    /// synchronously so the alert does not re-present.
    func retryRemovingOriginals() {
        let pending = keptOriginals
        keptOriginals = []
        guard !pending.isEmpty else { return }
        isBusy = true
        Task {
            await commitOriginals(pending)
            isBusy = false
        }
    }

    /// "Remove Copies" on the Originals Kept alert: the Live Photos stay,
    /// the new stills go.
    func removeCopies() {
        let pending = keptOriginals
        keptOriginals = []
        guard !pending.isEmpty else { return }
        isBusy = true
        Task {
            let outcome = await OriginalsCommit.removeCopies(pending)
            // A decline leaves both versions: say so instead of going quiet.
            if !outcome.allCopiesRemoved {
                errorMessage = OriginalsCommit.copiesKeptMessage
            }
            // A Live Photo that vanished outside the app is already replaced by
            // its still, so stop listing it instead of offering another convert.
            let doneIds = Set(outcome.completed.map(\.assetId))
            items.removeAll { doneIds.contains($0.id) }
            for item in pending where !doneIds.contains(item.assetId) {
                setState(.idle, for: item.assetId)
            }
            isBusy = false
        }
    }

    private func setState(_ state: ConversionState, for itemId: String) {
        // Re-lookup: the array may have shifted during an await.
        if let idx = items.firstIndex(where: { $0.id == itemId }) {
            items[idx].conversionState = state
        }
    }

    func convertAll(modelContext: ModelContext) async {
        guard !isBusy else { return }
        errorMessage = nil
        isCancelled = false
        convertingAll = true
        // D1 (review pass): resolve leftovers from interrupted conversions
        // before starting a batch.
        await CompressionJournal.reconcile(modelContext: modelContext)
        // COMP-09: snapshot the eligible (idle) ids up front so the summary's
        // denominator matches what was actually attempted.
        let pendingIds = items.compactMap { item -> String? in
            guard case .idle = item.conversionState else { return nil }
            return item.id
        }
        // One album pass for the whole batch instead of one predicate scan
        // per album per item inside `performConversion`.
        let albumMap = await photoService.userAlbumIdentifiers(for: Set(pendingIds))
        var saved: [PendingOriginal] = []
        var failed = 0
        for (offset, itemId) in pendingIds.enumerated() {
            // D2: cancellation checked at the top of every iteration.
            if isCancelled { break }
            phase = .savingCopies(done: offset, total: pendingIds.count)
            guard let index = items.firstIndex(where: { $0.id == itemId }) else { continue }
            items[index].conversionState = .converting
            do {
                let pending = try await performConversion(assetId: itemId, modelContext: modelContext, albumIdentifiers: albumMap[itemId] ?? [])
                saved.append(pending)
                setState(.copySaved, for: itemId)
            } catch {
                if isCancelled || error is CancellationError {
                    // A cancel is not a failure: the row goes back to idle so
                    // it stays eligible for a later run.
                    setState(.idle, for: itemId)
                    break
                }
                failed += 1
                setState(.failed(error.localizedDescription), for: itemId)
            }
        }
        // Step 2: one delete for every saved still — one iOS prompt. Also runs
        // after a Stop, so finished items finish.
        let result = await commitOriginals(saved)
        let totalFailed = failed + result.failed
        phase = .idle
        convertingAll = false
        lastBatch = (converted: result.committed, failed: totalFailed)
        // COMP-09: one aggregated message instead of reporting only the last
        // error.
        if totalFailed > 0 {
            errorMessage = "Converted \(result.committed) of \(pendingIds.count). \(totalFailed) failed."
        }
    }

    /// Step 1 of a conversion: save the still as a new asset. The Live Photo
    /// itself is deleted later, in `commitOriginals`.
    private func performConversion(assetId: String, modelContext: ModelContext, albumIdentifiers: [String]? = nil) async throws -> PendingOriginal {
        guard let phAsset = photoService.getPHAsset(for: assetId) else {
            throw LivePhotoError.assetNotFound
        }

        let resources = PHAssetResource.assetResources(for: phAsset)
        guard let photoResource = resources.first(where: { $0.type == .photo }) else {
            throw LivePhotoError.noPhotoResource
        }

        let originalSize = resources.reduce(Int64(0)) { total, resource in
            guard resource.responds(to: NSSelectorFromString("fileSize")),
                  let size = resource.value(forKey: "fileSize") as? Int64 else {
                return total
            }
            return total + size
        }

        // D1 (review pass): journal this swap like video/photo compression so a
        // crash mid-conversion can't leave a permanent Live Photo duplicate.
        // Throws when the pending row is not durable — that aborts the
        // conversion before any library write (no journal, no swap).
        let swap = try CompressionSwap(
            mediaType: .livePhoto,
            assetId: assetId,
            originalSize: originalSize,
            exportPreset: "still",
            modelContext: modelContext
        )

        do {
            // Read the still-image resource bytes directly. Writing these bytes back
            // (rather than decoding to a UIImage and re-encoding) preserves the
            // original quality and EXIF metadata.
            let resourceManager = PHAssetResourceManager.default()
            let imageData = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
                let resumer = ThrowingContinuationResumer(continuation)
                var data = Data()
                let options = PHAssetResourceRequestOptions()
                options.isNetworkAccessAllowed = true

                // Network access is allowed, so a stalled iCloud download could leave
                // the completion handler unfired forever. Bound it with a timeout +
                // request cancellation, wired before the request so even a synchronous
                // callback cancels the timer. Without this the item hangs in `.converting`.
                var requestID: PHAssetResourceDataRequestID = 0
                let timeoutTask = Task {
                    try? await Task.sleep(for: .seconds(30))
                    resumer.resume(throwing: LivePhotoError.conversionTimedOut)
                }
                resumer.onResume = {
                    resourceManager.cancelDataRequest(requestID)
                    timeoutTask.cancel()
                }

                requestID = resourceManager.requestData(
                    for: photoResource,
                    options: options
                ) { chunk in
                    data.append(chunk)
                } completionHandler: { error in
                    if let error {
                        resumer.resume(throwing: error)
                    } else {
                        resumer.resume(returning: data)
                    }
                }
            }

            guard !imageData.isEmpty else {
                throw LivePhotoError.invalidImageData
            }

            // Capture album membership for the new still (batch callers
            // pass the precomputed map; single conversions look it up directly).
            let resolvedAlbumIds: [String]
            if let precomputed = albumIdentifiers {
                resolvedAlbumIds = precomputed
            } else {
                resolvedAlbumIds = await photoService.userAlbumIdentifiers(containing: assetId)
            }

            // Save as a new still photo, preserving the original's metadata
            // (including hidden state — COMP-17). Burst membership cannot be
            // carried over: PHAssetCreationRequest has no burst-linkage API, so a
            // converted still loses its burst grouping.
            //
            // D1: the still is about to be written to the library — from here a
            // crash could strand a copy whose id the journal never learned.
            swap.markSaveAttempted()
            var placeholder: PHObjectPlaceholder?
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                let resourceOptions = PHAssetResourceCreationOptions()
                resourceOptions.originalFilename = photoResource.originalFilename
                request.addResource(with: .photo, data: imageData, options: resourceOptions)
                request.creationDate = phAsset.creationDate
                request.location = phAsset.location
                request.isFavorite = phAsset.isFavorite
                request.isHidden = phAsset.isHidden
                placeholder = request.placeholderForCreatedAsset
            }

            guard let replacementId = placeholder?.localIdentifier else {
                await swap.markFailed(assetId: assetId)
                throw LivePhotoError.invalidImageData
            }
            // D1: the durable new copy exists — record it in the journal at the
            // earliest crash point that could strand a duplicate.
            swap.recordReplacement(id: replacementId, size: Int64(imageData.count))

            // Restore album membership on the replacement (best effort).
            for albumId in resolvedAlbumIds {
                do {
                    try await photoService.addToAlbum(assetIdentifiers: [replacementId], albumIdentifier: albumId)
                } catch {
                    AppLog.photo.error("Failed to restore album \(albumId, privacy: .public): \(error.localizedDescription, privacy: .public)")
                }
            }

            // The Live Photo is NOT deleted here: the caller deletes all originals
            // in one `OriginalsCommit.commit` call (one iOS prompt per batch).
            return PendingOriginal(
                assetId: assetId,
                originalSize: originalSize,
                compressedSize: Int64(imageData.count),
                swap: swap
            )
        } catch {
            // A cancel is not a failure — History must not render a red badge
            // for something the batch summary reports as cancelled. Mirrors the
            // photo and video batch loops.
            if isCancelled || error is CancellationError {
                await swap.markSkipped(assetId: assetId)
                throw error
            }
            await swap.markFailed(assetId: assetId)
            throw error
        }
    }
}

enum LivePhotoError: LocalizedError {
    case assetNotFound
    case noPhotoResource
    case invalidImageData
    case conversionTimedOut

    var errorDescription: String? {
        switch self {
        case .assetNotFound: "Live Photo not found."
        case .noPhotoResource: "Could not find still image in Live Photo."
        case .invalidImageData: "Invalid image data."
        case .conversionTimedOut: "Timed out loading the photo (it may still be in iCloud). Please try again."
        }
    }
}
