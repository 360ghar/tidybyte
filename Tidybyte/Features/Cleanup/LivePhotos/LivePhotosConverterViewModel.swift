import SwiftUI
import SwiftData
import Photos

enum ConversionState {
    case idle
    case converting
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
        guard !convertingAll else { return }
        guard let index = items.firstIndex(where: { $0.id == itemId }) else { return }
        // Captured before the await: a post-delete fetch returns nothing.
        let size = items[index].asset.fileSize
        errorMessage = nil
        do {
            let deletedIds = try await photoService.deleteAssets(identifiers: [itemId])
            CleanupLedger.shared.record(kind: .livePhotos, deletedIds: deletedIds, sizeOf: { _ in size })
            items.removeAll { deletedIds.contains($0.id) }
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
        guard !convertingAll else { return }
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
        guard !convertingAll else { return }
        guard let index = items.firstIndex(where: { $0.id == itemId }) else { return }
        errorMessage = nil
        items[index].conversionState = .converting

        do {
            let savedBytes = try await performConversion(assetId: itemId, modelContext: modelContext)
            // Re-lookup: the array may have shifted during the await.
            if let idx = items.firstIndex(where: { $0.id == itemId }) {
                items[idx].savedBytes = savedBytes
                items[idx].conversionState = .completed
            }
        } catch {
            if let idx = items.firstIndex(where: { $0.id == itemId }) {
                items[idx].conversionState = .failed(error.localizedDescription)
            }
            errorMessage = error.localizedDescription
        }
    }

    func convertAll(modelContext: ModelContext) async {
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
        var converted = 0
        var failed = 0
        for itemId in pendingIds {
            // D2: cancellation checked at the top of every iteration — this loop
            // deletes originals, so it must be stoppable at every step.
            if isCancelled { break }
            guard let index = items.firstIndex(where: { $0.id == itemId }) else { continue }
            items[index].conversionState = .converting
            do {
                let savedBytes = try await performConversion(assetId: itemId, modelContext: modelContext, albumIdentifiers: albumMap[itemId] ?? [])
                converted += 1
                // Re-lookup: the array may have shifted during the await.
                if let idx = items.firstIndex(where: { $0.id == itemId }) {
                    items[idx].savedBytes = savedBytes
                    items[idx].conversionState = .completed
                }
            } catch {
                failed += 1
                if let idx = items.firstIndex(where: { $0.id == itemId }) {
                    items[idx].conversionState = .failed(error.localizedDescription)
                }
            }
        }
        convertingAll = false
        lastBatch = (converted: converted, failed: failed)
        // COMP-09: one aggregated message instead of reporting only the last
        // error.
        if failed > 0 {
            errorMessage = "Converted \(converted) of \(pendingIds.count). \(failed) failed."
        }
    }

    private func performConversion(assetId: String, modelContext: ModelContext, albumIdentifiers: [String]? = nil) async throws -> Int64 {
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
        let journal = try CompressionJournal.beginPending(
            modelContext: modelContext,
            mediaType: .livePhoto,
            assetId: assetId,
            originalSize: originalSize,
            compressedSize: 0,
            exportPreset: "still"
        )

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

        // Capture album membership before deleting the original (batch callers
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
        CompressionJournal.markSaveAttempted(journal, modelContext: modelContext)
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
            CompressionJournal.finalize(journal, outcome: .failed, modelContext: modelContext)
            throw LivePhotoError.invalidImageData
        }
        // D1: the durable new copy exists — record it in the journal at the
        // earliest crash point that could strand a duplicate.
        CompressionJournal.recordReplacement(journal, replacementId: replacementId, compressedSize: Int64(imageData.count), modelContext: modelContext)

        // Restore album membership on the replacement (best effort).
        for albumId in resolvedAlbumIds {
            do {
                try await photoService.addToAlbum(assetIdentifiers: [replacementId], albumIdentifier: albumId)
            } catch {
                AppLog.photo.error("Failed to restore album \(albumId, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }

        // Delete the original Live Photo only after confirming the new still
        // exists. If deletion fails, roll the replacement back so we don't
        // leave a duplicate behind (COMP-02).
        do {
            try await photoService.deleteAssets(identifiers: [assetId])
        } catch {
            var rollbackSucceeded = false
            do {
                try await photoService.deleteAssets(identifiers: [replacementId])
                rollbackSucceeded = true
            } catch {
                rollbackSucceeded = false
            }
            // Journal: on successful rollback nothing durable remains (the row
            // resolves now); if rollback also failed the replacement is still in
            // the library, so leave the row PENDING — only `reconcile` (which
            // looks at pending rows) can remove the stranded copy, and a
            // finalized row would hide it from that cleanup permanently.
            if rollbackSucceeded {
                CompressionJournal.finalize(journal, outcome: .failed, modelContext: modelContext)
            }
            throw LivePhotoError.originalDeletionFailed(rollbackSucceeded: rollbackSucceeded)
        }

        // Journal the replacement's actual byte size (not the savings): history
        // computes savedBytes as originalSizeBytes - compressedSizeBytes.
        journal.compressedSizeBytes = Int64(imageData.count)
        CompressionJournal.finalize(journal, outcome: .completed, modelContext: modelContext)
        return max(0, originalSize - Int64(imageData.count))
    }
}

enum LivePhotoError: LocalizedError {
    case assetNotFound
    case noPhotoResource
    case invalidImageData
    case conversionTimedOut
    case originalDeletionFailed(rollbackSucceeded: Bool)

    var errorDescription: String? {
        switch self {
        case .assetNotFound: "Live Photo not found."
        case .noPhotoResource: "Could not find still image in Live Photo."
        case .invalidImageData: "Invalid image data."
        case .conversionTimedOut: "Timed out loading the photo (it may still be in iCloud). Please try again."
        case .originalDeletionFailed(let rollbackSucceeded):
            if rollbackSucceeded {
                "Converted copy saved, but the original couldn't be deleted. We removed the new copy to avoid a duplicate."
            } else {
                "Converted copy saved, but the original couldn't be deleted, and the new copy couldn't be removed either. Check your library for a duplicate."
            }
        }
    }
}
